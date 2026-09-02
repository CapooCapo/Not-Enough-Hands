extends SceneTree

const GHOST_SCENE := preload("res://ghosts/darkness_ghost.tscn")
const GHOST_POSITION := Vector3(0.0, 1.0, -5.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ghost := GHOST_SCENE.instantiate() as DarknessGhost
	world.add_child(ghost)
	ghost.global_position = GHOST_POSITION
	ghost.auto_manifest = false
	ghost._set_manifested(true)
	ghost.encounter_phase = DarknessGhost.EncounterPhase.CHASING
	ghost.velocity = Vector3(2.6, 0.0, 0.0)
	ghost._update_footsteps(0.1)
	var footstep_audio := ghost.get_node_or_null("FootstepAudio") as AudioStreamPlayer3D
	if not footstep_audio or not footstep_audio.playing:
		_fail("A moving Darkness Ghost did not play a spatial footstep.")
		return
	ghost.velocity = Vector3.ZERO
	ghost._update_footsteps(0.1)
	if footstep_audio.playing:
		_fail("Darkness Ghost footsteps continued after it stopped moving.")
		return

	var flashlights: Array[SpotLight3D] = []
	for index: int in 3:
		flashlights.append(_add_player_with_flashlight(world, index))
	await physics_frame

	for count: int in 4:
		for index: int in flashlights.size():
			flashlights[index].visible = index < count
		await process_frame
		var expected_speed := maxf(
			ghost.minimum_illuminated_speed,
			ghost.darkness_speed - count * ghost.flashlight_speed_penalty
		)
		if not is_equal_approx(ghost._chase_speed_at(GHOST_POSITION), expected_speed):
			_fail("Flashlight slowdown did not stack once per illuminating player.")
			return

	# Beams kill now instead of driving it off, on an authored ladder the beam
	# count indexes. Pin the table, then hold one rung of it live.
	for entry: Array in [[2, 8.0], [3, 5.0], [4, 3.0]]:
		if not is_equal_approx(ghost._flashlight_death_seconds(int(entry[0])), float(entry[1])):
			_fail("The flashlight death ladder does not hold %d beams for %.1fs." % entry)
			return
	if not is_inf(ghost._flashlight_death_seconds(ghost.flashlight_death_player_count - 1)):
		_fail("A beam count below the ladder reported a finite time to kill.")
		return

	# The beams imply a sighting, but nothing in this fixture owns a real
	# Camera3D to make one, so state it for flashlight combat.
	ghost._has_been_seen = true
	ghost.auto_manifest = true
	ghost._update_light_exposure(4.9)
	if not ghost.is_manifested() or ghost._flashlight_player_count != 3:
		_fail("Three flashlights killed the ghost early or were not counted distinctly.")
		return
	ghost._update_light_exposure(0.2)
	if ghost.is_dead() or ghost.is_manifested() or not ghost.auto_manifest:
		_fail("Three continuous flashlights did not end only the current hunt at five seconds.")
		return
	if not is_equal_approx(ghost._next_manifest_in, ghost.manifest_interval):
		_fail("Flashlight defeat did not schedule the normal manifestation cooldown.")
		return

	# Back on its feet, so the rest of the fixture still has a ghost to test.
	ghost._is_dead = false
	ghost.auto_manifest = true
	ghost._reset_light_exposure()
	ghost._set_manifested(true)
	ghost.encounter_phase = DarknessGhost.EncounterPhase.CHASING

	# Dropping under flashlight_death_player_count discards the hold rather than
	# pausing it: 4.5s + 4.5s across a break is not a kill, five unbroken are.
	ghost._update_light_exposure(4.5)
	flashlights[0].visible = false
	flashlights[1].visible = false
	await process_frame
	ghost._update_light_exposure(0.1)
	flashlights[0].visible = true
	flashlights[1].visible = true
	await process_frame
	ghost._update_light_exposure(4.5)
	if ghost.is_dead():
		_fail("The flashlight death timer did not reset when the beams broke off.")
		return

	# One torch is a slowdown and never a kill, however long it is held.
	flashlights[1].visible = false
	flashlights[2].visible = false
	await process_frame
	ghost._reset_light_exposure()
	ghost._update_light_exposure(ghost.flashlight_death_ladder[0] * 3.0)
	if ghost.is_dead():
		_fail("A lone flashlight killed the ghost on its own.")
		return

	for flashlight: SpotLight3D in flashlights:
		flashlight.visible = false
	await process_frame
	# Unmet again, so the sighting latch below is proved rather than assumed.
	ghost._has_been_seen = false

	# Both halves of the grace hang off one predicate, and the fake players above
	# carry no real Camera3D, so lend it one for a moment: facing the ghost is a
	# sighting, facing away from it is not.
	var watcher := CharacterBody3D.new()
	watcher.add_to_group(&"players")
	world.add_child(watcher)
	watcher.global_position = GHOST_POSITION + Vector3(0.0, 0.0, 6.0)
	var watcher_pivot := Node3D.new()
	watcher_pivot.name = "CameraPivot"
	watcher.add_child(watcher_pivot)
	var watcher_camera := Camera3D.new()
	watcher_camera.name = "Camera3D"
	watcher_pivot.add_child(watcher_camera)
	await process_frame
	watcher_camera.look_at(GHOST_POSITION + Vector3.UP * ghost.sighting_point_height, Vector3.UP)
	if not ghost._is_seen_by_any_player():
		_fail("A player looking straight at an unobstructed Darkness Ghost did not see it.")
		return
	watcher_camera.rotate_y(PI)
	if ghost._is_seen_by_any_player():
		_fail("A player facing away from the Darkness Ghost still counted as seeing it.")
		return
	# _process latched that sighting by itself over the frame the camera spent
	# pointed at the ghost, which is the wiring the grace actually hangs on.
	if not ghost.has_been_seen():
		_fail("A frame with a camera on the ghost did not latch the sighting.")
		return
	watcher.queue_free()
	await process_frame
	await process_frame
	# Hand the fixture back an unmet ghost: nothing else in this test owns a real
	# Camera3D, so from here it holds both halves of the first-sighting grace.
	ghost._has_been_seen = false

	var room_light := OmniLight3D.new()
	room_light.omni_range = 8.0
	room_light.light_energy = 1.0
	room_light.add_to_group(&"local_light_sources")
	world.add_child(room_light)
	room_light.global_position = GHOST_POSITION + Vector3.UP
	await process_frame

	# Before the first sighting of this encounter, world light must not end the
	# hunt while the ghost crosses a powered room on the way to its target.
	if not is_equal_approx(ghost.light_death_seconds, 0.5):
		_fail("Environmental light death must take exactly 0.5 seconds.")
		return
	ghost._update_light_exposure(ghost.light_death_seconds * 3.0)
	if ghost.is_dead():
		_fail("World light permanently killed an unseen Darkness Ghost.")
		return
	if not ghost.is_manifested():
		_fail("An unseen Darkness Ghost retreated while crossing environmental light.")
		return
	if not is_equal_approx(ghost._environment_light_exposure, 0.0):
		_fail("An unseen Darkness Ghost banked environmental-light exposure.")
		return

	# Keep the room light off so the unseen hunt-clock grace is verified
	# independently from environmental-light immunity.
	room_light.visible = false
	await process_frame

	# A hunt that only ends on a kill or a light death is a hunt that usually
	# never ends - which left a whole night holding exactly one encounter. It
	# now gives up on its own, and that is what paces the next one.
	# Grace, half two: while unseen that clock runs at unseen_hunt_time_scale, so
	# a full hunt_duration of real time is not enough to end it.
	ghost._hunt_time_left = ghost.hunt_duration
	ghost._process(ghost.hunt_duration)
	if not ghost.is_manifested():
		_fail("An unseen Darkness Ghost timed its hunt out on the seen clock.")
		return
	var unseen_remainder := ghost.hunt_duration * (1.0 - ghost.unseen_hunt_time_scale)
	if not is_equal_approx(ghost._hunt_time_left, unseen_remainder):
		_fail("The unseen hunt clock did not tick at unseen_hunt_time_scale.")
		return

	ghost._has_been_seen = true
	ghost._process(unseen_remainder - 0.1)
	if not ghost.is_manifested():
		_fail("Darkness Ghost abandoned its hunt before hunt_duration elapsed.")
		return
	ghost._process(0.2)
	if ghost.is_manifested() or ghost.is_dead():
		_fail("Darkness Ghost did not end its hunt after hunt_duration and retreat.")
		return
	if not is_equal_approx(ghost._next_manifest_in, ghost.manifest_interval):
		_fail("A timed-out hunt did not schedule the next manifest.")
		return
	if not ghost.has_been_seen():
		_fail("The completed encounter lost its sighting latch before the next manifest.")
		return
	ghost._set_manifested(true)
	ghost.encounter_phase = DarknessGhost.EncounterPhase.CHASING
	room_light.visible = true
	await process_frame

	# The timer must still require one continuous exposure; briefly leaving the
	# light resets it before the final 0.5-second hold.
	ghost._update_light_exposure(ghost.light_death_seconds - 0.1)
	if ghost.is_dead():
		_fail("Environmental light killed the ghost before light_death_seconds elapsed.")
		return
	room_light.visible = false
	await process_frame
	ghost._update_light_exposure(0.1)
	room_light.visible = true
	await process_frame
	ghost._update_light_exposure(ghost.light_death_seconds + 0.01)
	if ghost.is_dead() or ghost.is_manifested() or not ghost.auto_manifest:
		_fail("Environmental light did not end only the current Darkness hunt.")
		return
	if not is_equal_approx(ghost._next_manifest_in, ghost.manifest_interval):
		_fail("Environmental-light defeat did not schedule the normal cooldown.")
		return

	print("Darkness light response smoke test passed: light immunity before each encounter's first sighting, half-rate unseen hunt clock, continuous 0.5-second environmental-light retreat, flashlight retreat, and normal remanifest cooldown.")
	quit()


func _add_player_with_flashlight(parent: Node3D, index: int) -> SpotLight3D:
	var player := Node3D.new()
	player.name = "Player%d" % index
	player.add_to_group(&"players")
	parent.add_child(player)
	player.global_position = Vector3(float(index - 1) * 0.5, 1.0, 0.0)
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	player.add_child(pivot)
	var camera := Node3D.new()
	camera.name = "Camera3D"
	pivot.add_child(camera)
	var flashlight := SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.spot_range = 15.0
	flashlight.spot_angle = 40.0
	flashlight.light_energy = 2.4
	flashlight.add_to_group(&"local_light_sources")
	camera.add_child(flashlight)
	return flashlight


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
