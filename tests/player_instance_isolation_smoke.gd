extends SceneTree

## Pins the two per-instance guarantees multiplayer depends on: changing one
## player's crouch capsule must not mutate another player's collider, and a
## remote replica entering the viewport must not take over the local camera.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manager := root.get_node_or_null(^"/root/NetworkManager")
	if manager == null:
		return _fail("NetworkManager autoload is missing.")
	manager.set("session_active", true)

	var player_scene := load("res://player/player.tscn") as PackedScene
	if player_scene == null:
		return _fail("Player scene could not be loaded.")

	var world := Node3D.new()
	world.name = "PlayerIsolationWorld"
	root.add_child(world)
	current_scene = world

	var local_player := player_scene.instantiate() as CharacterBody3D
	local_player.name = "Player"
	local_player.owner_peer_id = 1
	world.add_child(local_player)
	local_player.set_physics_process(false)

	var remote_player := player_scene.instantiate() as CharacterBody3D
	remote_player.name = "Player_2"
	remote_player.owner_peer_id = 2
	world.add_child(remote_player)
	remote_player.set_physics_process(false)

	var local_camera := local_player.get_node("CameraPivot/Camera3D") as Camera3D
	var remote_camera := remote_player.get_node("CameraPivot/Camera3D") as Camera3D
	if not local_camera.current or remote_camera.current:
		return _fail("A remote player replica stole the local viewport camera.")

	var local_collision := local_player.get_node("CollisionShape3D") as CollisionShape3D
	var remote_collision := remote_player.get_node("CollisionShape3D") as CollisionShape3D
	var local_shape := local_collision.shape as CapsuleShape3D
	var remote_shape := remote_collision.shape as CapsuleShape3D
	if local_shape == remote_shape:
		return _fail("Two player instances still share one CapsuleShape3D resource.")

	var local_height := local_shape.height
	remote_player.call("_crouch")
	if not is_equal_approx(local_shape.height, local_height):
		return _fail("Crouching the remote player changed the local player's capsule.")
	if not is_equal_approx(remote_shape.height, remote_player.crouch_height):
		return _fail("The remote player's own capsule did not enter crouch height.")

	# A new authoritative correction replaces an old pending one, and applying it
	# moves every unacknowledged prediction into the same coordinate space. This
	# prevents the same error being rediscovered and accumulated every snapshot.
	local_player.global_position = Vector3(10.0, 0.0, 0.0)
	local_player.set("_prediction_history", {
		10: Vector3(8.0, 0.0, 0.0),
		11: Vector3(10.0, 0.0, 0.0),
	})
	local_player.set("_pending_reconciliation", Vector3(50.0, 0.0, 0.0))
	local_player.call(
		"_reconcile_predicted_position",
		Vector3(8.25, 0.0, 0.0),
		Vector3.ZERO,
		10
	)
	var pending: Vector3 = local_player.get("_pending_reconciliation")
	if not pending.is_equal_approx(Vector3(0.25, 0.0, 0.0)):
		return _fail("A fresh prediction correction accumulated the stale pending error.")
	local_player.call("_apply_pending_reconciliation", 0.1)
	var history: Dictionary = local_player.get("_prediction_history")
	if not local_player.global_position.is_equal_approx(Vector3(10.25, 0.0, 0.0)):
		return _fail("Smooth reconciliation did not move the local player correctly.")
	if not (history[11] as Vector3).is_equal_approx(Vector3(10.25, 0.0, 0.0)):
		return _fail("Smooth reconciliation left future prediction history stale.")
	local_player.call(
		"_reconcile_predicted_position",
		Vector3(10.25, 0.0, 0.0),
		Vector3.ZERO,
		11
	)
	pending = local_player.get("_pending_reconciliation")
	if not pending.is_zero_approx():
		return _fail("The next matching snapshot rediscovered an already-applied correction.")

	local_player.global_position = Vector3(20.0, 0.0, 0.0)
	local_player.set("_prediction_history", {
		12: Vector3(20.0, 0.0, 0.0),
		13: Vector3(21.0, 0.0, 0.0),
	})
	local_player.call(
		"_reconcile_predicted_position",
		Vector3.ZERO,
		Vector3(1.0, 0.0, 0.0),
		12
	)
	history = local_player.get("_prediction_history")
	if not local_player.global_position.is_equal_approx(Vector3.ZERO):
		return _fail("A large authoritative correction did not hard-snap the player.")
	if not (history[13] as Vector3).is_equal_approx(Vector3(1.0, 0.0, 0.0)):
		return _fail("Hard reconciliation left future prediction history stale.")

	manager.set("session_active", false)
	print(
		"Player instance isolation smoke test passed: crouch capsules are unique "
		+ "and remote replicas cannot steal the local camera; reconciliation stays bounded."
	)
	quit()


func _fail(message: String) -> void:
	var manager := root.get_node_or_null(^"/root/NetworkManager")
	if manager:
		manager.set("session_active", false)
	push_error("Player instance isolation smoke test failed: " + message)
	print("Player instance isolation smoke test FAILED: " + message)
	quit(1)
