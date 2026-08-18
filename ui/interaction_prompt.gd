extends CenterContainer

@export var player_path: NodePath
var player: CharacterBody3D
@onready var label: RichTextLabel = $RichTextLabel

var interact_key_name: String = "E"
var last_text: String = ""
var current_interactable: Interactable3D = null


func _ready() -> void:
	if not player_path.is_empty():
		player = get_node(player_path)
		var interact_comp = player.get_node_or_null("InteractionController")
		if interact_comp and interact_comp.has_signal("interact_target_changed"):
			interact_comp.interact_target_changed.connect(_on_interact_target_changed)

	var events := InputMap.action_get_events("interact")
	if events.size() > 0:
		var event := events[0]
		if event is InputEventKey:
			interact_key_name = OS.get_keycode_string(
				event.physical_keycode if event.physical_keycode != 0 else event.keycode
			)
			if interact_key_name.is_empty():
				interact_key_name = event.as_text().get_slice(" ", 0)

	visible = false


func _set_prompt_text(new_text: String) -> void:
	var final_text = "[center]" + interact_key_name + " - " + new_text + "[/center]"
	if last_text != final_text:
		last_text = final_text
		label.text = final_text


func _on_interact_target_changed(interactable: Interactable3D) -> void:
	if current_interactable:
		if current_interactable.prompt_updated.is_connected(_on_prompt_updated):
			current_interactable.prompt_updated.disconnect(_on_prompt_updated)

	current_interactable = interactable

	if current_interactable:
		current_interactable.prompt_updated.connect(_on_prompt_updated)
		_update_prompt_display()
	else:
		visible = false


func _on_prompt_updated(_new_prompt: String) -> void:
	_update_prompt_display()


func _update_prompt_display() -> void:
	if not current_interactable: return

	var text = current_interactable.get_prompt()
	if text.is_empty():
		visible = false
	else:
		visible = true
		_set_prompt_text(text)
