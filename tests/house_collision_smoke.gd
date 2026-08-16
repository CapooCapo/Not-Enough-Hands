extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://main.tscn") as PackedScene
	var main_scene := packed_scene.instantiate()
	root.add_child(main_scene)
	await process_frame

	var house := main_scene.get_node("House2") as Node3D
	var concave_shape_count := 0
	for node: Node in house.find_children("*", "CollisionShape3D", true, false):
		var collision_shape := node as CollisionShape3D
		var concave_shape := collision_shape.shape as ConcavePolygonShape3D
		if concave_shape:
			concave_shape_count += 1
			if not concave_shape.backface_collision:
				push_error("A house collision shape still ignores back-face hits.")
				quit(1)
				return

	if concave_shape_count == 0:
		push_error("No generated house collision shapes were found.")
		quit(1)
		return

	print("House collision smoke test passed: %d two-sided shapes." % concave_shape_count)
	quit()
