extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://tests/player_test.tscn") as PackedScene
	var test_scene := packed_scene.instantiate()
	root.add_child(test_scene)

	var player := test_scene.get_node("Player") as CharacterBody3D
	var door := test_scene.get_node("TestDoor") as Node3D
	player.global_position = Vector3(0.7, 1.0, 2.0)
	player.global_rotation = Vector3.ZERO

	await physics_frame
	await physics_frame

	var target: Node = player.call("get_interaction_target")
	if target != door:
		push_error("Interaction ray did not resolve the Door node.")
		quit(1)
		return

	player.call("_try_interact")
	if int(door.get("state")) != 1: # OPENING
		push_error("Door did not enter OPENING state after interaction.")
		quit(1)
		return

	print("Door interaction smoke test passed.")
	quit()
