extends ProgressBar

## Bottom-right bladder meter, next to ui/stamina_bar.gd. Unlike that bar,
## this one smooths its displayed value toward the authoritative one instead
## of copying it every frame, and reacts to PlayerBladder's own threshold
## state (read from its exported thresholds, not recomputed independently)
## for its warning/full visual - it never writes back to the bladder.

@export var player_path: NodePath
@export var display_smoothing: float = 6.0

## The accident needs saying out loud. Without it the player's view closes in
## and their sprint stops working with nothing on screen to explain either, and
## a debuff nobody can attribute reads as the game breaking.
const WETTING_TEXT := "ĐANG TÈ DẦM"

var _bladder: PlayerBladder
var _displayed_value: float = 0.0
var _pulse_time: float = 0.0
var _is_warning: bool = false
var _is_full: bool = false
var _is_wetting: bool = false
var _wetting_label: Label

var _style_normal_fill: StyleBoxFlat
var _style_warning_fill: StyleBoxFlat
var _style_full_fill: StyleBoxFlat


func _ready() -> void:
	_style_normal_fill = get_theme_stylebox("fill").duplicate()
	_style_warning_fill = _style_normal_fill.duplicate()
	_style_warning_fill.bg_color = Color(0.82, 0.66, 0.24, 0.96)
	_style_full_fill = _style_normal_fill.duplicate()
	_style_full_fill.bg_color = Color(0.85, 0.28, 0.24, 0.98)
	# Player is our ancestor, so its _ready() (and the @onready `bladder` it
	# assigns) runs *after* ours - defer the bind, same fix as equipment_ui.gd.
	call_deferred("_bind_to_player")


func _bind_to_player() -> void:
	var player := get_node_or_null(player_path)
	if not player or not ("bladder" in player):
		return
	_bladder = player.bladder
	if not _bladder:
		return
	max_value = _bladder.bladder_max
	_displayed_value = _bladder.get_bladder()
	value = _displayed_value
	_bladder.bladder_changed.connect(_on_bladder_changed)
	_bladder.wetting_started.connect(_on_wetting_started)
	_bladder.wetting_ended.connect(_on_wetting_ended)
	_build_wetting_label()
	_is_wetting = _bladder.is_wetting
	_wetting_label.visible = _is_wetting
	_update_visual_state(_bladder.get_bladder())


## Built here rather than authored into player.tscn for the same reason the
## bar's own styles are duplicated at runtime: this is the only node that knows
## about the state, and the scene should not carry a label nothing else reads.
func _build_wetting_label() -> void:
	_wetting_label = Label.new()
	_wetting_label.name = "WettingNotice"
	_wetting_label.text = WETTING_TEXT
	_wetting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wetting_label.add_theme_color_override(&"font_color", Color(1.0, 0.42, 0.34))
	_wetting_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_wetting_label.add_theme_constant_override(&"outline_size", 6)
	_wetting_label.add_theme_font_size_override(&"font_size", 16)
	# Sat above the bar and told not to eat clicks, so it cannot interfere with
	# anything the HUD does below it.
	_wetting_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wetting_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_wetting_label.offset_top = -26.0
	_wetting_label.offset_bottom = -4.0
	_wetting_label.visible = false
	add_child(_wetting_label)


func _on_wetting_started() -> void:
	_is_wetting = true
	if _wetting_label:
		_wetting_label.visible = true
	if _bladder:
		_update_visual_state(_bladder.get_bladder())


func _on_wetting_ended() -> void:
	_is_wetting = false
	if _wetting_label:
		_wetting_label.visible = false
	if _bladder:
		_update_visual_state(_bladder.get_bladder())


func _process(delta: float) -> void:
	if not _bladder:
		return
	var blend := minf(display_smoothing * delta, 1.0)
	_displayed_value = lerpf(_displayed_value, _bladder.get_bladder(), blend)
	value = _displayed_value
	_update_pulse(delta)


func _on_bladder_changed(current: float, max_val: float) -> void:
	max_value = max_val
	_update_visual_state(current)


func _update_visual_state(current: float) -> void:
	_is_warning = current >= _bladder.bladder_warning_threshold
	# An accident keeps the alarm dressing for its whole length. Reading it off
	# the level alone would drop the bar back to normal colours within a second
	# of it starting, while the player is still slowed and half blind.
	_is_full = _is_wetting or current >= _bladder.bladder_full_threshold
	if _is_full:
		add_theme_stylebox_override("fill", _style_full_fill)
	elif _is_warning:
		add_theme_stylebox_override("fill", _style_warning_fill)
	else:
		add_theme_stylebox_override("fill", _style_normal_fill)


## A quiet brightness pulse while warning/full, nothing while normal - the
## meter should stay visually silent until there's something to say.
func _update_pulse(delta: float) -> void:
	if not (_is_warning or _is_full):
		modulate = Color.WHITE
		return
	_pulse_time += delta
	var speed := 4.0 if _is_full else 2.2
	var strength := 0.18 if _is_full else 0.1
	var pulse := 1.0 + sin(_pulse_time * speed) * strength
	modulate = Color(pulse, pulse, pulse, 1.0)
