extends SceneTree

func _init() -> void:
	var root = get_root()
	var test_scene = load("res://tests/player_test.tscn").instantiate()
	root.add_child(test_scene)
	
	await create_timer(0.5).timeout
	
	var player = test_scene.get_node("Player")
	var toilet = test_scene.get_node("TestToilet")
	var medkit = test_scene.get_node("TestMedkit1")
	var interact_ray = player.get_node("CameraPivot/Camera3D/InteractRay")
	var interact_comp = player.get_node("InteractionController")
	
	var aim_at = func(target_pos: Vector3):
		player.global_position = target_pos + Vector3(0, 0, 1.5)
		var cam_pivot = player.get_node("CameraPivot")
		var cam = player.get_node("CameraPivot/Camera3D")
		
		player.global_position.y = target_pos.y
		
		var dir = (target_pos - player.global_position).normalized()
		player.rotation.y = atan2(-dir.x, -dir.z)
		
		var local_target = player.to_local(target_pos)
		local_target.y -= cam_pivot.position.y
		cam_pivot.rotation.x = atan2(local_target.y, -local_target.z)
		
		for i in range(5):
			await create_timer(0.05).timeout
			interact_ray.force_raycast_update()

	print("\n--- DEBUG MEDKIT ---")
	await aim_at.call(medkit.global_position)
	print("Ray colliding: ", interact_ray.is_colliding())
	if interact_ray.is_colliding():
		var col = interact_ray.get_collider()
		print("Collider: ", col.name if col else "null")
		print("Collider layer: ", col.collision_layer if "collision_layer" in col else "unknown")
		print("Candidate: ", interact_comp._resolve_interactable(col))

	print("\n--- DEBUG TOILET ---")
	await aim_at.call(toilet.global_position + Vector3(0, 0.25, 0))
	print("Ray colliding: ", interact_ray.is_colliding())
	if interact_ray.is_colliding():
		var col = interact_ray.get_collider()
		print("Collider: ", col.name if col else "null")
		print("Collider layer: ", col.collision_layer if "collision_layer" in col else "unknown")
		print("Candidate: ", interact_comp._resolve_interactable(col))

	quit()
