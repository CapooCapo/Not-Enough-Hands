class_name ToiletGhost
extends Node3D

## Toilet-minigame-specific threat, owned and driven entirely by
## ToiletMinigame (arm()/update()/reset() called from its start_session()/
## _process()/_cleanup()). This has no _process() of its own, so it cannot
## run a single frame outside the toilet minigame's own already-guarded
## loop - nothing to leak, nothing to stop separately on exit.
##
## Visibility detection duplicates ghosts/statue_ghost.gd's
## _camera_can_see_point() idiom (FOV cone + frustum + occlusion raycast)
## rather than sharing code with it - that mirrors the existing project
## convention (each of the three ghosts already owns its own copy of this
## check; there is no shared perception utility today), and keeps
## statue_ghost.gd completely untouched.

signal ghost_seen
signal ghost_timed_out

## SEEN and DISAPPEARING are the eye-contact reaction added on top of the
## original WAITING/VISIBLE pair: once looked at, the ghost holds
## (SEEN) before actually vanishing and forcing a blink (DISAPPEARING),
## rather than disappearing the instant it's detected.
enum GhostPhase { IDLE, WAITING, VISIBLE, SEEN, DISAPPEARING }

## Five equal slices of the reachable yaw range (spawn_yaw_range either side
## of the session-start facing), left to right. Consecutive ghosts never
## reuse the same slice, which is what stops several in a row appearing in
## the same corner of the room.
enum SpawnZone { LEFT, FRONT_LEFT, FRONT, FRONT_RIGHT, RIGHT }
const SPAWN_ZONE_COUNT := 5

@export_category("Spawn Timing")
## The first Ghost of a session always appears at exactly this many seconds
## in - not randomized, unlike the repeat spawns below.
@export var initial_spawn_delay: float = 2.0
## After a Ghost disappears (successfully seen), the next one appears after
## a fresh random wait in this range - never sooner than the minimum, never
## later than the maximum. Re-rolled every time.
@export var min_respawn_delay: float = 3.0
@export var max_respawn_delay: float = 5.0
@export var reaction_time: float = 3.0
## How long the ghost stays visible, in place, after being successfully
## looked at before it actually disappears. The reaction timeout can no
## longer kill the player once this window has started - the encounter has
## already succeeded.
@export var ghost_seen_duration: float = 0.5

@export_category("Spawn Position")
@export var spawn_min_distance: float = 2.0
@export var spawn_max_distance: float = 4.0
## Ghost spawns are sampled within this many degrees either side of the
## camera's orientation at the moment the toilet minigame started (not the
## camera's current, possibly-already-turned orientation), matching
## ToiletMinigame's own +-90 degree camera yaw clamp so every spawn is
## somewhere the player can turn to. Keep the two in sync if either is
## retuned; they aren't wired together to avoid reaching into another
## script's exports for one shared number.
@export var spawn_yaw_range: float = 90.0
## Consecutive spawns must differ in yaw by at least this much, on top of
## never reusing the previous zone - stops two ghosts in a row appearing in
## nearly the same direction even when they technically land in different
## adjacent zones.
@export var min_spawn_angle_separation: float = 45.0
## How many times to re-roll a zone/angle that violates the "different zone
## and far enough away" rules before giving up and taking the best-available
## pick (see _furthest_zone_angle()). Bounded so this can never spin.
@export var max_spawn_attempts: int = 10
@export var spawn_sample_count: int = 12
@export_flags_3d_physics var spawn_blocking_mask: int = 1
## Radius of the point-overlap check used to reject a spawn candidate that
## would land inside a wall/floor - mirrors player.gd's own _can_stand()
## shape-query idiom, not a new physics convention.
@export var spawn_clearance_radius: float = 0.2

@export_category("Detection")
@export var observation_half_angle: float = 30.0
## Must stay comfortably above spawn_max_distance. The ghost's head sits
## fractionally *above* the camera, so a ghost spawned at exactly
## spawn_max_distance is slightly further than that in true 3D distance -
## with the two equal, the furthest spawns fell the wrong side of this
## check and could never be seen at all.
@export var maximum_observation_distance: float = 6.0
@export_flags_3d_physics var sight_blocking_mask: int = 1
## Height of the Sprint 3 model's face above its own floor-anchored root
## (see assets/ghosts/toilet_ghost/README.md). The "seen" check targets this
## point rather than the root, so the player has to actually look at the
## head - not just glance at the ghost's feet.
@export var head_height: float = 1.58

var phase: GhostPhase = GhostPhase.IDLE
var _spawn_timer: float = 0.0
var _reaction_timer: float = 0.0
var _seen_timer: float = 0.0
var _blink_timer: float = 0.0
var _active_player: Node3D
var _rng := RandomNumberGenerator.new()
## Direction of the previous spawn, so the next one can be kept away from
## it. -1 means "no previous spawn this session" (the first ghost is free to
## use any zone). Reset with the rest of the session state.
var _last_spawn_zone: int = -1
var _last_spawn_angle: float = 0.0

@onready var visual: Node3D = $Visual
@onready var teleport_audio: AudioStreamPlayer3D = $TeleportAudio


func _ready() -> void:
	_rng.randomize()
	visual.visible = false
	# _pick_spawn_position() nudges its candidate up by spawn_clearance_radius
	# so the clearance-check sphere clears the floor - a physics-query fudge,
	# not the ghost's true resting height. Cancel it back out here so the
	# model's own floor-anchored root actually touches the floor instead of
	# hovering by that same amount.
	visual.position.y = -(spawn_clearance_radius + 0.02)


## Called by ToiletMinigame.start_session() - arms the fixed, non-random wait
## before the FIRST ghost of the session may spawn. Repeat spawns after that
## go through _arm_respawn() instead (see _finish_blink()).
func arm() -> void:
	phase = GhostPhase.WAITING
	_spawn_timer = initial_spawn_delay
	_reaction_timer = 0.0
	_seen_timer = 0.0
	_blink_timer = 0.0
	_active_player = null
	visual.visible = false
	# A new session starts with no spawn history, so its first ghost may use
	# any zone. _arm_respawn() deliberately does NOT clear this - the
	# "different zone from last time" rule has to survive between the ghosts
	# of one session, which is the whole point of tracking it.
	_last_spawn_zone = -1
	_last_spawn_angle = 0.0


## Re-arms the wait for the next ghost after the previous one disappeared -
## a fresh random roll every time, unlike the fixed initial delay in arm().
func _arm_respawn() -> void:
	phase = GhostPhase.WAITING
	_spawn_timer = _rng.randf_range(min_respawn_delay, maxf(min_respawn_delay, max_respawn_delay))
	_reaction_timer = 0.0
	_seen_timer = 0.0
	_blink_timer = 0.0
	_active_player = null
	visual.visible = false


## Called every frame by ToiletMinigame._process(), only while its own state
## is PLAYING - this is the only place update() is ever invoked from.
func update(delta: float, player: Node3D, camera: Camera3D) -> void:
	match phase:
		GhostPhase.WAITING:
			_spawn_timer -= delta
			if _spawn_timer <= 0.0:
				_spawn(player, camera)
		GhostPhase.VISIBLE:
			if not is_instance_valid(player) or not is_instance_valid(camera):
				return
			if _camera_can_see_point(camera, player, _head_position()):
				_on_seen()
				return
			_reaction_timer -= delta
			if _reaction_timer <= 0.0:
				_resolve_failure()
		GhostPhase.SEEN:
			_seen_timer -= delta
			if _seen_timer <= 0.0:
				_disappear()
		GhostPhase.DISAPPEARING:
			_blink_timer -= delta
			if _blink_timer <= 0.0:
				_finish_blink()


## Called by ToiletMinigame._cleanup() on every exit path (success, cancel,
## and death - which is itself just a cancel triggered by the existing
## is_alive guard). Unconditional, so nothing can outlive the session.
##
## If the minigame is exited mid-blink (DISAPPEARING - force_blink_now()
## already fired, end_forced_blink() has not run yet), the player's eyes
## would otherwise stay forced shut forever, since nothing else is left to
## reopen them once this ghost stops being driven. Reopening here is what
## satisfies "leaving the minigame must never leave a delayed callback able
## to blink the player later" for the one case that could actually strand
## the eyes closed.
func reset() -> void:
	if phase == GhostPhase.DISAPPEARING and is_instance_valid(_active_player) \
			and _active_player.has_method("end_forced_blink"):
		_active_player.call("end_forced_blink")
	phase = GhostPhase.IDLE
	_spawn_timer = 0.0
	_reaction_timer = 0.0
	_seen_timer = 0.0
	_blink_timer = 0.0
	_active_player = null
	visual.visible = false
	_last_spawn_zone = -1
	_last_spawn_angle = 0.0
	# Cancelling shortly after the ghost spawns (the teleport stinger is only
	# ~0.5s) could otherwise leave it audibly finishing after the ghost has
	# already disappeared and the minigame has moved on.
	teleport_audio.stop()


func _spawn(player: Node3D, camera: Camera3D) -> void:
	global_position = _pick_spawn_position(player, camera)
	_face_player(player)
	_active_player = player
	visual.visible = true
	phase = GhostPhase.VISIBLE
	_reaction_timer = reaction_time
	teleport_audio.play()


## Faces the ghost toward the player, horizontally only (no pitch, so its
## own dramatic head tilt from the Sprint 3 model isn't compounded by
## looking up/down at a height difference) - duplicated from
## ghosts/statue_ghost.gd's own face_player_on_freeze idiom
## (rotation.y = atan2(-flat_target.x, -flat_target.z)) rather than shared,
## matching this file's existing convention. The player's position is fixed
## for the rest of the toilet minigame session once it starts (movement is
## locked and never tweens again until the session ends), so orienting once
## at spawn is enough - nothing needs to re-face it every frame, and this
## node still has no _process() of its own.
func _face_player(player: Node3D) -> void:
	var flat_target := player.global_position - global_position
	flat_target.y = 0.0
	if not flat_target.is_zero_approx():
		rotation.y = atan2(-flat_target.x, -flat_target.z)


## The point the player actually needs to look at - see head_height's doc
## comment. This is what "seen" is checked against, not the root.
func _head_position() -> Vector3:
	return visual.global_position + Vector3(0, head_height, 0)


## Entered the instant the player looks directly at the ghost. It stays
## visible, in its current position, for ghost_seen_duration before actually
## disappearing - from this point on the reaction timeout can no longer
## kill the player; the encounter has already succeeded.
func _on_seen() -> void:
	phase = GhostPhase.SEEN
	_seen_timer = ghost_seen_duration


## After ghost_seen_duration has elapsed since detection: the ghost actually
## disappears, then the existing player blink API is forced so the beat
## reads as "I looked, it vanished, I blinked, it's gone" rather than a
## silent pop. The reopen is scheduled on this node's own timer (see
## _finish_blink()) rather than left to the player's _physics_process, which
## minigames like the toilet's disable for their whole duration - see
## force_blink_now()'s doc comment in player.gd.
func _disappear() -> void:
	phase = GhostPhase.DISAPPEARING
	visual.visible = false
	teleport_audio.stop()
	_blink_timer = _forced_blink_duration()
	if is_instance_valid(_active_player) and _active_player.has_method("force_blink_now"):
		_active_player.call("force_blink_now")


## Reopens the eyes closed by _disappear(), ends this encounter, and arms
## the next one - a successful sighting continues the spawn loop rather than
## ending it (only a missed reaction timeout - see _resolve_failure() - stops
## it, since the player is dead by then and the minigame is about to cancel).
func _finish_blink() -> void:
	var resolved_player := _active_player
	if is_instance_valid(resolved_player) and resolved_player.has_method("end_forced_blink"):
		resolved_player.call("end_forced_blink")
	ghost_seen.emit()
	_arm_respawn()


## How long the forced blink stays closed before _finish_blink() reopens it.
## Reuses the player's own existing forced_blink_duration convention (the
## same value force_blink() defaults to) instead of inventing a second,
## redundant "how long is a blink" constant.
func _forced_blink_duration() -> float:
	if _active_player and "forced_blink_duration" in _active_player:
		return _active_player.forced_blink_duration
	return 0.22


func _resolve_failure() -> void:
	phase = GhostPhase.IDLE
	visual.visible = false
	# A fast find can still be within the ~0.5s teleport stinger's length;
	# the ghost should disappear cleanly, not keep sounding after it's gone.
	teleport_audio.stop()
	var resolved_player := _active_player
	_active_player = null
	ghost_timed_out.emit()
	if is_instance_valid(resolved_player) and resolved_player.has_method("kill_by_ghost"):
		resolved_player.call("kill_by_ghost", self)


## The camera's forward direction at the moment the toilet minigame started,
## reconstructed from its current orientation rather than tracked separately -
## ToiletMinigame's yaw clamp holds player.accumulated_yaw as exactly the
## rotation applied since that moment, so undoing it recovers the original
## direction regardless of how far the player has since turned. Spawns are
## sampled around this fixed reference, not the live camera direction: the
## camera's own reachable range is fixed for the whole session too (it's a
## clamp on accumulated_yaw, not a moving window), so using the live
## direction could place a candidate outside where the player could ever
## turn to, particularly once they're already turned close to one limit.
## Flattened to the horizontal plane: the toilet camera starts pitched down
## toward the bowl, and an unflattened forward vector drags that pitch into
## the spawn offset, foreshortening every distance by cos(pitch) - a 2.0 m
## roll landed the ghost 1.73 m away, under its own configured minimum.
## Spawn direction is a compass bearing; the height comes from the floor.
func _session_start_forward(camera: Camera3D, player: Node3D) -> Vector3:
	var current_forward := -camera.global_basis.z
	current_forward.y = 0.0
	if current_forward.is_zero_approx():
		current_forward = Vector3.FORWARD
	current_forward = current_forward.normalized()
	var accumulated: float = player.accumulated_yaw if "accumulated_yaw" in player else 0.0
	return current_forward.rotated(Vector3.UP, -accumulated)


## Yaw range [low, high] in degrees covered by one spawn zone - the
## reachable arc split into SPAWN_ZONE_COUNT equal slices, left to right.
func _zone_bounds(zone: int) -> Vector2:
	var width := (spawn_yaw_range * 2.0) / float(SPAWN_ZONE_COUNT)
	var low := -spawn_yaw_range + width * float(zone)
	return Vector2(low, low + width)


## Picks the direction of the next spawn as {zone, angle}: a random zone
## that isn't the previous one, at a random angle inside it that is also at
## least min_spawn_angle_separation away from the previous angle. Both rules
## are pure arithmetic, so they're settled here before any physics work -
## _pick_spawn_position() then only has to retry on geometry, and can never
## trade the variety rules away to satisfy a clearance check.
func _next_zone_angle() -> Dictionary:
	for attempt in max_spawn_attempts:
		var zone := _rng.randi_range(0, SPAWN_ZONE_COUNT - 1)
		if zone == _last_spawn_zone:
			continue
		var bounds := _zone_bounds(zone)
		var angle := _rng.randf_range(bounds.x, bounds.y)
		if _last_spawn_zone >= 0 and absf(angle - _last_spawn_angle) < min_spawn_angle_separation:
			continue
		return {"zone": zone, "angle": angle}
	return _furthest_zone_angle()


## Best-available pick once the random retries above are spent: the zone
## whose far edge sits furthest from the last angle, at that far edge. Always
## a different zone and the largest separation on offer, so it honours both
## rules as closely as the range allows instead of spinning or giving up.
func _furthest_zone_angle() -> Dictionary:
	if _last_spawn_zone < 0:
		var any_zone := _rng.randi_range(0, SPAWN_ZONE_COUNT - 1)
		var any_bounds := _zone_bounds(any_zone)
		return {"zone": any_zone, "angle": _rng.randf_range(any_bounds.x, any_bounds.y)}

	var best_zone := 0
	var best_angle := 0.0
	var best_gap := -1.0
	for zone in SPAWN_ZONE_COUNT:
		if zone == _last_spawn_zone:
			continue
		var bounds := _zone_bounds(zone)
		for edge in [bounds.x, bounds.y]:
			var gap: float = absf(edge - _last_spawn_angle)
			if gap > best_gap:
				best_gap = gap
				best_zone = zone
				best_angle = edge
	return {"zone": best_zone, "angle": best_angle}


func _record_spawn(zone: int, angle_deg: float) -> void:
	_last_spawn_zone = zone
	_last_spawn_angle = angle_deg


## Places the ghost at a random distance along a direction chosen by
## _next_zone_angle() (see there for the zone/separation rules), measured
## from the fixed session-start camera facing so it is always somewhere the
## player can turn to - see _session_start_forward(). Rejects anything that
## overlaps blocking geometry or has no clear line from the player's eye to
## it (keeps it in the same open room the player is standing in without
## needing a navmesh or per-map markers), re-rolling direction and distance
## together on each retry. Never returns the player's own position.
##
## Deliberately does NOT require the spawn to be inside the camera's current
## frustum. The LEFT and RIGHT zones sit beyond the edge of a 70-degree FOV,
## so gating on the frustum would quietly make them unreachable and collapse
## the spawn spread back onto the three front zones - the exact clustering
## the zone rules exist to prevent. The ghost is still always within the
## camera's reachable yaw range, and still has to be actually looked at
## before it counts as seen.
func _pick_spawn_position(player: Node3D, camera: Camera3D) -> Vector3:
	var floor_y := _floor_y(player)
	var eye_position := camera.global_position if camera else player.global_position
	var reference_forward := _session_start_forward(camera, player) if camera else -player.global_transform.basis.z

	for i in spawn_sample_count:
		var pick := _next_zone_angle()
		var zone: int = pick["zone"]
		var angle_deg: float = pick["angle"]
		var distance := _rng.randf_range(spawn_min_distance, spawn_max_distance)
		var direction := reference_forward.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var candidate := player.global_position + direction * distance
		# The clearance sphere below is spawn_clearance_radius wide, so its
		# center must clear the floor by more than that radius or it always
		# overlaps the floor slab itself and every candidate gets rejected.
		candidate.y = floor_y + spawn_clearance_radius + 0.02

		if not _is_position_clear(candidate):
			continue
		# Validated at head height, not the floor-level candidate itself:
		# checking the base point let a candidate pass with a clear view to
		# its feet while its actual head - the point the live "seen" check
		# raycasts to every frame - sat behind the toilet's own body. That
		# produced ghosts that could never be seen no matter how the player
		# aimed (found via Sprint 5 playtest simulation - a real, reproducible
		# unwinnable-encounter bug, not a balance/tuning nuance).
		var candidate_head := candidate + Vector3(0, head_height, 0)
		if _is_path_blocked(eye_position, candidate_head, player):
			continue

		_record_spawn(zone, angle_deg)
		return candidate

	# Nowhere clear at all (a fully boxed-in room) - every one of
	# spawn_sample_count candidates failed clearance/occlusion. This must
	# never mean "skip this spawn"; still put the ghost in a fresh zone at
	# the near edge of the distance range rather than on top of the player.
	push_warning(
		"ToiletGhost: all %d spawn candidates were blocked; using an unvalidated fallback position." %
		spawn_sample_count
	)
	var last_resort := _next_zone_angle()
	_record_spawn(last_resort["zone"], last_resort["angle"])
	var last_resort_direction := reference_forward.rotated(Vector3.UP, deg_to_rad(last_resort["angle"]))
	var last_resort_position := player.global_position + last_resort_direction * spawn_min_distance
	last_resort_position.y = floor_y + spawn_clearance_radius + 0.02
	return last_resort_position


## Approximates the floor under the player from its own capsule, mirroring
## ghosts/statue_ghost.gd's _player_foot_y() without duplicating navigation.
func _floor_y(player: Node3D) -> float:
	var shape_node := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node:
		var capsule := shape_node.shape as CapsuleShape3D
		if capsule:
			return shape_node.global_position.y - capsule.height * 0.5
	return player.global_position.y


func _is_position_clear(position: Vector3) -> bool:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = spawn_clearance_radius
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.collision_mask = spawn_blocking_mask
	return space_state.intersect_shape(query, 1).is_empty()


func _is_path_blocked(from: Vector3, to: Vector3, player: Node3D) -> bool:
	var exclude: Array[RID] = []
	if player and player.has_method("get_rid"):
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, spawn_blocking_mask, exclude)
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()


func _is_inside_camera_fov(camera: Camera3D, point: Vector3) -> bool:
	var offset := point - camera.global_position
	var distance := offset.length()
	if distance <= 0.01:
		return true
	var look_dot := (-camera.global_basis.z).dot(offset / distance)
	return look_dot >= cos(deg_to_rad(observation_half_angle))


## Duplicated from ghosts/statue_ghost.gd's _camera_can_see_point() by
## design - see the class doc comment.
func _camera_can_see_point(camera: Camera3D, player: Node3D, point: Vector3) -> bool:
	var offset := point - camera.global_position
	var distance := offset.length()
	if distance <= 0.01 or distance > maximum_observation_distance:
		return false

	var look_dot := (-camera.global_basis.z).dot(offset / distance)
	if look_dot < cos(deg_to_rad(observation_half_angle)):
		return false
	if not camera.is_position_in_frustum(point):
		return false

	var exclude: Array[RID] = []
	if player and player.has_method("get_rid"):
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		point,
		sight_blocking_mask,
		exclude
	)
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


## Optional dev/testing hook, matching the existing per-ghost convention
## (statue/crawler/hunter all expose dev_force_spawn for DevTools/manual
## testing). Not wired into ui/dev_tools.gd in this sprint - that would
## touch an unrelated file - but kept available for the next sprint's
## manual playtest.
func dev_force_spawn(player: Node3D, camera: Camera3D) -> bool:
	if not is_instance_valid(player):
		return false
	_spawn(player, camera)
	return true
