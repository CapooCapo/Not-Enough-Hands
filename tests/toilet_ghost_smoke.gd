extends SceneTree

## ToiletGhost smoke test. Drives the ghost's arm()/update()/reset() API
## directly - the same functions ToiletMinigame calls from
## start_session()/_process()/_cleanup() - rather than waiting on real
## timing, matching this suite's existing convention (see
## tests/toilet_minigame_smoke.gd) of calling internal methods directly for
## determinism instead of simulating real input/time.

const STEP_DELTA := 0.1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://tests/player_test.tscn") as PackedScene
	var test_scene := packed_scene.instantiate()
	root.add_child(test_scene)

	var player := test_scene.get_node("Player") as CharacterBody3D
	var toilet := test_scene.get_node("TestToilet")
	var minigame: Node = toilet.get_node("ToiletMinigame")
	var ghost: Node = minigame.toilet_ghost
	if not ghost:
		push_error("ToiletMinigame has no ToiletGhost child to test.")
		quit(1)
		return
	var camera: Camera3D = player.get_node("CameraPivot/Camera3D")
	var camera_pivot: Node3D = player.get_node("CameraPivot")

	player.global_position = Vector3(12.0, 1.0, 2.0)
	player.global_rotation = Vector3.ZERO
	toilet.global_position = Vector3(12.0, 1.22, 0.5)
	player.bladder.bladder_fill_rate = 0.0

	await physics_frame
	await physics_frame

	# --- Configured values match the required spec exactly, not just
	# "internally consistent with itself" - every other check in this file
	# reads these exports dynamically, so a regressed default would
	# otherwise pass every other assertion silently. ---
	if not is_equal_approx(ghost.initial_spawn_delay, 2.0):
		push_error("initial_spawn_delay is %.2f, not the required 2.0." % ghost.initial_spawn_delay)
		quit(1)
		return
	if not is_equal_approx(ghost.min_respawn_delay, 3.0):
		push_error("min_respawn_delay is %.2f, not the required 3.0." % ghost.min_respawn_delay)
		quit(1)
		return
	if not is_equal_approx(ghost.max_respawn_delay, 5.0):
		push_error("max_respawn_delay is %.2f, not the required 5.0." % ghost.max_respawn_delay)
		quit(1)
		return

	# --- Initial delay: no ghost before 2.0s, exactly (no randomization for
	# the first spawn of a session). ---
	ghost.arm()
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("arm() did not enter the WAITING phase.")
		quit(1)
		return
	if not is_equal_approx(ghost._spawn_timer, ghost.initial_spawn_delay):
		push_error("The first spawn delay was randomized; it must be exactly initial_spawn_delay.")
		quit(1)
		return
	var elapsed := 0.0
	while elapsed < ghost.initial_spawn_delay - STEP_DELTA:
		ghost.update(STEP_DELTA, player, camera)
		elapsed += STEP_DELTA
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("Ghost spawned before initial_spawn_delay elapsed (elapsed=%.2f)." % elapsed)
		quit(1)
		return

	# --- First spawn: happens once initial_spawn_delay has elapsed. ---
	while elapsed < ghost.initial_spawn_delay + STEP_DELTA and ghost.phase == ghost.GhostPhase.WAITING:
		ghost.update(STEP_DELTA, player, camera)
		elapsed += STEP_DELTA
	if ghost.phase != ghost.GhostPhase.VISIBLE:
		push_error("Ghost did not spawn shortly after initial_spawn_delay elapsed.")
		quit(1)
		return

	# --- Ghost faces the player horizontally after spawning (not the
	# camera - the player's own position, which is what look_at-style
	# facing means here). ---
	var facing_error := _ghost_facing_error(ghost, player)
	if facing_error != "":
		push_error(facing_error)
		quit(1)
		return

	# --- Spawn position: never at the player's own position, and within the
	# configured [min, max] distance from it. ---
	if not ghost._is_position_clear(ghost.global_position):
		push_error("Ghost spawned inside blocking geometry.")
		quit(1)
		return
	if ghost.global_position.distance_to(player.global_position) < 0.01:
		push_error("Ghost spawned exactly at the player's own position.")
		quit(1)
		return
	var spawn_distance: float = Vector2(player.global_position.x, player.global_position.z).distance_to(
		Vector2(ghost.global_position.x, ghost.global_position.z)
	)
	if spawn_distance < ghost.spawn_min_distance - 0.01 or spawn_distance > ghost.spawn_max_distance + 0.01:
		push_error("Ghost spawn distance %.2f outside the configured [%.2f, %.2f] range." % [
			spawn_distance, ghost.spawn_min_distance, ghost.spawn_max_distance
		])
		quit(1)
		return

	# --- Spawn spread: consecutive spawns never reuse a zone, always clear
	# the minimum angle separation, keep distance inside the configured
	# range, and reach every zone rather than clustering. Driven over many
	# spawns because all three are randomized per spawn.
	#
	# The toilet itself is temporarily moved out of the way: it sits right in
	# front of the player, and the (correct) head-height occlusion rule
	# rejects front-zone candidates hidden behind it, which would make "every
	# zone is reachable" untestable here for reasons that have nothing to do
	# with the zone logic under test.
	var saved_toilet_position: Vector3 = toilet.global_position
	toilet.global_position = Vector3(40.0, 1.22, 40.0)
	# Pitched down toward the bowl, the way a real session leaves the camera
	# (see start_session()'s target_pitch). This matters for the distance
	# assertion below: spawn direction is derived from the camera's forward,
	# and an unflattened forward drags that pitch in and foreshortens every
	# distance by cos(pitch) - invisible with a level camera, which is why
	# this block deliberately does not run level.
	var spread_viewpoint := toilet.get_node("MinigameViewPoint") as Marker3D
	camera_pivot.rotation.x = spread_viewpoint.global_rotation.x
	await physics_frame
	await physics_frame
	ghost.arm()
	var zone_counts := [0, 0, 0, 0, 0]
	var previous_zone := -1
	var previous_angle := 0.0
	for i in 200:
		var candidate: Vector3 = ghost._pick_spawn_position(player, camera)
		var zone: int = ghost._last_spawn_zone
		var angle: float = ghost._last_spawn_angle
		zone_counts[zone] += 1
		if zone == previous_zone:
			push_error("Spawn %d reused the previous zone (%d) - consecutive spawns must differ." % [i, zone])
			quit(1)
			return
		if previous_zone >= 0 and absf(angle - previous_angle) < ghost.min_spawn_angle_separation - 0.001:
			push_error("Spawn %d was only %.1f deg from the previous one (minimum %.1f)." % [
				i, absf(angle - previous_angle), ghost.min_spawn_angle_separation
			])
			quit(1)
			return
		if absf(angle) > ghost.spawn_yaw_range + 0.001:
			push_error("Spawn %d angle %.1f deg is outside the reachable +-%.1f range." % [i, angle, ghost.spawn_yaw_range])
			quit(1)
			return
		var flat_distance: float = Vector2(candidate.x, candidate.z).distance_to(
			Vector2(player.global_position.x, player.global_position.z)
		)
		if flat_distance < ghost.spawn_min_distance - 0.05 or flat_distance > ghost.spawn_max_distance + 0.05:
			push_error("Spawn %d distance %.2f is outside the configured [%.1f, %.1f] range." % [
				i, flat_distance, ghost.spawn_min_distance, ghost.spawn_max_distance
			])
			quit(1)
			return
		previous_zone = zone
		previous_angle = angle
	for zone_index in zone_counts.size():
		if zone_counts[zone_index] == 0:
			push_error("Spawn zone %d was never used across 200 spawns - the spread has collapsed." % zone_index)
			quit(1)
			return
	toilet.global_position = saved_toilet_position
	camera_pivot.rotation.x = 0.0
	await physics_frame
	await physics_frame

	# --- Spawn fallback: even if every candidate is invalid (fully blocked
	# spawn area), the ghost must still end up somewhere - and never at the
	# player's own exact position. Forced without touching the scene tree:
	# an absurdly large clearance radius makes every candidate's own
	# clearance sphere overlap nearby world geometry (floor/walls), so
	# _is_position_clear() always rejects it, exactly like a fully blocked
	# room would.
	var original_clearance_radius: float = ghost.spawn_clearance_radius
	ghost.spawn_clearance_radius = 100.0
	var fallback_candidate: Vector3 = ghost._pick_spawn_position(player, camera)
	ghost.spawn_clearance_radius = original_clearance_radius
	if fallback_candidate.distance_to(player.global_position) < ghost.spawn_min_distance - 0.01:
		push_error("With every candidate blocked, the spawn fallback still landed on (or too close to) the player.")
		quit(1)
		return

	# --- Spawn direction: within spawn_yaw_range of the camera orientation at
	# the moment the session started (here, since the player never rotated,
	# that's just the current forward). Sampled repeatedly since the angle is
	# randomized per spawn. ---
	var reference_forward: Vector3 = ghost._session_start_forward(camera, player)
	for i in 60:
		var candidate: Vector3 = ghost._pick_spawn_position(player, camera)
		var offset := candidate - player.global_position
		offset.y = 0.0
		if offset.length() < 0.01:
			continue
		var angle_deg: float = rad_to_deg(reference_forward.angle_to(offset.normalized()))
		if angle_deg > ghost.spawn_yaw_range + 0.5:
			push_error("Spawn candidate at %.1f deg exceeds spawn_yaw_range (%.1f deg)." % [angle_deg, ghost.spawn_yaw_range])
			quit(1)
			return
	ghost.reset()

	# --- Spawn: the head-height detection point must never be occluded, even
	# when the floor-level base point is clear. Sprint 5 found a real
	# repeatable case here: the toilet's own body (spanning roughly y=0.8 to
	# y=1.6) sat between the camera and a candidate's *head* while its
	# floor-level base point had a clear line - producing a ghost that could
	# never be seen no matter how the player aimed. Reproducing it needs the
	# camera pitched down toward the bowl the way a real session leaves it
	# (see start_session()'s target_pitch) - an unpitched, level camera
	# barely triggers it at all. Sampled repeatedly since spawn position is
	# randomized; a single sample could get lucky (empirically ~6-7% of
	# calls hit it against the unfixed code, so 200 samples is well past the
	# point of being a reliable regression guard).
	var viewpoint := toilet.get_node("MinigameViewPoint") as Marker3D
	camera_pivot.rotation.x = viewpoint.global_rotation.x
	for i in 200:
		var candidate: Vector3 = ghost._pick_spawn_position(player, camera)
		var candidate_head := candidate + Vector3(0, ghost.head_height, 0)
		if ghost._is_path_blocked(camera.global_position, candidate_head, player):
			push_error("Spawn candidate's head-height point is occluded even though the spawn algorithm accepted it (trial %d, candidate=%s)." % [i, candidate])
			quit(1)
			return
	camera_pivot.rotation.x = 0.0

	# --- FOV helper: reused by both spawn preference and detection. ---
	# Kept well short of the toilet (1.5m ahead, 0.5x0.8x0.7 collision box) so
	# these "clear line of sight" checks don't clip its own geometry.
	player.global_rotation = Vector3.ZERO
	await physics_frame
	var point_ahead: Vector3 = camera.global_position + (-camera.global_basis.z) * 0.8
	var point_behind: Vector3 = camera.global_position + camera.global_basis.z * 0.8
	if not ghost._is_inside_camera_fov(camera, point_ahead):
		push_error("A point directly ahead of the camera was not judged inside its FOV.")
		quit(1)
		return
	if ghost._is_inside_camera_fov(camera, point_behind):
		push_error("A point directly behind the camera was judged inside its FOV.")
		quit(1)
		return

	# --- Detection: outside FOV -> not seen. ---
	if ghost._camera_can_see_point(camera, player, point_behind):
		push_error("A point behind the camera was reported as seen.")
		quit(1)
		return

	# --- Detection: inside FOV, unobstructed -> seen. ---
	if not ghost._camera_can_see_point(camera, player, point_ahead):
		push_error("A point directly ahead and unobstructed was not reported as seen.")
		quit(1)
		return

	# --- Detection: inside FOV, blocked by geometry -> not seen. ---
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(2.0, 2.0, 0.1)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	root.add_child(wall)
	wall.global_position = camera.global_position + (-camera.global_basis.z) * 0.4
	await physics_frame
	if ghost._camera_can_see_point(camera, player, point_ahead):
		push_error("A point behind blocking geometry was reported as seen.")
		quit(1)
		return
	wall.queue_free()
	await physics_frame

	# --- Camera: yaw clamp is +-90 degrees around the orientation the
	# session started with (0 degrees), matching spawn_yaw_range. ---
	player.call("_try_interact")
	if minigame.current_state != minigame.MinigameState.PLAYING:
		push_error("Interacting with the toilet did not start the minigame for the camera-clamp case.")
		quit(1)
		return
	if not is_equal_approx(player.yaw_clamp_min, deg_to_rad(minigame.min_camera_rotation_y)) \
			or not is_equal_approx(player.yaw_clamp_max, deg_to_rad(minigame.max_camera_rotation_y)):
		push_error("Yaw clamp does not match ToiletMinigame's configured range.")
		quit(1)
		return
	if not is_equal_approx(minigame.min_camera_rotation_y, -90.0) or not is_equal_approx(minigame.max_camera_rotation_y, 90.0):
		push_error("Toilet camera yaw range is not +-90 degrees (min=%.1f max=%.1f)." % [
			minigame.min_camera_rotation_y, minigame.max_camera_rotation_y
		])
		quit(1)
		return
	if not is_equal_approx(player.accumulated_yaw, 0.0):
		push_error("accumulated_yaw should start at 0 - the session-start orientation is the 0-degree reference.")
		quit(1)
		return

	# --- Success: seeing the ghost starts the eye-contact reaction, not an
	# instant disappearance - see minigames/toilet_ghost.gd's GhostPhase.SEEN.
	# This is also Ghost #1 of the multiple-spawns sequence below. ---
	ghost.initial_spawn_delay = 0.0
	ghost.reaction_time = 0.05 # about to expire - proves detection cancels it, not luck
	ghost.ghost_seen_duration = 0.5
	# Respawn delays deliberately left at their real configured values so the
	# repeat-spawn timing below tests the shipped 3-6s window, not a stub.
	ghost.arm()
	ghost.update(0.01, player, camera) # 0-delay roll: spawns immediately
	if ghost.phase != ghost.GhostPhase.VISIBLE:
		push_error("Ghost #1 did not spawn with a zeroed initial delay.")
		quit(1)
		return
	# Force it into plain view for a deterministic "seen" check regardless of
	# where it happened to land. The "seen" check targets visual.global_position
	# + head_height (see _head_position()), so place the visual that far below
	# the target point.
	ghost.visual.global_position = point_ahead - Vector3(0, ghost.head_height, 0)
	var seen_count := [0]
	ghost.ghost_seen.connect(func(): seen_count[0] += 1)

	# Ghost detected, but must NOT disappear immediately.
	ghost.update(STEP_DELTA, player, camera)
	if ghost.phase != ghost.GhostPhase.SEEN:
		push_error("Looking at the ghost did not enter the SEEN hold phase.")
		quit(1)
		return
	if not ghost.visual.visible:
		push_error("Ghost disappeared the instant it was seen instead of holding for ghost_seen_duration.")
		quit(1)
		return

	# Once seen, the (already-expired-if-it-still-counted) reaction timeout
	# must not be able to kill the player. 3 steps (0.3s) is comfortably
	# short of the 0.5s hold, so this also checks it hasn't disappeared yet.
	for i in 3:
		ghost.update(STEP_DELTA, player, camera)
	if not player.is_alive:
		push_error("The reaction timeout killed the player after the ghost had already been seen.")
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.SEEN or not ghost.visual.visible:
		push_error("Ghost left the SEEN hold (or disappeared) well before ghost_seen_duration elapsed.")
		quit(1)
		return

	# Disappears once ghost_seen_duration has elapsed, forcing the existing
	# player blink the instant it does.
	if player.eyes_closed:
		push_error("Player's eyes were already closed before the ghost disappeared.")
		quit(1)
		return
	var disappear_iterations := 0
	while ghost.phase == ghost.GhostPhase.SEEN and disappear_iterations < 100:
		ghost.update(STEP_DELTA, player, camera)
		disappear_iterations += 1
	if ghost.phase != ghost.GhostPhase.DISAPPEARING:
		push_error("Ghost never entered DISAPPEARING after ghost_seen_duration elapsed.")
		quit(1)
		return
	if ghost.visual.visible:
		push_error("Ghost visual remained visible after ghost_seen_duration elapsed.")
		quit(1)
		return
	if not player.eyes_closed:
		push_error("Ghost disappearing did not force the player's existing blink.")
		quit(1)
		return

	# The blink must not remain stuck: it reopens on its own shortly after,
	# driven by the ghost's own timer (see force_blink_now()'s doc comment in
	# player.gd for why it can't rely on the player's own _physics_process
	# here). Finishing the blink also re-arms the spawn loop (Ghost #2).
	var blink_iterations := 0
	while ghost.phase == ghost.GhostPhase.DISAPPEARING and blink_iterations < 100:
		ghost.update(STEP_DELTA, player, camera)
		blink_iterations += 1
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("Ghost did not re-arm for a repeat spawn after the forced blink finished.")
		quit(1)
		return
	if player.eyes_closed:
		push_error("The forced blink remained stuck closed instead of reopening.")
		quit(1)
		return
	if seen_count[0] != 1:
		push_error("ghost_seen did not fire exactly once for the full eye-contact sequence.")
		quit(1)
		return
	if ghost.teleport_audio.playing:
		push_error("Teleport audio kept playing after the ghost was seen and disappeared.")
		quit(1)
		return
	if not player.is_alive:
		push_error("Success incorrectly killed the player.")
		quit(1)
		return

	# The toilet minigame (bar, A/D, camera) continues normally throughout
	# and after the sequence - nothing above paused or reset it.
	if minigame.current_state != minigame.MinigameState.PLAYING:
		push_error("The eye-contact reaction should not end the toilet minigame.")
		quit(1)
		return
	minigame.player_offset = 0.0
	minigame.nozzle_velocity = 0.0
	Input.action_press("move_right")
	minigame._handle_input(STEP_DELTA)
	Input.action_release("move_right")
	if minigame.player_offset <= 0.0:
		push_error("A/D bar control stopped working after the eye-contact reaction.")
		quit(1)
		return
	if not is_equal_approx(player.pitch_clamp_min, deg_to_rad(minigame.min_camera_rotation_x)) \
			or not is_equal_approx(player.pitch_clamp_max, deg_to_rad(minigame.max_camera_rotation_x)):
		push_error("Camera pitch clamp changed as a side effect of the eye-contact reaction.")
		quit(1)
		return

	# --- Repeat spawn (Ghost #2): must not appear during the first
	# min_respawn_delay seconds of the wait, and must appear by
	# max_respawn_delay - both re-rolled fresh from _arm_respawn(). ---
	if ghost._spawn_timer < ghost.min_respawn_delay - 0.01 or ghost._spawn_timer > ghost.max_respawn_delay + 0.01:
		push_error("Respawn timer %.2f is outside the configured [%.1f, %.1f] range." % [
			ghost._spawn_timer, ghost.min_respawn_delay, ghost.max_respawn_delay
		])
		quit(1)
		return
	var respawn_elapsed := 0.0
	while respawn_elapsed < ghost.min_respawn_delay - STEP_DELTA:
		ghost.update(STEP_DELTA, player, camera)
		respawn_elapsed += STEP_DELTA
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("Ghost #2 spawned before the minimum respawn delay elapsed.")
		quit(1)
		return
	var respawn_iterations := 0
	while ghost.phase == ghost.GhostPhase.WAITING and respawn_iterations < 100:
		ghost.update(STEP_DELTA, player, camera)
		respawn_iterations += 1
	if ghost.phase != ghost.GhostPhase.VISIBLE:
		push_error("Ghost #2 never spawned within the configured maximum respawn delay.")
		quit(1)
		return
	if float(respawn_iterations) * STEP_DELTA > ghost.max_respawn_delay + STEP_DELTA * 2.0:
		push_error("Ghost #2 took longer than max_respawn_delay to appear.")
		quit(1)
		return
	var g2_facing_error := _ghost_facing_error(ghost, player)
	if g2_facing_error != "":
		push_error("Ghost #2: " + g2_facing_error)
		quit(1)
		return
	if not ghost.teleport_audio.playing:
		push_error("Repeat spawn did not play the teleport audio again.")
		quit(1)
		return

	# Drive Ghost #2 through the same full seen -> disappear -> blink ->
	# re-armed cycle as Ghost #1, matching "#1 -> disappear -> #2 ->
	# disappear -> #3" - just spawning it isn't enough to prove the loop
	# really repeats a full encounter, not just a timer.
	ghost.visual.global_position = point_ahead - Vector3(0, ghost.head_height, 0)
	ghost.update(STEP_DELTA, player, camera)
	if ghost.phase != ghost.GhostPhase.SEEN:
		push_error("Ghost #2 was not detected.")
		quit(1)
		return
	var g2_iterations := 0
	while ghost.phase != ghost.GhostPhase.WAITING and g2_iterations < 200:
		ghost.update(STEP_DELTA, player, camera)
		g2_iterations += 1
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("Ghost #2's full seen/disappear/blink cycle did not complete and re-arm.")
		quit(1)
		return
	if seen_count[0] != 2:
		push_error("Expected exactly 2 successful sightings after Ghost #2 (Ghosts #1-#2), got %d." % seen_count[0])
		quit(1)
		return

	# --- Maximum respawn delay: sampled repeatedly (the roll is random),
	# never exceeds max_respawn_delay. Re-arming the ghost's own timer here
	# is fine to do destructively - Ghost #3 below calls arm() again first,
	# so nothing from this loop needs to survive it.
	for i in 100:
		ghost._arm_respawn()
		if ghost._spawn_timer > ghost.max_respawn_delay + 0.001:
			push_error("_arm_respawn() rolled %.3f, exceeding max_respawn_delay (%.1f)." % [ghost._spawn_timer, ghost.max_respawn_delay])
			quit(1)
			return
		if ghost._spawn_timer < ghost.min_respawn_delay - 0.001:
			push_error("_arm_respawn() rolled %.3f, under min_respawn_delay (%.1f)." % [ghost._spawn_timer, ghost.min_respawn_delay])
			quit(1)
			return

	# --- No duplicate timers: re-arming twice in a row (as if two
	# disappearance events somehow both tried to schedule a respawn) must
	# leave exactly one pending timer - the single _spawn_timer float is
	# fully overwritten each time, so there is structurally nowhere for a
	# second one to live. Confirmed by driving it: exactly one WAITING->
	# VISIBLE transition occurs, at the SECOND roll's duration, not the
	# first's and not both. ---
	ghost._arm_respawn()
	var first_roll: float = ghost._spawn_timer
	ghost._arm_respawn()
	var second_roll: float = ghost._spawn_timer
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("Re-arming left the ghost outside WAITING.")
		quit(1)
		return
	var dup_elapsed := 0.0
	var dup_transitions := 0
	while ghost.phase == ghost.GhostPhase.WAITING and dup_elapsed < second_roll + 1.0:
		ghost.update(STEP_DELTA, player, camera)
		dup_elapsed += STEP_DELTA
		if ghost.phase == ghost.GhostPhase.VISIBLE:
			dup_transitions += 1
	if dup_transitions != 1:
		push_error("Re-arming twice produced %d spawn transitions instead of exactly 1 (first_roll=%.2f second_roll=%.2f)." % [
			dup_transitions, first_roll, second_roll
		])
		quit(1)
		return
	if dup_elapsed < second_roll - STEP_DELTA * 2.0:
		push_error("Ghost spawned at %.2fs, before the second (winning) roll of %.2fs - the first roll leaked through." % [dup_elapsed, second_roll])
		quit(1)
		return
	ghost.reset()

	# --- Single reaction timer: the same "re-trigger can't create a second
	# pending timer" guarantee, but for detection (_on_seen()) rather than
	# respawn (_arm_respawn()). Calling _on_seen() twice - as if the "player
	# looked at it" check somehow fired twice for one encounter - must still
	# leave exactly one _seen_timer, resolving at ghost_seen_duration from
	# the SECOND call, not sooner and not twice. ---
	ghost.initial_spawn_delay = 0.0
	ghost.arm()
	ghost.update(0.01, player, camera)
	if ghost.phase != ghost.GhostPhase.VISIBLE:
		push_error("Ghost did not spawn for the single-reaction-timer case.")
		quit(1)
		return
	ghost._on_seen()
	var redetect_steps := 0
	while redetect_steps < 2 and ghost.phase == ghost.GhostPhase.SEEN:
		ghost.update(STEP_DELTA, player, camera)
		redetect_steps += 1
	ghost._on_seen() # simulated re-trigger, partway through the first hold
	if not is_equal_approx(ghost._seen_timer, ghost.ghost_seen_duration):
		push_error("Re-triggering detection did not cleanly reset to a single fresh ghost_seen_duration timer (got %.3f, expected %.3f)." % [
			ghost._seen_timer, ghost.ghost_seen_duration
		])
		quit(1)
		return
	var redetect_iterations := 0
	var redetect_disappear_transitions := 0
	var redetect_prev_phase = ghost.phase
	while ghost.phase != ghost.GhostPhase.WAITING and redetect_iterations < 200:
		ghost.update(STEP_DELTA, player, camera)
		redetect_iterations += 1
		if redetect_prev_phase != ghost.GhostPhase.DISAPPEARING and ghost.phase == ghost.GhostPhase.DISAPPEARING:
			redetect_disappear_transitions += 1
		redetect_prev_phase = ghost.phase
	if redetect_disappear_transitions != 1:
		push_error("Re-triggering detection produced %d disappear transitions instead of exactly 1." % redetect_disappear_transitions)
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("The single-reaction-timer case did not complete its cycle and re-arm.")
		quit(1)
		return
	ghost.reset()

	# --- Multiple spawns (Ghost #3): see the ghost through one more full
	# seen -> disappear -> blink -> re-armed cycle, proving the loop is not
	# one-shot (it already produced #1 and #2 above). ---
	ghost.arm()
	ghost.initial_spawn_delay = 0.0
	ghost.arm() # re-apply the zeroed delay
	ghost.update(0.01, player, camera)
	if ghost.phase != ghost.GhostPhase.VISIBLE:
		push_error("Ghost #3 did not spawn.")
		quit(1)
		return
	var g3_facing_error := _ghost_facing_error(ghost, player)
	if g3_facing_error != "":
		push_error("Ghost #3: " + g3_facing_error)
		quit(1)
		return
	ghost.visual.global_position = point_ahead - Vector3(0, ghost.head_height, 0)
	ghost.update(STEP_DELTA, player, camera)
	if ghost.phase != ghost.GhostPhase.SEEN:
		push_error("Ghost #3 was not detected.")
		quit(1)
		return
	var g3_iterations := 0
	while ghost.phase != ghost.GhostPhase.WAITING and g3_iterations < 200:
		ghost.update(STEP_DELTA, player, camera)
		g3_iterations += 1
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("Ghost #3's full seen/disappear/blink cycle did not complete and re-arm.")
		quit(1)
		return
	if seen_count[0] != 4:
		push_error("Expected exactly 4 successful sightings (Ghosts #1-#3 plus the single-reaction-timer case), got %d." % seen_count[0])
		quit(1)
		return

	# --- Multiple cycles, measured: Ghosts #4-#7 continue the loop with the
	# real (not zeroed) respawn timing, each interval measured precisely and
	# checked against [min_respawn_delay, max_respawn_delay]. Also confirms
	# there is never more than one active ghost / one pending timer: every
	# cycle sees exactly one WAITING->VISIBLE transition, and phase is
	# tracked every single step, not just polled at the end.
	var measured_intervals := []
	for cycle in range(4, 8):
		var interval_elapsed := 0.0
		var visible_transitions := 0
		while ghost.phase == ghost.GhostPhase.WAITING and interval_elapsed < ghost.max_respawn_delay + 1.0:
			ghost.update(STEP_DELTA, player, camera)
			interval_elapsed += STEP_DELTA
			if ghost.phase == ghost.GhostPhase.VISIBLE:
				visible_transitions += 1
		if ghost.phase != ghost.GhostPhase.VISIBLE:
			push_error("Ghost #%d never spawned - a respawn was missed." % cycle)
			quit(1)
			return
		if visible_transitions != 1:
			push_error("Ghost #%d: expected exactly 1 spawn transition, saw %d (possible duplicate spawn/timer)." % [cycle, visible_transitions])
			quit(1)
			return
		if interval_elapsed < ghost.min_respawn_delay - STEP_DELTA or interval_elapsed > ghost.max_respawn_delay + STEP_DELTA:
			push_error("Ghost #%d respawned after %.2fs, outside the configured [%.1f, %.1f] range." % [
				cycle, interval_elapsed, ghost.min_respawn_delay, ghost.max_respawn_delay
			])
			quit(1)
			return
		measured_intervals.append(interval_elapsed)
		var cycle_facing_error := _ghost_facing_error(ghost, player)
		if cycle_facing_error != "":
			push_error("Ghost #%d: %s" % [cycle, cycle_facing_error])
			quit(1)
			return
		ghost.visual.global_position = point_ahead - Vector3(0, ghost.head_height, 0)
		ghost.update(STEP_DELTA, player, camera)
		if ghost.phase != ghost.GhostPhase.SEEN:
			push_error("Ghost #%d was not detected." % cycle)
			quit(1)
			return
		var cycle_iterations := 0
		while ghost.phase != ghost.GhostPhase.WAITING and cycle_iterations < 200:
			ghost.update(STEP_DELTA, player, camera)
			cycle_iterations += 1
		if ghost.phase != ghost.GhostPhase.WAITING:
			push_error("Ghost #%d's seen/disappear/blink cycle did not complete and re-arm." % cycle)
			quit(1)
			return
	if seen_count[0] != 8:
		push_error("Expected exactly 8 successful sightings (Ghosts #1-#3, the single-reaction-timer case, and #4-#7), got %d." % seen_count[0])
		quit(1)
		return
	print("Measured respawn intervals (Ghosts #4-#7, seconds): %s" % [measured_intervals])

	# --- Failure: not seeing it before the reaction timer expires kills the
	# player, and STOPS the spawn loop (no Ghost #4 after death). ---
	ghost.reaction_time = 1.0
	ghost.arm()
	ghost.initial_spawn_delay = 0.0
	ghost.arm()
	ghost.update(0.01, player, camera)
	if ghost.phase != ghost.GhostPhase.VISIBLE:
		push_error("Ghost did not spawn for the failure case.")
		quit(1)
		return
	# Force it out of view deterministically, regardless of where the spawn
	# algorithm happened to place it or which way the camera currently faces.
	var point_behind_now: Vector3 = camera.global_position + camera.global_basis.z * 3.0
	ghost.visual.global_position = point_behind_now - Vector3(0, ghost.head_height, 0)
	var timed_out_count := [0]
	ghost.ghost_timed_out.connect(func(): timed_out_count[0] += 1)
	var reaction_elapsed := 0.0
	while reaction_elapsed < 1.2 and ghost.phase == ghost.GhostPhase.VISIBLE:
		ghost.update(STEP_DELTA, player, camera)
		reaction_elapsed += STEP_DELTA
	if timed_out_count[0] != 1:
		push_error("Reaction timeout did not fire exactly once.")
		quit(1)
		return
	if player.is_alive:
		push_error("Missing the ghost's reaction window did not kill the player.")
		quit(1)
		return
	if ghost.teleport_audio.playing:
		push_error("Teleport audio kept playing after the ghost timed out and disappeared.")
		quit(1)
		return
	# The spawn loop must stop on death - no re-arm, unlike a successful
	# sighting. Stepping further must not produce another ghost.
	for i in 60:
		ghost.update(STEP_DELTA, player, camera)
	if ghost.phase != ghost.GhostPhase.IDLE:
		push_error("The spawn loop kept running after the player died instead of stopping.")
		quit(1)
		return

	# --- Failure, end to end (Sprint 10): the ghost's own ghost_timed_out
	# signal (unchanged name/emission point) now also drives
	# ToiletMinigame._on_toilet_ghost_caught(), which calls cancel()
	# synchronously - the minigame must stop immediately, not one frame
	# later via the is_alive guard as it used to. The existing death call
	# (kill_by_ghost(), asserted just above via player.is_alive) is
	# untouched; this only confirms the minigame-side reaction is now
	# immediate and that the new caught-scene beat was actually created. ---
	if minigame.current_state != minigame.MinigameState.CANCELLED:
		push_error("The minigame did not cancel immediately when the ghost caught the player.")
		quit(1)
		return
	var caught_instances := 0
	for child in minigame.get_children():
		if child is ToiletGhostCaught:
			caught_instances += 1
	if caught_instances != 1:
		push_error("Expected exactly 1 ToiletGhostCaught instance after the catch, found %d." % caught_instances)
		quit(1)
		return
	await minigame.session_ended
	if minigame.current_state != minigame.MinigameState.IDLE:
		push_error("Minigame did not return to IDLE after the death-triggered cleanup finished.")
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.IDLE or ghost.visual.visible:
		push_error("Ghost did not reset when death cancelled the minigame.")
		quit(1)
		return
	player.is_alive = true

	# --- Cleanup: a normal cancel also stops the ghost, whatever phase it's
	# in - here, still WAITING, never having spawned at all. Then verify
	# waiting past the maximum respawn delay produces no ghost after exit. ---
	await physics_frame
	player.call("_try_interact")
	if minigame.current_state != minigame.MinigameState.PLAYING:
		push_error("Toilet did not start a fresh session for the cleanup case.")
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("Starting a session did not arm the ghost into WAITING.")
		quit(1)
		return
	# The E press that started this session is ignored as a cancel request
	# until it is released (see ToiletMinigame._wait_for_interact_release);
	# only the press after that release actually cancels.
	minigame._unhandled_input(_make_interact_event())
	minigame._unhandled_input(_make_interact_release_event())
	minigame._unhandled_input(_make_interact_event())
	if minigame.current_state != minigame.MinigameState.CANCELLED:
		push_error("Interact did not cancel the session for the cleanup case.")
		quit(1)
		return
	await minigame.session_ended
	if ghost.phase != ghost.GhostPhase.IDLE:
		push_error("Ghost did not reset when the minigame cleaned up.")
		quit(1)
		return
	if ghost.visual.visible:
		push_error("Ghost visual remained visible after minigame cleanup.")
		quit(1)
		return
	# "exit minigame -> wait 5s -> MUST NOT spawn Ghost": the minigame no
	# longer calls ghost.update() at all once it's IDLE (ToiletMinigame._process()
	# returns immediately unless current_state == PLAYING), but drive the
	# ghost's own update() directly here anyway as the strongest possible
	# check that nothing spontaneously reactivates it.
	for i in 90: # 9.0s worth of steps - comfortably longer than max_respawn_delay
		ghost.update(STEP_DELTA, player, camera)
	if ghost.phase != ghost.GhostPhase.IDLE or ghost.visual.visible:
		push_error("A Ghost appeared more than 5 seconds after the minigame was exited.")
		quit(1)
		return

	# --- TEST 9a: exit during the 0.5s SEEN window (before it disappears). ---
	await physics_frame
	player.call("_try_interact")
	if minigame.current_state != minigame.MinigameState.PLAYING:
		push_error("Toilet did not start a fresh session for the exit-during-SEEN case.")
		quit(1)
		return
	ghost.initial_spawn_delay = 0.0
	ghost.ghost_seen_duration = 0.5
	ghost.arm()
	ghost.update(0.01, player, camera)
	ghost.visual.global_position = point_ahead - Vector3(0, ghost.head_height, 0)
	ghost.update(STEP_DELTA, player, camera)
	if ghost.phase != ghost.GhostPhase.SEEN:
		push_error("Ghost did not enter SEEN for the exit-during-SEEN case.")
		quit(1)
		return
	minigame._unhandled_input(_make_interact_event())
	minigame._unhandled_input(_make_interact_release_event())
	minigame._unhandled_input(_make_interact_event())
	if minigame.current_state != minigame.MinigameState.CANCELLED:
		push_error("Cancelling during the SEEN window did not cancel the session.")
		quit(1)
		return
	await minigame.session_ended
	if ghost.phase != ghost.GhostPhase.IDLE or ghost.visual.visible:
		push_error("Ghost was not fully removed when the minigame was exited during the SEEN window.")
		quit(1)
		return
	if player.eyes_closed:
		push_error("Exiting during the SEEN window (before any blink was forced) left the player's eyes closed.")
		quit(1)
		return
	# No delayed callback: stepping further must not suddenly resolve, blink,
	# or spawn another ghost.
	for i in 60:
		ghost.update(STEP_DELTA, player, camera)
	if ghost.phase != ghost.GhostPhase.IDLE or player.eyes_closed:
		push_error("A stale SEEN-window timer kept running, blinked, or respawned after the minigame was exited.")
		quit(1)
		return

	# --- TEST 9b: exit mid-blink (DISAPPEARING) - the critical case, since
	# force_blink_now() has already fired here and nothing else is left to
	# reopen the eyes if reset() didn't handle it.
	await physics_frame
	player.call("_try_interact")
	if minigame.current_state != minigame.MinigameState.PLAYING:
		push_error("Toilet did not start a fresh session for the exit-mid-blink case.")
		quit(1)
		return
	ghost.arm()
	ghost.update(0.01, player, camera)
	ghost.visual.global_position = point_ahead - Vector3(0, ghost.head_height, 0)
	ghost.update(STEP_DELTA, player, camera) # -> SEEN
	ghost.update(ghost.ghost_seen_duration + STEP_DELTA, player, camera) # -> DISAPPEARING, blink forced
	if ghost.phase != ghost.GhostPhase.DISAPPEARING or not player.eyes_closed:
		push_error("Failed to reach the mid-blink DISAPPEARING state to test exit-cleanup against.")
		quit(1)
		return
	minigame._unhandled_input(_make_interact_event())
	minigame._unhandled_input(_make_interact_release_event())
	minigame._unhandled_input(_make_interact_event())
	if minigame.current_state != minigame.MinigameState.CANCELLED:
		push_error("Cancelling mid-blink did not cancel the session.")
		quit(1)
		return
	await minigame.session_ended
	if ghost.phase != ghost.GhostPhase.IDLE or ghost.visual.visible:
		push_error("Ghost was not fully removed when the minigame was exited mid-blink.")
		quit(1)
		return
	if player.eyes_closed:
		push_error("Exiting mid-blink left the player's eyes stuck closed - reset() must reopen them.")
		quit(1)
		return
	for i in 60:
		ghost.update(STEP_DELTA, player, camera)
	if player.eyes_closed or ghost.phase != ghost.GhostPhase.IDLE:
		push_error("A stale blink-reopen or respawn timer fired after the minigame was exited mid-blink.")
		quit(1)
		return

	# --- Re-entry: completely clean state after the mid-blink exit above -
	# no leftover SEEN/DISAPPEARING phase, no leftover blink state. ---
	if ghost.phase != ghost.GhostPhase.IDLE:
		push_error("Ghost phase was not IDLE before re-entry.")
		quit(1)
		return
	if player.eyes_closed:
		push_error("Player's eyes were closed before re-entry even started.")
		quit(1)
		return

	# --- Cleanup: reaching minigame SUCCESS (not just cancel/death) while the
	# ghost is still active/unresolved must also clean it up - _cleanup() is
	# shared by succeed() and cancel(), but this exact path wasn't covered.
	await physics_frame
	player.call("_try_interact")
	if minigame.current_state != minigame.MinigameState.PLAYING:
		push_error("Toilet did not start a fresh session for the success-cleanup case.")
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.WAITING:
		push_error("Re-entering the minigame did not arm the ghost into a fresh WAITING state.")
		quit(1)
		return
	ghost.initial_spawn_delay = 0.0
	ghost.reaction_time = 5.0 # comfortably longer than the quick drive below
	ghost.arm()
	ghost.update(0.01, player, camera)
	if ghost.phase != ghost.GhostPhase.VISIBLE:
		push_error("Ghost did not spawn for the success-cleanup case.")
		quit(1)
		return
	player.bladder.current_value = 5.0 # small on purpose - fast, deterministic drain
	minigame.asset_anchor.position.x = 0.0
	minigame._flow_ramp_elapsed = minigame.pee_ramp_duration
	var success_iterations := 0
	while minigame.current_state == minigame.MinigameState.PLAYING and success_iterations < 2000:
		minigame._evaluate_balance(STEP_DELTA)
		success_iterations += 1
	if minigame.current_state != minigame.MinigameState.SUCCESS:
		push_error("Minigame never reached SUCCESS while the ghost was still active.")
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.VISIBLE:
		push_error("Ghost resolved on its own during the drive - this case needs it still unresolved to be meaningful.")
		quit(1)
		return
	await minigame.session_ended
	if minigame.current_state != minigame.MinigameState.IDLE:
		push_error("Minigame did not return to IDLE after success's cleanup finished.")
		quit(1)
		return
	if ghost.phase != ghost.GhostPhase.IDLE or ghost.visual.visible:
		push_error("Ghost was not cleaned up when the minigame succeeded while it was still active.")
		quit(1)
		return
	if ghost.teleport_audio.playing:
		push_error("Teleport audio kept playing after success cleaned up an active ghost.")
		quit(1)
		return

	print("Toilet ghost smoke test passed.")
	quit()


func _make_interact_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	return event


func _make_interact_release_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = false
	return event


## Returns "" if the ghost's horizontal forward points at the player (within
## a tight tolerance) with no unwanted pitch/roll introduced, otherwise a
## message describing what's wrong.
func _ghost_facing_error(ghost: Node, player: Node3D) -> String:
	var ghost_position: Vector3 = ghost.global_position
	var to_player: Vector3 = player.global_position - ghost_position
	to_player.y = 0.0
	var ghost_basis: Basis = ghost.global_transform.basis
	var ghost_forward: Vector3 = -ghost_basis.z
	ghost_forward.y = 0.0
	var angle_deg := rad_to_deg(ghost_forward.normalized().angle_to(to_player.normalized()))
	if angle_deg > 1.0:
		return "Ghost is not facing the player (angle=%.1f deg)." % angle_deg
	if not is_zero_approx(ghost.rotation.x) or not is_zero_approx(ghost.rotation.z):
		return "Facing the player introduced unwanted pitch/roll instead of staying horizontal-only."
	return ""
