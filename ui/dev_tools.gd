class_name DevTools
extends CanvasLayer

signal panel_toggled(open: bool)

@export var player_path: NodePath = NodePath("../Player")
@export var statue_path: NodePath = NodePath("../StatueGhost")
@export var crawler_path: NodePath = NodePath("../CrawlerGhost")
@export var door_director_path: NodePath = NodePath("../DoorAttackDirector")

var panel_open: bool = false
var _mouse_mode_before_open: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

@onready var panel: PanelContainer = $Panel
@onready var invincible_toggle: CheckButton = $Panel/Margin/Content/Invincible
@onready var fast_toggle: CheckButton = $Panel/Margin/Content/FastMovement
@onready var entrance_picker: OptionButton = $Panel/Margin/Content/DoorRow/Entrance
@onready var status_label: Label = $Panel/Margin/Content/Status


func _ready() -> void:
	for entrance_id: int in range(1, 8):
		entrance_picker.add_item("Cửa %02d" % entrance_id, entrance_id)
	invincible_toggle.toggled.connect(set_invincibility_enabled)
	fast_toggle.toggled.connect(set_fast_movement_enabled)
	$Panel/Margin/Content/SpawnStatue.pressed.connect(spawn_statue)
	$Panel/Margin/Content/SpawnCrawler.pressed.connect(spawn_crawler)
	$Panel/Margin/Content/DoorRow/AttackDoor.pressed.connect(force_selected_door_attack)
	$Panel/Margin/Content/Close.pressed.connect(func() -> void: set_panel_open(false))
	set_panel_open(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey \
		and event.pressed \
		and not event.echo \
		and (event.keycode == KEY_F1 or event.physical_keycode == KEY_F1):
		set_panel_open(not panel_open)
		get_viewport().set_input_as_handled()


func set_panel_open(open: bool) -> void:
	if open == panel_open and panel.visible == open:
		return
	panel_open = open
	panel.visible = open
	if open:
		_mouse_mode_before_open = Input.get_mouse_mode()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		status_label.text = "Sẵn sàng. Các thay đổi chỉ dành cho dev."
	else:
		Input.set_mouse_mode(_mouse_mode_before_open)
	panel_toggled.emit(open)


func set_invincibility_enabled(enabled: bool) -> void:
	var player := _player()
	if player and player.has_method("set_dev_invincible"):
		player.call("set_dev_invincible", enabled)
		status_label.text = "Bất tử: %s" % ("BẬT" if enabled else "TẮT")


func set_fast_movement_enabled(enabled: bool) -> void:
	var player := _player()
	if player and player.has_method("set_dev_fast_movement"):
		player.call("set_dev_fast_movement", enabled)
		status_label.text = "Chạy nhanh x3: %s" % ("BẬT" if enabled else "TẮT")


func spawn_statue() -> bool:
	var statue := get_node_or_null(statue_path)
	var player := _player() as CharacterBody3D
	var spawned := statue != null \
		and statue.has_method("dev_force_spawn") \
		and bool(statue.call("dev_force_spawn", player))
	status_label.text = "Statue đã xuất hiện." if spawned else "Không thể gọi Statue."
	return spawned


func spawn_crawler() -> bool:
	var crawler := get_node_or_null(crawler_path)
	var player := _player() as CharacterBody3D
	var spawned := crawler != null \
		and crawler.has_method("dev_force_spawn") \
		and bool(crawler.call("dev_force_spawn", player))
	status_label.text = "Crawler đã xuất hiện." if spawned else "Không thể gọi Crawler."
	return spawned


func set_selected_entrance(entrance_id: int) -> void:
	for index: int in entrance_picker.item_count:
		if entrance_picker.get_item_id(index) == entrance_id:
			entrance_picker.select(index)
			return


func force_selected_door_attack() -> bool:
	var entrance_id := entrance_picker.get_selected_id()
	var director := get_node_or_null(door_director_path)
	var door: Node = null
	if director and director.has_method("start_attack_at_entrance"):
		door = director.call("start_attack_at_entrance", entrance_id) as Node
	var started := is_instance_valid(door)
	status_label.text = (
		"Ma đang tấn công cửa %02d." % entrance_id
		if started
		else "Không thể tấn công cửa %02d (cửa có thể đã vỡ)." % entrance_id
	)
	return started


func _player() -> Node:
	return get_node_or_null(player_path)
