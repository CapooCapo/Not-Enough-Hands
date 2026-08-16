extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main_scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	var player := main_scene.get_node("Player") as CharacterBody3D
	(main_scene.get_node("StatueGhost") as CharacterBody3D).set("active", false)
	player.set_physics_process(false)
	# Start directly before the lower end and walk the authored run centreline.
	# Navigation connectivity is covered separately; this specifically proves
	# the capsule clears both enclosure walls and the upper door frame.
	player.global_position = Vector3(-8.0, -2.02, 0.35)
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var climb_deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() <= climb_deadline:
		player.velocity.x = 0
		player.velocity.z = float(player.get("walk_speed"))
		if player.is_on_floor():
			player.velocity.y = -0.15
		else:
			player.velocity.y -= gravity / 60.0
		player.call("_try_step_up", Vector3(player.velocity.x, 0, player.velocity.z) / 60.0)
		player.move_and_slide()
		if player.global_position.y >= 0.8:
			print("House basement stair smoke test passed: player reached Garage through the enclosed stairwell.")
			quit()
			return
		await physics_frame

	_fail("Player could not pass the relocated basement stairwell and upper entry frame (final=%s)." % player.global_position)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
