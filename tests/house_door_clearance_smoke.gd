extends SceneTree


const DOOR_CLEARANCES: Array[Dictionary] = [
	# Ground-floor north/south room connections.
	{"name": "Living / Main Hall", "center": Vector3(0, 0, 0), "half": Vector2(0.72, 1.05)},
	{"name": "Dining / Storage", "center": Vector3(6, 0, 0), "half": Vector2(0.72, 1.05)},
	# Ground-floor east/west room connections.
	{"name": "Kitchen / Living", "center": Vector3(-3, 0, -3), "half": Vector2(1.05, 0.72)},
	{"name": "Garage / Main Hall", "center": Vector3(-3, 0, 3), "half": Vector2(1.05, 0.72)},
	{"name": "Living / Dining", "center": Vector3(3, 0, -3), "half": Vector2(1.05, 0.72)},
	{"name": "Main Hall / Storage", "center": Vector3(3, 0, 3), "half": Vector2(1.05, 0.72)},
	# Second-floor bedroom and bathroom connections.
	{"name": "West Bedroom / Hall", "center": Vector3(-5, 3, 0), "half": Vector2(0.72, 1.05)},
	{"name": "East Bedroom / Hall", "center": Vector3(4, 3, 0), "half": Vector2(0.72, 1.05)},
	{"name": "Hall / Bathroom", "center": Vector3(3, 3, 3), "half": Vector2(1.05, 0.72)},
	# All seven defended exterior entrances, including clearance on both sides
	# of the wall rather than only inside the room.
	{"name": "Entrance #1 Front", "center": Vector3(0, 0, 6), "half": Vector2(0.85, 1.25)},
	{"name": "Entrance #2 Kitchen Side", "center": Vector3(-9, 0, -3), "half": Vector2(1.35, 1.15)},
	{"name": "Entrance #3 Dining Patio", "center": Vector3(6, 0, -6), "half": Vector2(0.9, 1.25)},
	{"name": "Entrance #4 Bedroom Balcony", "center": Vector3(-6, 3, -6), "half": Vector2(0.9, 1.25)},
	{"name": "Entrance #5 East Balcony", "center": Vector3(9, 3, -3), "half": Vector2(1.25, 0.9)},
	{"name": "Entrance #6 Cellar Exit", "center": Vector3(9, -3, 0), "half": Vector2(1.25, 0.9)},
	{"name": "Entrance #7 Roof Entry", "center": Vector3(0, 6, -6), "half": Vector2(0.9, 1.25)},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main_scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await process_frame

	var props: Array[Node3D] = []
	for props_container: Node in main_scene.get_node("House2/Generated").find_children(
		"Props", "Node3D", true, false
	):
		for child: Node in props_container.get_children():
			if child is Node3D:
				props.append(child as Node3D)

	var blocked: Array[String] = []
	for clearance: Dictionary in DOOR_CLEARANCES:
		var center: Vector3 = clearance["center"]
		var half: Vector2 = clearance["half"]
		var clearance_bounds := AABB(
			Vector3(center.x - half.x, center.y - 0.05, center.z - half.y),
			Vector3(half.x * 2.0, 2.25, half.y * 2.0)
		)
		for prop: Node3D in props:
			var prop_bounds := _global_visual_bounds(prop)
			if prop_bounds.size != Vector3.ZERO and prop_bounds.intersects(clearance_bounds):
				blocked.append("%s blocked by %s" % [clearance["name"], prop.name])

	if not blocked.is_empty():
		_fail("Furniture overlaps authored doorway clearance: %s" % blocked)
		return

	print("House doorway clearance smoke test passed: %d interior/exterior doors remain furniture-free." % DOOR_CLEARANCES.size())
	quit()


func _global_visual_bounds(root_node: Node3D) -> AABB:
	var bounds := AABB()
	var has_point := false
	var mesh_nodes: Array[Node] = root_node.find_children("*", "MeshInstance3D", true, false)
	if root_node is MeshInstance3D:
		mesh_nodes.push_back(root_node)
	for node: Node in mesh_nodes:
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance.mesh:
			continue
		var local_bounds := mesh_instance.mesh.get_aabb()
		for x: float in [local_bounds.position.x, local_bounds.end.x]:
			for y: float in [local_bounds.position.y, local_bounds.end.y]:
				for z: float in [local_bounds.position.z, local_bounds.end.z]:
					var point := mesh_instance.global_transform * Vector3(x, y, z)
					if not has_point:
						bounds = AABB(point, Vector3.ZERO)
						has_point = true
					else:
						bounds = bounds.expand(point)
	return bounds


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
