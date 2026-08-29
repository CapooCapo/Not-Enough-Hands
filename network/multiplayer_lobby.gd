extends Control

@onready var player_grid: GridContainer = %PlayerGrid
@onready var room_label: Label = %RoomLabel
@onready var ready_count_label: Label = %ReadyCountLabel
@onready var hint_label: Label = %HintLabel
@onready var status_label: Label = %StatusLabel
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton

var _auto_start_player_count: int = 0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	NetworkManager.roster_changed.connect(_on_roster_changed)
	NetworkManager.status_changed.connect(_on_status_changed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	room_label.text = "UDP %d  ·  %d/%d NGƯỜI" % [
		NetworkManager.session_port,
		NetworkManager.players.size(),
		NetworkManager.MAX_PLAYERS,
	]
	_parse_automation_arguments()
	_render_roster()
	if _should_auto_ready():
		NetworkManager.set_local_ready.call_deferred(true)


func _on_roster_changed(_players: Dictionary) -> void:
	_render_roster()
	_maybe_auto_start.call_deferred()


func _on_status_changed(message: String) -> void:
	status_label.text = message


func _on_ready_pressed() -> void:
	var local_peer_id := multiplayer.get_unique_id()
	NetworkManager.set_local_ready(not NetworkManager.is_player_ready(local_peer_id))


func _on_start_pressed() -> void:
	NetworkManager.request_start_game()


func _on_leave_pressed() -> void:
	NetworkManager.leave_session(true)


func _render_roster() -> void:
	for old_card: Node in player_grid.get_children():
		player_grid.remove_child(old_card)
		old_card.queue_free()

	var peer_ids: Array = NetworkManager.players.keys()
	peer_ids.sort()
	for slot_index: int in NetworkManager.MAX_PLAYERS:
		if slot_index < peer_ids.size():
			var peer_id := int(peer_ids[slot_index])
			player_grid.add_child(_create_player_card(slot_index, peer_id))
		else:
			player_grid.add_child(_create_empty_card(slot_index))

	var ready_count := 0
	for peer_id: int in NetworkManager.players:
		if NetworkManager.is_player_ready(peer_id):
			ready_count += 1
	ready_count_label.text = "%d/%d ĐÃ SẴN SÀNG" % [ready_count, NetworkManager.players.size()]
	room_label.text = "UDP %d  ·  %d/%d NGƯỜI" % [
		NetworkManager.session_port,
		NetworkManager.players.size(),
		NetworkManager.MAX_PLAYERS,
	]

	var local_peer_id := multiplayer.get_unique_id()
	var local_ready := NetworkManager.is_player_ready(local_peer_id)
	ready_button.text = "HỦY SẴN SÀNG" if local_ready else "SẴN SÀNG"
	start_button.visible = NetworkManager.is_local_lobby_host()
	start_button.disabled = not NetworkManager.can_start_game()
	if NetworkManager.is_local_lobby_host():
		hint_label.text = (
			"Tất cả người chơi đã sẵn sàng. Bạn có thể bắt đầu."
			if NetworkManager.can_start_game()
			else "Chờ mọi người bấm SẴN SÀNG."
		)
	else:
		hint_label.text = "Đang chờ chủ phòng bắt đầu trận đấu."


func _create_player_card(slot_index: int, peer_id: int) -> PanelContainer:
	var ready := NetworkManager.is_player_ready(peer_id)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 190)
	panel.add_theme_stylebox_override("panel", _card_style(ready))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)

	var slot_label := Label.new()
	slot_label.text = "NGƯỜI CHƠI %d" % (slot_index + 1)
	slot_label.add_theme_font_size_override("font_size", 14)
	slot_label.add_theme_color_override("font_color", Color(0.45, 0.56, 0.58))
	content.add_child(slot_label)

	var avatar := Label.new()
	avatar.text = "◆"
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.add_theme_font_size_override("font_size", 44)
	avatar.add_theme_color_override(
		"font_color", Color(0.3, 0.9, 0.77) if ready else Color(0.44, 0.51, 0.53)
	)
	content.add_child(avatar)

	var name_label := Label.new()
	name_label.text = NetworkManager.get_player_name(peer_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Color(0.86, 0.92, 0.92))
	content.add_child(name_label)

	var state_label := Label.new()
	state_label.text = "SẴN SÀNG" if ready else "CHƯA SẴN SÀNG"
	if peer_id == NetworkManager.lobby_host_peer_id:
		state_label.text += "  ·  CHỦ PHÒNG"
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.add_theme_font_size_override("font_size", 15)
	state_label.add_theme_color_override(
		"font_color", Color(0.34, 0.95, 0.6) if ready else Color(0.95, 0.35, 0.28)
	)
	content.add_child(state_label)
	return panel


func _create_empty_card(slot_index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 190)
	panel.add_theme_stylebox_override("panel", _card_style(false, true))
	var label := Label.new()
	label.text = "VỊ TRÍ %d\n\nĐANG CHỜ NGƯỜI CHƠI…" % (slot_index + 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.3, 0.38, 0.4))
	panel.add_child(label)
	return panel


func _card_style(ready: bool, empty: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.029, 0.034, 0.72 if not empty else 0.4)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = (
		Color(0.18, 0.64, 0.49, 0.85)
		if ready
		else Color(0.16, 0.25, 0.28, 0.65)
	)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _parse_automation_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--lobby-auto-start="):
			var value := argument.trim_prefix("--lobby-auto-start=")
			if value.is_valid_int():
				_auto_start_player_count = maxi(int(value), 1)


func _should_auto_ready() -> bool:
	var args := OS.get_cmdline_user_args()
	return (
		"--network-smoke" in args
		or "--lobby-auto-ready" in args
		or _auto_start_player_count > 0
	)


func _maybe_auto_start() -> void:
	if (
		_auto_start_player_count > 0
		and NetworkManager.is_local_lobby_host()
		and NetworkManager.players.size() >= _auto_start_player_count
		and NetworkManager.can_start_game()
	):
		NetworkManager.request_start_game()
