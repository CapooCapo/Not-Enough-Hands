extends SceneTree

func _init() -> void:
	var root = get_root()
	var test_scene = load("res://tests/player_test.tscn").instantiate()
	root.add_child(test_scene)
	
	await create_timer(0.5).timeout
	
	var player = test_scene.get_node("Player")
	var door = test_scene.get_node("TestDoor")
	var switch = test_scene.get_node("TestSwitch")
	var medkit = test_scene.get_node("TestMedkit1")
	var toilet = test_scene.get_node("TestToilet")
	
	var interact_ray = player.get_node("CameraPivot/Camera3D/InteractRay")
	var interact_comp = player.get_node("InteractionController")
	var carry_slots = player.get_node("CarrySlotsComponent")
	
	print("\n--- RUNNING INTERACTION TESTS ---\n")
	
	var interact_with = func(target_node: Node3D, offset: Vector3 = Vector3.ZERO):
		var target_pos = target_node.global_position + offset
		# Move the player close
		player.global_position = target_pos + Vector3(0, 0, 1.0)
		
		# Move raycast
		interact_ray.global_position = player.global_position
		interact_ray.global_rotation = Vector3.ZERO
		interact_ray.target_position = Vector3(0, 0, -2.0)
		
		interact_ray.force_raycast_update()
		interact_comp._update_interact_target()
		
		if interact_comp.current_interactable:
			print("PROMPT: ", interact_comp.current_interactable.get_prompt())
			interact_comp.handle_interact_input()
			return true
		return false
	
	if await interact_with.call(door, Vector3(1.15, 1.15, 0)):
		print("DOOR STATE AFTER INTERACT: ", door.state)
	else:
		print("FAILED TO DETECT DOOR")
		
	if await interact_with.call(switch):
		print("SWITCH HAS TIMER: ", switch.timer.time_left > 0)
	else:
		print("FAILED TO DETECT SWITCH")
		
	await create_timer(0.1).timeout
	if await interact_with.call(medkit):
		await create_timer(0.1).timeout
		print("MEDKIT INVENTORY SLOT 1: ", carry_slots.get_item(0) != null)
	else:
		print("FAILED TO DETECT MEDKIT")
		
	if await interact_with.call(toilet, Vector3(0, 0.25, 0)):
		await create_timer(0.1).timeout
		print("TOILET MINIGAME ACTIVE: ", toilet.is_occupied)
		print("PLAYER PHYSICS PROCESSING: ", player.is_physics_processing())
	else:
		print("FAILED TO DETECT TOILET")
	
	print("\n--- TESTS COMPLETE ---")
	quit()
