class_name DevTools
extends CanvasLayer

signal panel_toggled(open: bool)

@export var player_path: NodePath = NodePath("../Player")
@export var statue_path: NodePath = NodePath("../StatueGhost")
@export var crawler_path: NodePath = NodePath("../CrawlerGhost")
@export var hunter_path: NodePath = NodePath("../HunterGhost")
@export var door_director_path: NodePath = NodePath("../DoorAttackDirector")

## Colour of the through-wall entrance markers. Bright enough to read against
## the horror grade, transparent enough not to hide the door behind it.
const XRAY_TINT := Color(0.15, 1.0, 0.72, 0.3)
const XRAY_MARKER_NAME := "DevEntranceXray"

var panel_open: bool = false
var entrance_xray: bool = false
var _mouse_mode_before_open: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

@onready var panel: PanelContainer = $Panel
@onready var invincible_toggle: CheckButton = $Panel/Margin/Content/Invincible
@onready var fast_toggle: CheckButton = $Panel/Margin/Content/FastMovement
@onready var noclip_toggle: CheckButton = $Panel/Margin/Content/Noclip
@onready var xray_toggle: CheckButton = $Panel/Margin/Content/EntranceXray
@onready var entrance_picker: OptionButton = $Panel/Margin/Content/DoorRow/Entrance
@onready var status_label: Label = $Panel/Margin/Content/Status


func _ready() -> void:
	for entrance_id: int in range(1, 8):
		entrance_picker.add_item("Cửa %02d" % entrance_id, entrance_id)
	invincible_toggle.toggled.connect(set_invincibility_enabled)
	fast_toggle.toggled.connect(set_fast_movement_enabled)
	noclip_toggle.toggled.connect(set_noclip_enabled)
	xray_toggle.toggled.connect(set_entrance_xray_enabled)
	$Panel/Margin/Content/SpawnStatue.pressed.connect(spawn_statue)
	$Panel/Margin/Content/SpawnCrawler.pressed.connect(spawn_crawler)
	$Panel/Margin/Content/SpawnHunter.pressed.connect(spawn_hunter)
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


func set_noclip_enabled(enabled: bool) -> void:
	var player := _player()
	if player and player.has_method("set_dev_noclip"):
		player.call("set_dev_noclip", enabled)
		status_label.text = (
			"Bay xuyên tường: BẬT. WASD theo hướng nhìn, Space lên, Ctrl xuống, Shift nhanh."
			if enabled
			else "Bay xuyên tường: TẮT."
		)


## Hangs a see-through-walls marker on every defense door, so all seven
## entrances can be found and counted from anywhere in the house. The marker
## is a child of the door, so it inherits the door's placement and scale and
## needs no separate bookkeeping when doors move.
func set_entrance_xray_enabled(enabled: bool) -> void:
	entrance_xray = enabled
	var doors := get_tree().get_nodes_in_group("defense_doors")
	for door_node: Node in doors:
		var door := door_node as Node3D
		var existing := door.get_node_or_null(XRAY_MARKER_NAME)
		if not enabled:
			if existing:
				existing.queue_free()
			continue
		if not existing:
			door.add_child(_build_xray_marker(int(door.get("entrance_id"))))
	status_label.text = (
		"Soi %d cửa xuyên tường: BẬT." % doors.size()
		if enabled
		else "Soi cửa xuyên tường: TẮT."
	)


func _build_xray_marker(entrance_id: int) -> Node3D:
	var marker := Node3D.new()
	marker.name = XRAY_MARKER_NAME

	var material := StandardMaterial3D.new()
	material.albedo_color = XRAY_TINT
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The whole point is to be visible through the house, so skip the depth
	# test and draw last.
	material.no_depth_test = true
	material.render_priority = 100

	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.4, 2.7, 0.4)
	mesh.material = material
	var box := MeshInstance3D.new()
	box.name = "Volume"
	box.mesh = mesh
	box.position = Vector3(0.0, 1.35, 0.0)
	marker.add_child(box)

	var label := Label3D.new()
	label.name = "Tag"
	label.text = "%02d" % entrance_id
	label.font_size = 160
	label.pixel_size = 0.004
	label.modulate = Color(0.35, 1.0, 0.78)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.outline_size = 24
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 101
	label.fixed_size = true
	label.position = Vector3(0.0, 2.9, 0.0)
	marker.add_child(label)
	return marker


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


## Puts the huntsman in the house without waiting for a door to break. It still
## needs a real breach to ever walk back out, so a forced spawn into an intact
## house seals it in on purpose - which is the state worth testing.
func spawn_hunter() -> bool:
	var hunter := get_node_or_null(hunter_path)
	var player := _player() as CharacterBody3D
	var spawned := hunter != null \
		and hunter.has_method("dev_force_spawn") \
		and bool(hunter.call("dev_force_spawn", player))
	status_label.text = "Thợ Săn đã vào nhà." if spawned else "Không thể gọi Thợ Săn."
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
