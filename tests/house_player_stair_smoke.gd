extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://main.tscn") as PackedScene
	var main_scene := packed_scene.instantiate()
	root.add_child(main_scene)

	var player := main_scene.get_node("Player") as CharacterBody3D
	var statue := main_scene.get_node("StatueGhost") as CharacterBody3D
	var region := main_scene.get_node("HouseNavigationRegion") as NavigationRegion3D
	var map_rid := region.get_navigation_map()
	statue.set("active", false)
	player.set_physics_process(false)
	player.global_position = Vector3(14.8, 0.98, 29.1)

	var sync_deadline_msec := Time.get_ticks_msec() + 5000
	while NavigationServer3D.map_get_iteration_id(map_rid) == 0:
		if Time.get_ticks_msec() > sync_deadline_msec:
			_fail("Navigation map did not sync before the player stair test.")
			return
		await physics_frame

	var stair_start := NavigationServer3D.map_get_closest_point(map_rid, player.global_position)
	var stair_end := NavigationServer3D.map_get_closest_point(map_rid, Vector3(13.15, 2.44, 22.15))
	var path := NavigationServer3D.map_get_path(map_rid, stair_start, stair_end, true)
	while path.size() < 2 or path[path.size() - 1].distance_to(stair_end) > 0.5:
		if Time.get_ticks_msec() > sync_deadline_msec:
			_fail("No complete ground-to-upper route was available for the player stair test.")
			return
		await physics_frame
		stair_start = NavigationServer3D.map_get_closest_point(map_rid, player.global_position)
		stair_end = NavigationServer3D.map_get_closest_point(map_rid, Vector3(13.15, 2.44, 22.15))
		path = NavigationServer3D.map_get_path(map_rid, stair_start, stair_end, true)

	var path_index := 0
	var start_y := player.global_position.y
	var highest_y := start_y
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var deadline_msec := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() <= deadline_msec:
		while path_index < path.size() - 1:
			var flat_to_waypoint := path[path_index] - player.global_position
			flat_to_waypoint.y = 0.0
			if flat_to_waypoint.length() > 0.3:
				break
			path_index += 1

		var direction := path[path_index] - player.global_position
		direction.y = 0.0
		direction = direction.normalized()
		player.velocity.x = direction.x * float(player.get("walk_speed"))
		player.velocity.z = direction.z * float(player.get("walk_speed"))
		if player.is_on_floor():
			player.velocity.y = -0.15
		else:
			player.velocity.y -= gravity / 60.0

		if player.is_on_floor() and player.velocity.y <= 0.0:
			player.call(
				"_try_step_up",
				Vector3(player.velocity.x, 0.0, player.velocity.z) / 60.0
			)
		player.move_and_slide()
		highest_y = maxf(highest_y, player.global_position.y)

		if player.global_position.y >= 3.0:
			print(
				"House player stair smoke test passed: player climbed %.2f m without sticking."
				% (player.global_position.y - start_y)
			)
			quit()
			return
		await physics_frame

	_fail(
		(
			"Player never reached the upper floor while following the valid stair route "
			+ "(highest y=%.2f, final=%s)."
		)
		% [highest_y, player.global_position]
	)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
