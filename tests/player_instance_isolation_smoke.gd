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

	manager.set("session_active", false)
	print(
		"Player instance isolation smoke test passed: crouch capsules are unique "
		+ "and remote replicas cannot steal the local camera."
	)
	quit()


func _fail(message: String) -> void:
	var manager := root.get_node_or_null(^"/root/NetworkManager")
	if manager:
		manager.set("session_active", false)
	push_error("Player instance isolation smoke test failed: " + message)
	print("Player instance isolation smoke test FAILED: " + message)
	quit(1)
