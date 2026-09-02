extends SceneTree

## Peeking round a corner, which is the counter to the Huntsman's line of sight
## from any angle. Three things have to hold: the head actually leaves the
## body's centreline, it comes back on its own when the key is released, and it
## stops at a wall instead of pushing the camera through the cover it is
## peeking around. Both writers of the camera pivot run in every loop below, so
## the lean has to survive the head bob and roll the same tick applies.

const PLAYER_SCENE := preload("res://player/player.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	world.add_child(player)
	await physics_frame
	var pivot := player.get_node_or_null(^"CameraPivot") as Node3D
	if pivot == null:
		_fail("The player has no CameraPivot to lean.")
		return
	var base_x: float = player._camera_pivot_base_x

	if not is_equal_approx(pivot.position.x, base_x) or not is_equal_approx(pivot.rotation.z, 0.0):
		_fail("An idle player did not start upright.")
		return

	# Held long enough to reach the stop, in open air.
	Input.action_press(&"lean_right")
	for _step: int in 40:
		player._update_lean(0.05)
		player._update_camera_motion(0.05)
	if player._lean < 0.99:
		_fail("Holding lean_right did not reach a full lean.")
		return
	if pivot.position.x <= base_x + player.lean_side_offset * 0.5:
		_fail("A full lean did not move the head off the body's centreline.")
		return
	if pivot.rotation.z >= 0.0:
		_fail("Leaning right did not roll the camera right.")
		return

	# The opposite key is the mirror image, not a second lean in the same
	# direction: both held at once is upright, which is what makes them safe to
	# mash.
	Input.action_press(&"lean_left")
	for _step: int in 40:
		player._update_lean(0.05)
		player._update_camera_motion(0.05)
	if absf(player._lean) > 0.01 or not is_equal_approx(pivot.position.x, base_x):
		_fail("Both lean keys at once did not cancel out.")
		return

	Input.action_release(&"lean_right")
	for _step: int in 40:
		player._update_lean(0.05)
		player._update_camera_motion(0.05)
	if player._lean > -0.99 or pivot.position.x >= base_x - player.lean_side_offset * 0.5:
		_fail("Holding lean_left did not lean the head to the left.")
		return

	# Released: back upright on its own, no snap and no drift.
	Input.action_release(&"lean_left")
	for _step: int in 40:
		player._update_lean(0.05)
		player._update_camera_motion(0.05)
	if not is_equal_approx(player._lean, 0.0) or not is_equal_approx(pivot.position.x, base_x):
		_fail("Releasing both lean keys did not return the head to centre.")
		return

	# A wall right beside the head is the case the clamp exists for: leaning
	# into it must stop short of it rather than putting the camera inside it.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 3.0, 3.0)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = pivot.global_position + player.global_basis.x * 0.2
	await physics_frame

	Input.action_press(&"lean_right")
	for _step: int in 40:
		player._update_lean(0.05)
		player._update_camera_motion(0.05)
	Input.action_release(&"lean_right")
	var blocked_offset: float = pivot.position.x - base_x
	if blocked_offset >= player.lean_side_offset * 0.5:
		_fail("A lean into a wall was not clamped short of it: %.3f m." % blocked_offset)
		return
	if blocked_offset < 0.0:
		_fail("A blocked lean pushed the head the wrong way.")
		return

	print("Player lean smoke test passed: full lean, mirrored keys, self-centring release, and a wall-clamped peek.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
