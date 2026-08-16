extends SceneTree


const EXPECTED_ROOMS := {
	"Basement": ["BoilerAndStorage"],
	"GroundFloor": ["Kitchen", "LivingRoom", "DiningRoom", "Garage", "MainHall", "Storage"],
	"SecondFloor": ["BedroomWest", "BedroomEast", "HallAndStairs", "Bathroom"],
	"Attic": ["AtticStorage"],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main_scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await process_frame

	var house := main_scene.get_node_or_null("House2") as Node3D
	if not house:
		_fail("main.tscn does not contain the House2 scene.")
		return
	var generated := house.get_node_or_null("Generated") as Node3D
	if not generated:
		_fail("House2 did not generate its modular architecture.")
		return

	for level_name: String in EXPECTED_ROOMS:
		var level := generated.get_node_or_null(level_name) as Node3D
		if not level:
			_fail("House2 is missing level %s." % level_name)
			return
		for room_name: String in EXPECTED_ROOMS[level_name]:
			var room := level.get_node_or_null(room_name) as Marker3D
			if not room or not room.has_meta("room_size"):
				_fail("%s is missing its authored room marker %s." % [level_name, room_name])
				return

	# The basement staircase is in Garage. A former doorway at x=-6,z=0
	# continued straight into Kitchen/entrance #2 and produced an implausible
	# stair-to-room tunnel. Only Living/Hall and Dining/Storage belong here.
	var middle_frames := generated.get_node("GroundFloor/Architecture").find_children(
		"MiddlePartitionDoorFrame*", "Node3D", true, false
	)
	if middle_frames.size() != 2:
		_fail("Ground middle partition should contain exactly 2 door frames, found %d." % middle_frames.size())
		return
	for frame: Node3D in middle_frames:
		if absf(frame.position.x + 6.0) < 0.1:
			_fail("Kitchen/Garage doorway still opens directly into the basement stairwell.")
			return
	var stairwell_frame := generated.get_node("GroundFloor/Architecture").find_child(
		"GarageStairwellDoorFrame*", true, false
	) as Node3D
	if not stairwell_frame or stairwell_frame.position.distance_to(Vector3(-8, 0, 4.45)) > 0.05:
		_fail("Garage basement stairwell is missing its dedicated upper entry frame.")
		return

	var modular_assets := get_nodes_in_group("modular_house_asset")
	if modular_assets.size() < 250:
		_fail("House2 used only %d modular kit instances; architecture appears incomplete." % modular_assets.size())
		return
	for module: Node in modular_assets:
		if not str(module.get_meta("source_asset", "")).begins_with("res://assets/map/"):
			_fail("A modular architecture node is not sourced from assets/map: %s." % module.name)
			return

	var stair_count := 0
	var basement_stair: Node3D
	for node: Node in house.find_children("Stair*", "Node3D", true, false):
		if node.has_meta("source_asset"):
			stair_count += 1
			if node.name.begins_with("StairBasementToGround"):
				basement_stair = node as Node3D
	if stair_count != 3:
		_fail("Expected 3 internal staircases, found %d." % stair_count)
		return
	if not basement_stair or absf(basement_stair.position.x + 8.0) > 0.01:
		_fail("Basement stair must run along the west garage wall, not through the room centre.")
		return

	# Bathroom fixtures belong against walls, not in the circulation path from
	# the hall doorway. In particular, keep the toilet on the south wall with
	# the bowl facing into the room.
	var toilet := generated.find_child("Toilet_*", true, false) as Node3D
	var expected_toilet_position := Vector3(5.1, 3.0, 0.65)
	if not toilet or toilet.global_position.distance_to(expected_toilet_position) > 0.05:
		_fail("Bathroom toilet is not tucked against the south wall.")
		return
	if absf(wrapf(toilet.rotation.y - PI, -PI, PI)) > 0.05:
		_fail("Bathroom toilet does not face into the room.")
		return

	var smooth_ramps := get_nodes_in_group("smooth_stair_ramps")
	if smooth_ramps.size() != 4:
		_fail("Expected 4 smooth stair ramps including the cellar exit, found %d." % smooth_ramps.size())
		return
	for ramp: StaticBody3D in smooth_ramps:
		var collision := ramp.get_node_or_null("SmoothRampCollision") as CollisionShape3D
		if not collision or not collision.shape is BoxShape3D:
			_fail("Stair ramp %s is missing its smooth box collision." % ramp.name)
			return
	if get_nodes_in_group("smooth_stair_navigation_links").size() != 4:
		_fail("Every smooth stair ramp must have a matching navigation link.")
		return

	var entrance_ids: Array[int] = []
	var entrance_elevations := {1: 0.0, 2: 0.0, 3: 0.0, 4: 3.0, 5: 3.0, 6: -3.0, 7: 6.0}
	for node: Node in get_nodes_in_group("defense_doors"):
		var entrance_id := int(node.get("entrance_id"))
		entrance_ids.append(entrance_id)
		if not entrance_elevations.has(entrance_id):
			_fail("Unexpected entrance id %d." % entrance_id)
			return
		if absf((node as Node3D).global_position.y - entrance_elevations[entrance_id]) > 0.01:
			_fail("Entrance %02d is on the wrong floor." % entrance_id)
			return
	entrance_ids.sort()
	if entrance_ids != [1, 2, 3, 4, 5, 6, 7]:
		_fail("House2 entrances are incomplete or duplicated: %s." % entrance_ids)
		return

	print(
		"House2 layout smoke test passed: 4 levels, 12 rooms, %d modular assets, 4 smooth ramps/links and 7 entrances."
		% modular_assets.size()
	)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
