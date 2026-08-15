extends CenterContainer

@export var player_path: NodePath
var player: CharacterBody3D
@onready var label: RichTextLabel = $RichTextLabel

var interact_key_name: String = "E"
var last_text: String = ""

func _ready() -> void:
	if not player_path.is_empty():
		player = get_node(player_path)
		
	var events = InputMap.action_get_events("interact")
	if events.size() > 0:
		var ev = events[0]
		if ev is InputEventKey:
			interact_key_name = OS.get_keycode_string(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode)
			if interact_key_name.is_empty():
				interact_key_name = ev.as_text().get_slice(" ", 0)

func _set_prompt_text(new_text: String) -> void:
	if last_text != new_text:
		last_text = new_text
		label.text = new_text

func _process(_delta: float) -> void:
	if player and player.interact_ray:
		if player.interact_ray.is_colliding():
			var collider = player.interact_ray.get_collider()
			var interact_target = collider
			if collider and not collider.has_method("interact"):
				interact_target = collider.get_parent()
				
			if interact_target and interact_target.has_method("interact"):
				var dist = player.global_position.distance_to(interact_target.global_position)
				var allowed_range = interact_target.interaction_range if "interaction_range" in interact_target else 2.5
				
				if dist <= allowed_range:
					var show_prompt = true
					
					if "state" in interact_target:
						var state = interact_target.state
						if state == 1 or state == 3: # OPENING or CLOSING
							show_prompt = false
						elif state == 0: # CLOSED
							_set_prompt_text("[center]" + interact_key_name + " - Mở cửa[/center]")
						elif state == 2: # OPEN
							_set_prompt_text("[center]" + interact_key_name + " - Đóng cửa[/center]")
					elif "is_open" in interact_target:
						# Fallback for old tests if any
						if interact_target.is_open:
							_set_prompt_text("[center]" + interact_key_name + " - Đóng cửa[/center]")
						else:
							_set_prompt_text("[center]" + interact_key_name + " - Mở cửa[/center]")
					else:
						_set_prompt_text("[center]Interact [" + interact_key_name + "][/center]")
					
					if show_prompt:
						if not visible:
							visible = true
						return
						
	if visible:
		visible = false
