extends ProgressBar

## Torch charge, read the same way the stamina bar reads stamina: straight off
## the player every frame, with no state of its own. On a client the value is
## whatever the last server snapshot said, because the authority is the only
## side that spends charge.

@export var player_path: NodePath
## Below this fraction the bar turns to the warning colour. It is the only
## notice a player gets before the torch dies, so it is deliberately early.
@export_range(0.0, 1.0, 0.01) var low_charge_ratio: float = 0.25
@export var normal_color: Color = Color(0.45, 0.9, 1.0, 0.92)
@export var low_color: Color = Color(1.0, 0.44, 0.3, 0.95)

var player: CharacterBody3D
var _fill: StyleBoxFlat


func _ready() -> void:
	if not player_path.is_empty():
		player = get_node_or_null(player_path) as CharacterBody3D
	# Duplicated so recolouring this bar cannot tint every other bar that was
	# authored against the same StyleBox resource.
	var fill := get_theme_stylebox(&"fill") as StyleBoxFlat
	if fill:
		_fill = fill.duplicate() as StyleBoxFlat
		add_theme_stylebox_override(&"fill", _fill)
	_sync_from_player()


func _process(_delta: float) -> void:
	_sync_from_player()


func _sync_from_player() -> void:
	if not is_instance_valid(player):
		return
	max_value = maxf(float(player.get("flashlight_battery_max")), 1.0)
	value = clampf(float(player.get("flashlight_battery")), 0.0, max_value)
	if _fill:
		_fill.bg_color = low_color if value <= max_value * low_charge_ratio else normal_color
	# Off is not the same as empty, and a player who switched the torch off to
	# save it should not read the bar as a fault.
	modulate.a = 1.0 if _flashlight_is_on() else 0.45


func _flashlight_is_on() -> bool:
	return player.has_method(&"is_flashlight_on") and bool(player.call(&"is_flashlight_on"))
