extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://main.tscn") as PackedScene
	var main_scene := packed_scene.instantiate()
	root.add_child(main_scene)
	await process_frame

	var navigation_region := main_scene.get_node_or_null("HouseNavigationRegion") as NavigationRegion3D
	if not navigation_region:
		_fail("No HouseNavigationRegion was generated under main.tscn.")
		return

	var navigation_mesh := navigation_region.navigation_mesh
	if not navigation_mesh or navigation_mesh.get_polygon_count() <= 0:
		_fail("Baked navigation mesh has no polygons.")
		return

	var vertices := navigation_mesh.get_vertices()
	if vertices.is_empty():
		_fail("Baked navigation mesh reported polygons but no vertices.")
		return

	var map_rid := navigation_region.get_navigation_map()
	var ground_probe := Vector3(0.0, 0.1, -1.0)
	var upper_probe := Vector3(0.0, 3.1, 4.6)

	# NavigationServer3D links a freshly-baked region into the map's live
	# query structures on a separate pass that isn't guaranteed to finish
	# within a handful of physics frames (observed to need closer to a real
	# second, not just a few ticks) - poll for readiness instead of guessing
	# a fixed frame count, which was flaky. Wait for iteration_id > 0 first
	# so the map_get_closest_point probe (which logs a benign engine error
	# if queried before the first sync) only ever runs post-sync.
	var sync_deadline_msec := Time.get_ticks_msec() + 5000
	while NavigationServer3D.map_get_iteration_id(map_rid) == 0:
		if Time.get_ticks_msec() > sync_deadline_msec:
			_fail("Navigation map did not finish syncing the baked region within 5 seconds.")
			return
		await physics_frame

	var ground_point := NavigationServer3D.map_get_closest_point(map_rid, ground_probe)
	while ground_point.distance_to(Vector3.ZERO) < 0.01:
		if Time.get_ticks_msec() > sync_deadline_msec:
			_fail("Navigation map did not finish syncing the baked region within 5 seconds.")
			return
		await physics_frame
		ground_point = NavigationServer3D.map_get_closest_point(map_rid, ground_probe)

	var upper_point := NavigationServer3D.map_get_closest_point(map_rid, upper_probe)
	if ground_point.distance_to(ground_probe) > 1.0 or absf(ground_point.y) > 0.5:
		_fail("Ground-floor navigation is not aligned with the physical stair entrance: %s." % ground_point)
		return
	if upper_point.distance_to(upper_probe) > 0.75 or upper_point.y < 2.1:
		_fail("Upper-floor navigation is not aligned with the physical stair landing: %s." % upper_point)
		return

	var path := NavigationServer3D.map_get_path(map_rid, ground_point, upper_point, true)
	while path.is_empty() or path[path.size() - 1].distance_to(upper_point) > 0.5:
		if Time.get_ticks_msec() > sync_deadline_msec:
			_fail(
				"No complete path was found through the stairs from %s to %s (partial points: %d)."
				% [ground_point, upper_point, path.size()]
			)
			return
		await physics_frame
		path = NavigationServer3D.map_get_path(map_rid, ground_point, upper_point, true)

	var last_point: Vector3 = path[path.size() - 1]
	if last_point.y - ground_point.y < 1.8:
		_fail("The stair path did not gain enough height to reach the upper floor.")
		return

	# Door 05 opens from the east second-floor bedroom. Reaching that room from
	# the stair head must stay on the second floor; a disconnected hall/bedroom
	# island can otherwise make an agent take the ground-floor stairs twice.
	var room_five_start := NavigationServer3D.map_get_closest_point(
		map_rid,
		Vector3(1.65, 3.05, 4.24)
	)
	var room_five_point := NavigationServer3D.map_get_closest_point(
		map_rid,
		Vector3(7.4, 3.1, -3.0)
	)
	var room_five_path := NavigationServer3D.map_get_path(
		map_rid,
		room_five_start,
		room_five_point,
		true
	)
	if room_five_path.is_empty() \
		or room_five_path[room_five_path.size() - 1].distance_to(room_five_point) > 0.5:
		_fail("No complete second-floor path was found from the landing to Door 05's room.")
		return
	var room_five_min_y := INF
	for point: Vector3 in room_five_path:
		room_five_min_y = minf(room_five_min_y, point.y)
	if room_five_min_y < 2.5:
		_fail(
			"The route to Door 05's room detours below the second floor (minimum y %.2f)."
			% room_five_min_y
		)
		return

	var basement_point := NavigationServer3D.map_get_closest_point(
		map_rid,
		Vector3(-6.0, -2.9, -1.0)
	)
	var attic_point := NavigationServer3D.map_get_closest_point(
		map_rid,
		Vector3(-4.0, 6.1, 4.8)
	)
	var full_house_path := NavigationServer3D.map_get_path(
		map_rid,
		basement_point,
		attic_point,
		true
	)
	if full_house_path.is_empty() \
		or full_house_path[full_house_path.size() - 1].distance_to(attic_point) > 0.5:
		_fail("No complete basement-to-attic route was found through all three staircases.")
		return
	if attic_point.y - basement_point.y < 8.5:
		_fail("The full-house route did not span all four authored elevations.")
		return

	print(
		"House navigation smoke test passed: %d polygons, %d-point basement-to-attic route."
		% [navigation_mesh.get_polygon_count(), full_house_path.size()]
	)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
