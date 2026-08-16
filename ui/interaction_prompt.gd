extends CenterContainer

@export var player_path: NodePath
var player: CharacterBody3D
@onready var label: RichTextLabel = $RichTextLabel

var interact_key_name: String = "E"
var last_text: String = ""


func _ready() -> void:
	if not player_path.is_empty():
		player = get_node(player_path)

	var events := InputMap.action_get_events("interact")
	if events.size() > 0:
		var event := events[0]
		if event is InputEventKey:
			interact_key_name = OS.get_keycode_string(
				event.physical_keycode if event.physical_keycode != 0 else event.keycode
			)


func _set_prompt_text(new_text: String) -> void:
	if last_text != new_text:
		last_text = new_text
		label.text = new_text


func _process(_delta: float) -> void:
	if player:
		var interact_target: Node = player.get_interaction_target()
		if interact_target and player.can_interact_with(interact_target):
			if "state" in interact_target:
				var state: int = interact_target.state
				if state == 1 or state == 3: # OPENING or CLOSING
					visible = false
					return
				elif state == 0: # CLOSED
					_set_prompt_text("[center][b]" + interact_key_name + "[/b]  MỞ CỬA[/center]")
				else: # OPEN
					_set_prompt_text("[center][b]" + interact_key_name + "[/b]  ĐÓNG CỬA[/center]")
			else:
				_set_prompt_text("[center][b]" + interact_key_name + "[/b]  TƯƠNG TÁC[/center]")

			visible = true
			return

	visible = false
