extends CharacterBody3D

## "Ma Dưới Sàn" / The Crawler.
##
## Designed as the exact inverse of the statue ghost, so the two can share a
## house without competing for the same fear:
##
##   statue: hunts by sight, freezes the moment you look at it, floor only,
##           teleports in for a scripted ambush, killed you while you blinked.
##   crawler: blind. Hunts by SOUND. Does not care that you can see it. Owns
##           the walls and the ceiling, so it ignores the floor plan entirely.
##
## The counterplay is therefore also inverted. Against the statue you keep your
## eyes on it; against this you go quiet - crouch, stop, and let it crawl over
## the ceiling above your head and away toward the last thing it heard.
##
## It runs on a fixed, announced hunt cycle rather than being a permanent
## threat, which is what keeps it survivable:
##
##   HIDDEN    it is not in the house at all. Nothing can hurt you.
##   OMEN      it appears and bolts across one player's view, far too fast to
##             catch and unable to kill during the dash. This is a warning, and
##             it is the only warning: a hunt has started.
##   PATROL    it sweeps a fixed route around the whole house, `patrol_laps`
##             times. This is the dangerous phase, but it is looking, not
##             tracking - a silent player is passed over.
##   HUNTING   a noise broke the patrol. It commits to that noise.
##   RETREAT   it finished its laps without finding anyone: one scream, then it
##             is gone until the next cycle.
##
## The attic is its lair. Every cycle starts and ends there.

enum CrawlerState {
	DORMANT,
	HIDDEN,
	OMEN,
	PATROL,
	HUNTING,
	SEARCHING,
	POUNCE_WINDUP,
	POUNCING,
	RECOVERING,
	RETREATING,
}

signal state_changed(new_state: CrawlerState)
signal noise_heard(position: Vector3, loudness: float)
signal surface_changed(new_normal: Vector3)
signal omen_started(player: Node3D, from: Vector3, to: Vector3)
signal patrol_lap_completed(lap: int)
signal pounce_started(target_point: Vector3)
signal pounce_missed()
signal killed_player(player: Node3D)
signal retreated()

@export_category('Behavior')
@export var active: bool = true
## Patrol crawl. Deliberately crippling - less than half a walking player. It is
## not chasing anyone at this speed; it is dragging itself across the ceiling
## waiting to hear something, and it can be walked away from at leisure.
@export var crawl_speed: float = 1.15
## Closing speed once it has a fix but the noise is too far away to leap at. It
## is faster than a patrol and slower than a sprint, so distance still buys time.
@export var hunting_speed: float = 3.6
@export var acceleration: float = 26.0
@export var turn_speed: float = 7.5

@export_category('Hunt Cycle')
## Whether it runs the hidden/omen/patrol/retreat cycle at all. Off leaves a
## bare noise-hunter, which is the control the isolated smoke tests use.
@export var hunt_cycle_enabled: bool = true
@export var start_hidden: bool = true
@export var initial_hidden_delay_min: float = 20.0
@export var initial_hidden_delay_max: float = 40.0
## The quiet between hunts. This is most of the nerf: for minutes at a time the
## house simply does not contain it.
@export var hidden_delay_min: float = 55.0
@export var hidden_delay_max: float = 100.0
## Noise while it is hiding cannot summon it directly - the omen always plays
## first - but it does bring the next cycle forward by this fraction of the
## remaining wait, so a loud house is still a more dangerous house.
@export_range(0.0, 1.0) var noise_impatience: float = 0.35

@export_category('Omen')
## The announced fly-past that precedes every hunt. It cannot kill during this,
## and it makes no attempt to reach anyone.
@export var omen_enabled: bool = true
@export var omen_speed: float = 13.5
## How far in front of the chosen player it crosses. Far enough to read as a
## shape rather than a jumpscare, close enough that you cannot miss it.
@export var omen_distance_min: float = 5.5
@export var omen_distance_max: float = 9.0
## Half-width of the crossing, measured out from the player's sightline. The
## dash runs the full width, so it enters and leaves frame.
@export var omen_crossing_half_width: float = 4.5
@export var omen_max_duration: float = 2.2
@export_range(4, 32, 1) var omen_candidate_count: int = 14
## If no player can be given a clean fly-past, it screams from above the ceiling
## instead. The hunt is never unannounced.
@export var omen_audio_fallback: bool = true

@export_category('Adhesion')
## Whether it may leave the floor at all. Turning this off leaves a plain
## floor-bound crawler, which is what the isolated smoke tests use as a control.
@export var wall_crawling_enabled: bool = true
## Acceleration pulling the body into whatever surface it is currently gripping.
## This replaces gravity while clung, so it must comfortably exceed it or the
## crawler sags off ceilings.
@export var cling_force: float = 30.0
## Cap on the speed it may build up straight into the surface. Without this the
## adhesion accelerates forever and the body vibrates against the geometry.
@export var max_cling_speed: float = 2.2
## How far below the body a surface may be and still be grippable. Sphere radius
## is 0.34, so this allows a little clearance over uneven trim without letting
## it hover.
@export var cling_probe_distance: float = 0.55
## Reach used when feeling around a convex edge - the table lip, the top of a
## wall - for the face on the other side.
@export var edge_reach: float = 0.6
## How fast the body re-aligns to a newly gripped surface. Low values look like
## it is pouring around the corner; high values snap and read as a bug.
@export var surface_align_speed: float = 9.0
## A wall must be at least this far from the current surface plane before it
## counts as a new surface to climb rather than something to slide along.
@export_range(0.0, 1.0) var surface_change_threshold: float = 0.25
## Grace period after losing grip before it accepts that it is falling. Stops a
## single frame of bad geometry from dropping it off the ceiling.
@export var cling_lost_time: float = 0.18
## Minimum time between re-anchors. In a concave corner two or three faces are
## all in contact and all "more different" than the current one, so without this
## it swaps surface every frame and vibrates in place instead of turning.
@export var regrip_cooldown: float = 0.35
## How long it may be wedged before it simply lets go and drops. Nothing steers
## out of a ceiling corner reliably, but falling out of one always works, and a
## crawler losing its grip is in character.
@export var stuck_release_time: float = 1.4
@export_flags_3d_physics var surface_mask: int = 1

@export_category('Hearing')
## Distance a full-speed sprint carries to. Everything quieter scales down from
## here, so crouch-walking is audible only from a few metres. Roughly one floor
## of the house rather than the whole building: it has to physically patrol into
## your half of the map before your footsteps matter.
@export var hearing_range: float = 16.0
## Player speed treated as maximum loudness. Slightly above the player's sprint
## speed so even sprinting is not quite a 1.0 - there is always a louder noise.
@export var loud_reference_speed: float = 3.1
@export_range(0.0, 1.0) var crouch_noise_multiplier: float = 0.3
## A landing thump is a single loud event no amount of crouching hides.
@export_range(0.0, 1.0) var landing_noise: float = 0.85
## Sound still reaches it through a wall, just muffled - which is why closing a
## door behind you helps but does not save you.
@export_range(0.0, 1.0) var wall_muffle: float = 0.55
## How fast its fix on the last noise rots. This is the whole stealth window:
## go silent and it keeps crawling to where you *were*.
@export var trail_decay: float = 0.12
## Below this confidence it stops committing to the trail and starts sweeping.
@export_range(0.0, 1.0) var search_confidence: float = 0.2
## It notices a body it physically crawls into, silent or not - but only while
## it is actually hunting. On patrol it can pass right over you.
@export var touch_detection_range: float = 0.8
## Loudness required to break off a patrol and commit to a hunt. A crouch-walk
## sits under this, so sneaking does not turn a sweep into a chase.
@export_range(0.0, 1.0) var patrol_alert_loudness: float = 0.35

@export_category('Patrol')
## Nodes in this group are the route, visited in tree order. With none present
## it falls back to sampling the navmesh around its lair.
@export var patrol_point_group: StringName = 'crawler_patrol_points'
## Nodes in this group mark where it lives and where every cycle begins. The
## attic, in this house. Falls back to wherever it was placed in the scene.
@export var lair_group: StringName = 'crawler_lair'
## Complete laps of the route before it gives up and goes home.
@export_range(1, 6, 1) var patrol_laps: int = 2
## A patrol point counts as visited from this far away; it is sweeping rooms,
## not touching markers.
@export var patrol_arrive_distance: float = 2.0
## Give up on a patrol point that will not resolve, so one unreachable marker
## cannot strand the whole cycle.
@export var patrol_point_timeout: float = 14.0
@export var patrol_chitter_interval_min: float = 5.0
@export var patrol_chitter_interval_max: float = 12.0
## While patrolling it steers this far above its route marker, which drives it
## up the nearest wall and onto the ceiling. It hunts from up there, which is
## why looking up is the counterplay to the omen. Applied only on genuinely flat
## floor - see `flat_floor_threshold`.
@export var patrol_climb_bias: float = 2.4
## How level a surface has to be before navigation is used to route across it.
##
## This must stay well below cos(45 degrees) = 0.707, because the house's
## authored stair ramps are exactly 45 degrees. At a 0.7 threshold the crawler
## flickered between "on ground, use the navmesh" and "on a wall, go straight
## and climb" on every single frame of every staircase, which is precisely why
## it could walk up a flight and then never get back down one.
@export_range(0.0, 1.0) var ground_surface_threshold: float = 0.45
## Separate, much stricter test for "standing on a level floor", used to decide
## whether to reach for the ceiling. A staircase is walkable ground but is not
## somewhere to start climbing from.
@export_range(0.0, 1.0) var flat_floor_threshold: float = 0.9
## Height difference under which a route marker counts as being on the crawler's
## own level. Floors here are 3 m apart, so this cleanly separates "same room"
## from "another storey".
@export var same_level_height: float = 1.5
## Consecutive failed attempts to shake itself loose before it gives up and
## relocates. Only ever used while no player can see it.
@export_range(1, 10, 1) var unstick_relocate_after: int = 3

@export_category('Retreat')
## The scream that ends a failed hunt. It vanishes when this finishes.
@export var retreat_scream_duration: float = 1.6

@export_category('Search')
@export var arrive_distance: float = 1.2
## Shorter than a patrol leg on purpose: losing the trail should drop it back
## to sweeping rather than leave it circling one room.
@export var search_duration: float = 7.0
@export var search_radius: float = 5.0
@export var search_point_interval: float = 2.2

@export_category('Pounce')
## The entire attack. It creeps at `crawl_speed` and then covers this whole
## distance in one launch, so range is what you manage, not speed: make a sound
## anywhere inside this and it is already on you.
@export var pounce_range: float = 13.0
@export var pounce_min_range: float = 1.4
## Short, because the leap is the threat and a long tell would defuse it - but
## not zero: this plus the scream is the only frame in which it can be dodged.
@export var pounce_windup: float = 0.3
@export var pounce_speed: float = 21.0
@export var pounce_arc: float = 0.22
## How far ahead of a moving target it aims. It is blind, so this is guesswork
## and it can be dodged by changing direction during the windup.
@export var pounce_lead_time: float = 0.22
@export var pounce_kill_radius: float = 1.05
@export var pounce_max_air_time: float = 1.4
## The window a missed pounce hands back to the player. Without this it is
## simply unsurvivable in a corridor, and it is long enough here to actually
## clear a room and put a door between you.
@export var pounce_recovery: float = 1.9
@export var pounce_cooldown: float = 3.6
@export_range(0.0, 1.0) var pounce_min_confidence: float = 0.25
## How near its noise fix a player has to be before it is willing to leap at
## them. It is blind: it lunges at a sound, not at a body, so a player who is
## simply nearby while something else made the noise is not a target.
@export var pounce_fix_tolerance: float = 2.5

@export_category('Presentation')
@export var crawl_animation_speed: float = 9.0
## Distance at which the flesh flushes and the breathing becomes audible.
@export var dread_radius: float = 9.0
@export var crawl_audio_min_speed: float = 0.35

var state: CrawlerState = CrawlerState.PATROL
var surface_normal: Vector3 = Vector3.UP
var has_surface: bool = false
var airborne_time: float = 0.0
var facing_direction: Vector3 = Vector3.FORWARD

var last_noise_position: Vector3
var noise_confidence: float = 0.0
var noise_source: CharacterBody3D
var has_noise_fix: bool = false

var search_timer: float = 0.0
var search_point_timer: float = 0.0
var search_point: Vector3
var hidden_timer: float = 0.0
var omen_timer: float = 0.0
var omen_target_point: Vector3
var patrol_index: int = 0
var patrol_lap: int = 0
var patrol_point_timer: float = 0.0
var patrol_chitter_timer: float = 0.0
var retreat_timer: float = 0.0
var manifested: bool = true
var lair_position: Vector3
var patrol_points: Array[Vector3] = []
var normal_collision_layer: int
var normal_collision_mask: int
var pounce_timer: float = 0.0
var pounce_cooldown_timer: float = 0.0
var pounce_air_time: float = 0.0
var recovery_timer: float = 0.0
var stuck_timer: float = 0.0
var regrip_cooldown_timer: float = 0.0
var steering_goal: Vector3
var best_goal_distance: float = INF
var no_progress_time: float = 0.0
var failed_releases: int = 0
var last_position: Vector3

var crawl_phase: float = 0.0
var agitation: float = 0.0
var breath: float = 0.0
var jaw_open: float = 0.0
var presentation_time: float = 0.0
var flesh_material: ShaderMaterial

var gravity: float = ProjectSettings.get_setting('physics/3d/default_gravity')
## Bodies the surface probes must ignore: itself, plus every player. Players
## share the world collision layer, so without this the crawler will happily
## decide a player standing beside it is a wall and try to climb them.
var _cling_exclusions: Array[RID] = []
## Per-player airborne memory, keyed by instance id, used to turn a landing into
## a single loud thump instead of a continuous noise while falling.
var _player_airborne: Dictionary = {}

@onready var visual_root: Node3D = $VisualRoot
@onready var body_pivot: Node3D = $VisualRoot/BodyPivot
@onready var neck_pivot: Node3D = $VisualRoot/BodyPivot/NeckPivot
@onready var head_pivot: Node3D = $VisualRoot/BodyPivot/NeckPivot/HeadPivot
@onready var jaw_pivot: Node3D = $VisualRoot/BodyPivot/NeckPivot/HeadPivot/JawPivot
@onready var tail_pivot: Node3D = $VisualRoot/BodyPivot/TailPivot
@onready var tail_tip_pivot: Node3D = $VisualRoot/BodyPivot/TailPivot/TailTipPivot
@onready var skull: MeshInstance3D = $VisualRoot/BodyPivot/NeckPivot/HeadPivot/Skull
@onready var drip: GPUParticles3D = $VisualRoot/Drip
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var crawl_audio: AudioStreamPlayer3D = $CrawlAudio
@onready var chitter_audio: AudioStreamPlayer3D = $ChitterAudio
@onready var breath_audio: AudioStreamPlayer3D = $BreathAudio
@onready var scream_audio: AudioStreamPlayer3D = $ScreamAudio
@onready var bone_audio: AudioStreamPlayer3D = $BoneAudio

## Limb chains, in the order they are driven: the two diagonal pairs are
## (front-left, back-right) and (front-right, back-left).
@onready var limb_roots: Array[Node3D] = [
	$VisualRoot/BodyPivot/Limbs/FrontLeft,
	$VisualRoot/BodyPivot/Limbs/BackRight,
	$VisualRoot/BodyPivot/Limbs/FrontRight,
	$VisualRoot/BodyPivot/Limbs/BackLeft,
]
var limb_lowers: Array[Node3D] = []
var limb_hands: Array[Node3D] = []

# Rest pose of one limb, in degrees, authored here rather than in the scene so
# the animation code is the single source of truth for the silhouette.
#
# The whole read of this creature comes from two deliberate anatomical errors:
#   1. the upper limb is rotated past horizontal, so the elbow/knee rides ABOVE
#      the spine instead of below it, and
#   2. the second joint folds the wrong way, so the forearm comes back down to
#      the surface from the outside like a spider's leg, not a human's.
#
# Limb segments hang down local -Y, and a rotation of t about local +Z sends
# that to (sin t, -cos t, 0). So the left limb (side -1) opens to -118 degrees:
# out to its own side and 28 degrees ABOVE horizontal, which is the raised
# elbow. The forearm then adds +91, landing at a net -27 degrees - back down
# onto the surface from outside the shoulder. Both numbers mirror through
# `side`, and `lift` always increases the fold so the hand peels off the
# surface on the recovery half of the stride.
const LIMB_UPPER_SPLAY := 118.0
const LIMB_UPPER_PITCH := 22.0
const LIMB_LOWER_FOLD := -91.0
const LIMB_HAND_FLAT := 46.0
const LIMB_SIDE_SIGNS: Array[float] = [-1.0, 1.0, 1.0, -1.0]
const LIMB_FRONT_SIGNS: Array[float] = [1.0, -1.0, 1.0, -1.0]


func _ready() -> void:
	add_to_group('crawler_ghosts')
	normal_collision_layer = collision_layer
	normal_collision_mask = collision_mask
	last_position = global_position
	last_noise_position = global_position
	search_point = global_position
	lair_position = global_position
	surface_normal = Vector3.UP
	facing_direction = -global_basis.z
	patrol_chitter_timer = randf_range(patrol_chitter_interval_min, patrol_chitter_interval_max)
	for limb: Node3D in limb_roots:
		var lower := limb.get_node('LowerPivot') as Node3D
		limb_lowers.append(lower)
		limb_hands.append(lower.get_node('HandPivot') as Node3D)
	_prepare_materials()
	_apply_rest_pose()
	# Route markers are ordinary scene nodes, so they only exist once the rest of
	# the level has entered the tree.
	_resolve_route.call_deferred()

	if not active:
		_set_state(CrawlerState.DORMANT)
	elif hunt_cycle_enabled and start_hidden:
		_enter_hidden(randf_range(initial_hidden_delay_min, initial_hidden_delay_max))
	else:
		_begin_patrol()


## Reads the lair and the patrol route out of the scene. Keeping these in groups
## rather than as coordinates in this script means the route belongs to the
## level, and the creature works unchanged in a test box with neither.
func _resolve_route() -> void:
	if not is_inside_tree():
		return
	patrol_points.clear()
	for node: Node in get_tree().get_nodes_in_group(patrol_point_group):
		var marker := node as Node3D
		if marker:
			patrol_points.append(marker.global_position)

	for node: Node in get_tree().get_nodes_in_group(lair_group):
		var marker := node as Node3D
		if marker:
			lair_position = marker.global_position
			break


func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		return

	if state == CrawlerState.HIDDEN:
		velocity = Vector3.ZERO
		_update_hidden(delta)
		_update_player_threat()
		return

	regrip_cooldown_timer = maxf(regrip_cooldown_timer - delta, 0.0)
	_refresh_cling_exclusions()
	_listen(delta)
	_update_surface(delta)

	match state:
		CrawlerState.OMEN:
			_update_omen(delta)
		CrawlerState.PATROL:
			_update_patrol(delta)
		CrawlerState.HUNTING:
			_update_hunting(delta)
		CrawlerState.SEARCHING:
			_update_searching(delta)
		CrawlerState.POUNCE_WINDUP:
			_update_pounce_windup(delta)
		CrawlerState.POUNCING:
			_update_pouncing(delta)
		CrawlerState.RECOVERING:
			_update_recovering(delta)
		CrawlerState.RETREATING:
			_update_retreating(delta)
		CrawlerState.DORMANT:
			velocity = Vector3.ZERO

	_apply_adhesion(delta)
	move_and_slide()
	_resolve_wall_transition()
	_update_stuck_state(delta)
	_update_orientation(delta)
	_update_player_threat()
	_update_presentation(delta)


# --- Hearing ------------------------------------------------------------------


## Public noise channel. Anything in the world that makes a sound can call this
## (doors do), and so can a test that needs a deterministic stimulus instead of
## having to physically walk a player around.
func report_noise(position: Vector3, loudness: float, source: Node = null) -> void:
	if not active or state == CrawlerState.DORMANT:
		return
	var clamped := clampf(loudness, 0.0, 1.0)
	if clamped <= 0.0:
		return

	# While it is hidden it cannot be called: a noise only makes it impatient,
	# and the omen still has to play before anything can hurt anyone. Skipping
	# straight to a hunt here is exactly the un-announced ambush this cycle
	# exists to remove.
	if state == CrawlerState.HIDDEN:
		hidden_timer -= hidden_timer * noise_impatience * clamped
		return
	# During the fly-past it is deaf. It is a scripted crossing, and letting a
	# noise redirect it mid-dash turns the warning back into an attack.
	if state == CrawlerState.OMEN or state == CrawlerState.RETREATING:
		return

	var distance := global_position.distance_to(position)
	var reach := clamped * hearing_range
	if _is_occluded(position, source):
		reach *= wall_muffle
	if distance > reach or reach <= 0.001:
		return

	# Nearer and louder wins. A quiet noise right beside it still beats a distant
	# sprint, which is what lets a player draw it away with a thrown-sounding
	# event on the far side of a room.
	var confidence := clampf(1.0 - distance / reach, 0.0, 1.0) * clamped
	if confidence < noise_confidence and has_noise_fix:
		return

	last_noise_position = position
	noise_confidence = confidence
	has_noise_fix = true
	noise_source = source as CharacterBody3D
	noise_heard.emit(position, clamped)

	if state == CrawlerState.PATROL and clamped >= patrol_alert_loudness:
		# Only a real noise breaks the sweep. A crouch-walk registers as a fix -
		# so it will drift your way - without turning the patrol into a chase.
		_set_state(CrawlerState.HUNTING)
	elif state == CrawlerState.SEARCHING and distance > arrive_distance:
		# Only a noise it has somewhere to go to pulls it back out of a sweep.
		# Without the distance test, a player making noise right where it is
		# already standing flips it between hunting and searching every frame.
		_set_state(CrawlerState.HUNTING)


func _refresh_cling_exclusions() -> void:
	_cling_exclusions.clear()
	_cling_exclusions.append(get_rid())
	for node: Node in get_tree().get_nodes_in_group('players'):
		var body := node as CollisionObject3D
		if body:
			_cling_exclusions.append(body.get_rid())


func _listen(delta: float) -> void:
	noise_confidence = maxf(noise_confidence - trail_decay * delta, 0.0)
	if noise_confidence <= 0.0:
		has_noise_fix = false

	for player: CharacterBody3D in _living_players():
		var loudness := _player_loudness(player)
		if loudness > 0.0:
			report_noise(player.global_position, loudness, player)

		# Contact overrides silence entirely: it has just put a hand on you.
		# Patrol is excluded - a slow sweep passing over a player who is holding
		# still is the payoff for holding still, and it must not be a death.
		if state != CrawlerState.PATROL \
			and global_position.distance_to(player.global_position) <= touch_detection_range:
			last_noise_position = player.global_position
			noise_confidence = 1.0
			has_noise_fix = true
			noise_source = player
			if state == CrawlerState.SEARCHING:
				_set_state(CrawlerState.HUNTING)


## Converts what a player is physically doing into a 0..1 loudness. Standing
## still is genuinely zero - that is the entire stealth mechanic, so it must not
## be fudged with a floor value.
func _player_loudness(player: CharacterBody3D) -> float:
	var key := player.get_instance_id()
	var on_floor := player.is_on_floor()
	var was_airborne: bool = _player_airborne.get(key, false)
	_player_airborne[key] = not on_floor

	if on_floor and was_airborne:
		return landing_noise

	if not on_floor:
		return 0.0

	var real_velocity := player.get_real_velocity()
	var horizontal_speed := Vector2(real_velocity.x, real_velocity.z).length()
	var loudness := clampf(horizontal_speed / maxf(loud_reference_speed, 0.01), 0.0, 1.0)
	if 'is_crouching' in player and player.is_crouching:
		loudness *= crouch_noise_multiplier
	# Footfalls, not a siren: below a slow creep there is nothing to hear.
	return loudness if loudness > 0.06 else 0.0


## Is there architecture between the crawler and a point? `subject` must be
## excluded whenever the point is a body's own position, or its own collider is
## the first thing the ray finds and it reports itself as behind a wall - which
## silently makes both the pounce and the hearing muffle permanent.
func _is_occluded(point: Vector3, subject: Node = null) -> bool:
	var excluded: Array[RID] = [get_rid()]
	var subject_body := subject as CollisionObject3D
	if subject_body:
		excluded.append(subject_body.get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		point,
		surface_mask,
		excluded
	)
	query.hit_from_inside = true
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Surface adhesion ---------------------------------------------------------


## Finds the surface the body should be gripping this frame and eases the local
## "up" onto it. Three probes, in priority order:
##
##   1. straight under the belly     - stay on the plane we are already on
##   2. ahead, along the same plane  - the plane continues past the lip
##   3. around a convex edge         - the plane has ended; feel for the face on
##                                     the far side of the corner and pour onto it
##
## Concave corners (crawling into a wall, or into the wall/ceiling join) are not
## probed for here at all - move_and_slide reports those as real collisions, and
## _resolve_wall_transition re-anchors from the collision normal, which is both
## cheaper and more reliable than guessing with a ray.
func _update_surface(delta: float) -> void:
	if state == CrawlerState.POUNCING:
		has_surface = false
		# Mid-leap it is a normal falling body, so its local up has to unwind
		# back to world up - otherwise a leap launched off a ceiling keeps
		# probing upward and mistakes the ceiling it just left for a landing.
		surface_normal = surface_normal.normalized().slerp(
			Vector3.UP,
			minf(surface_align_speed * delta, 1.0)
		).normalized()
		return

	var forward := facing_direction
	if velocity.length_squared() > 0.04:
		var tangent := velocity - surface_normal * velocity.dot(surface_normal)
		if tangent.length_squared() > 0.01:
			forward = tangent.normalized()

	var found_normal := _probe_cling_normal(forward)
	if found_normal == Vector3.ZERO:
		airborne_time += delta
		if airborne_time >= cling_lost_time:
			has_surface = false
			# Falling with a stale ceiling normal aims every probe at the sky,
			# so it can never find the floor it is about to land on. Rolling the
			# local up back toward world up while airborne is what lets a
			# dropped or missed-pounce crawler re-grip on impact.
			surface_normal = surface_normal.normalized().slerp(
				Vector3.UP,
				minf(surface_align_speed * 0.5 * delta, 1.0)
			).normalized()
		return

	airborne_time = 0.0
	if not has_surface:
		has_surface = true
	_align_surface(found_normal, delta)


func _probe_cling_normal(forward: Vector3) -> Vector3:
	# The fly-past is a flat sprint across a doorway at 13 m/s. Left to grip
	# whatever it brushes at that speed it ends the dash hanging off a ceiling,
	# and the patrol then starts from up there instead of from the floor.
	if not wall_crawling_enabled or state == CrawlerState.OMEN:
		# Floor-only control mode: only ever accept ground under the belly.
		var ground := _cast_surface(global_position, Vector3.DOWN, cling_probe_distance)
		return ground if ground.dot(Vector3.UP) > 0.5 else Vector3.ZERO

	var under_belly := _cast_surface(global_position, -surface_normal, cling_probe_distance)
	if under_belly != Vector3.ZERO:
		return under_belly

	var ahead := global_position + forward * edge_reach
	var ahead_hit := _cast_surface(ahead, -surface_normal, cling_probe_distance + edge_reach)
	if ahead_hit != Vector3.ZERO:
		return ahead_hit

	# Convex wrap: stand off past the edge and below the old plane, then feel
	# backwards for the face we just crawled over the top of.
	var wrap_origin := ahead - surface_normal * edge_reach
	var wrap_hit := _cast_surface(wrap_origin, -forward, edge_reach * 1.8)
	if wrap_hit != Vector3.ZERO:
		return wrap_hit

	# Last resort, and the one that catches a landing: real ground, straight
	# down in world space, regardless of what plane it thinks it is on.
	var ground := _cast_surface(global_position, Vector3.DOWN, cling_probe_distance)
	if ground != Vector3.ZERO and ground.dot(Vector3.UP) > 0.5:
		return ground

	return Vector3.ZERO


func _cast_surface(origin: Vector3, direction: Vector3, distance: float) -> Vector3:
	if direction.is_zero_approx() or distance <= 0.0:
		return Vector3.ZERO
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction.normalized() * distance,
		surface_mask,
		_cling_exclusions
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	var normal: Vector3 = hit['normal']
	return normal.normalized() if not normal.is_zero_approx() else Vector3.ZERO


func _align_surface(new_normal: Vector3, delta: float) -> void:
	# Both sides are re-normalized here rather than trusted. Vector3.slerp builds
	# an axis-angle rotation and hard-errors on a non-unit input, and normals
	# coming off the house's generated trimesh colliders are routinely a
	# thousandth short of unit length.
	var target := new_normal.normalized()
	if target.is_zero_approx():
		return
	var current := surface_normal.normalized()
	if target.distance_to(current) > surface_change_threshold:
		# Every re-grip pops the joints. This is the sound that tells a player
		# in the next room that it has just left the floor for the wall.
		_play_bone_snap()
		surface_changed.emit(target)
	surface_normal = current.slerp(target, minf(surface_align_speed * delta, 1.0)).normalized()


func _apply_adhesion(delta: float) -> void:
	if has_surface and state != CrawlerState.POUNCING:
		up_direction = surface_normal
		var inward_speed := velocity.dot(-surface_normal)
		if inward_speed < max_cling_speed:
			velocity += -surface_normal * cling_force * delta
			inward_speed = velocity.dot(-surface_normal)
		if inward_speed > max_cling_speed:
			velocity += surface_normal * (inward_speed - max_cling_speed)
		return

	up_direction = Vector3.UP
	velocity.y -= gravity * delta


## Re-anchors onto a wall the body has just run into. Only a surface meaningfully
## tilted away from the current one counts - otherwise it would re-anchor to
## every scrap of trim it brushes and jitter along a flat floor.
func _resolve_wall_transition() -> void:
	if not wall_crawling_enabled \
		or state == CrawlerState.POUNCING \
		or state == CrawlerState.OMEN:
		return
	if regrip_cooldown_timer > 0.0 and has_surface:
		return

	# While airborne any contact is worth gripping, so the threshold drops to
	# zero - that is how a fall or a spent leap re-attaches on impact.
	var best_normal := Vector3.ZERO
	var best_difference := surface_change_threshold if has_surface else -1.0
	for index: int in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var normal := collision.get_normal()
		var difference := normal.distance_to(surface_normal)
		if difference > best_difference:
			best_difference = difference
			best_normal = normal

	if best_normal == Vector3.ZERO:
		return
	# Never re-anchor to a surface we would immediately fall off: the new normal
	# has to actually support the body from the side it hit.
	if best_normal.dot(velocity.normalized()) > 0.35:
		return

	has_surface = true
	airborne_time = 0.0
	regrip_cooldown_timer = regrip_cooldown
	_play_bone_snap()
	surface_changed.emit(best_normal)
	surface_normal = best_normal.normalized()


func _update_orientation(delta: float) -> void:
	var tangent := velocity - surface_normal * velocity.dot(surface_normal)
	if tangent.length_squared() > 0.02:
		facing_direction = tangent.normalized()

	# Normalized rather than trusted: Basis.slerp requires an orthonormal basis
	# and a column that is a thousandth off unit length is enough to trip it.
	var up := surface_normal.normalized()
	var forward := facing_direction - up * facing_direction.dot(up)
	if forward.length_squared() < 0.0001:
		forward = -global_basis.z - up * (-global_basis.z).dot(up)
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()

	var back := -forward
	var right := up.cross(back)
	if right.length_squared() < 0.0001:
		return
	var target_basis := Basis(right.normalized(), up, back).orthonormalized()
	global_basis = global_basis.slerp(target_basis, minf(turn_speed * delta, 1.0)).orthonormalized()


# --- States -------------------------------------------------------------------


func _set_state(new_state: CrawlerState) -> void:
	if state == new_state:
		return
	state = new_state
	match new_state:
		CrawlerState.SEARCHING:
			search_timer = search_duration
			search_point_timer = 0.0
		CrawlerState.RECOVERING:
			recovery_timer = pounce_recovery
	state_changed.emit(new_state)


# --- Hunt cycle ---------------------------------------------------------------


## Out of play entirely: no body, no collision, nothing to be killed by. This is
## where it spends most of the game.
func _enter_hidden(delay: float) -> void:
	hidden_timer = maxf(delay, 0.0)
	velocity = Vector3.ZERO
	has_noise_fix = false
	noise_confidence = 0.0
	noise_source = null
	pounce_cooldown_timer = 0.0
	global_position = lair_position
	last_position = lair_position
	surface_normal = Vector3.UP
	has_surface = false
	_set_manifested(false)
	_set_state(CrawlerState.HIDDEN)


func _set_manifested(is_manifested: bool) -> void:
	manifested = is_manifested
	visual_root.visible = is_manifested
	drip.emitting = is_manifested
	collision_layer = normal_collision_layer if is_manifested else 0
	collision_mask = normal_collision_mask if is_manifested else 0
	if not is_manifested:
		crawl_audio.stop()
		breath_audio.stop()


func _update_hidden(delta: float) -> void:
	hidden_timer -= delta
	if hidden_timer > 0.0:
		return
	if _living_players().is_empty():
		hidden_timer = 2.0
		return
	_begin_omen()


## The fly-past. It materialises to one side of a player's view, bolts across
## it far too fast to react to, and is gone - then the real hunt starts. This is
## the single most important thing the creature does, because it converts an
## ambush into an announced threat the player can prepare for.
func _begin_omen() -> void:
	if not omen_enabled:
		_begin_patrol()
		return

	var crossing := _find_omen_crossing()
	if crossing.is_empty():
		# Nobody could be shown a clean pass. Announce it anyway - an unheralded
		# hunt is exactly what this cycle exists to prevent.
		if omen_audio_fallback:
			global_position = _overhead_announce_position()
			scream_audio.play()
		_begin_patrol()
		return

	global_position = crossing['from']
	omen_target_point = crossing['to']
	last_position = global_position
	surface_normal = Vector3.UP
	has_surface = false
	omen_timer = omen_max_duration
	velocity = (omen_target_point - global_position).normalized() * omen_speed
	facing_direction = velocity.normalized()
	_set_manifested(true)
	chitter_audio.play()
	_set_state(CrawlerState.OMEN)
	omen_started.emit(crossing['player'], crossing['from'], crossing['to'])


func _update_omen(delta: float) -> void:
	omen_timer -= delta
	var to_target := omen_target_point - global_position
	to_target.y = 0.0
	if omen_timer <= 0.0 or to_target.length() <= 0.6:
		_begin_patrol()
		return

	# Straight, flat and flat out. No steering, no navigation, no attacking:
	# for these two seconds it is a shape crossing a doorway, nothing more.
	var direction := to_target.normalized()
	var vertical := velocity.y
	velocity = direction * omen_speed
	velocity.y = vertical
	facing_direction = direction


## Picks a player and a line across their view to bolt along. Both ends are
## snapped to real standable ground so it does not sprint through a wall, and
## the near end is pushed outside the view cone so it enters frame rather than
## popping into existence in the middle of it.
func _find_omen_crossing() -> Dictionary:
	var players := _living_players()
	if players.is_empty():
		return {}
	var player: CharacterBody3D = players[randi() % players.size()]
	var camera := player.get_node_or_null('CameraPivot/Camera3D') as Camera3D
	var forward := -player.global_basis.z
	if camera:
		forward = -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return {}
	forward = forward.normalized()
	var sideways := Vector3.UP.cross(forward).normalized()

	for attempt: int in omen_candidate_count:
		var distance := randf_range(omen_distance_min, omen_distance_max)
		var side := 1.0 if attempt % 2 == 0 else -1.0
		var centre := player.global_position + forward * distance
		var from := _standable_point(centre + sideways * omen_crossing_half_width * side)
		var to := _standable_point(centre - sideways * omen_crossing_half_width * side)
		if from == Vector3.INF or to == Vector3.INF:
			continue
		if from.distance_to(to) < omen_crossing_half_width:
			continue
		# Both ends on the player's own floor, or it crosses a room they cannot
		# see into.
		if absf(from.y - to.y) > 0.8 or absf(from.y - player.global_position.y) > 2.0:
			continue
		return {'player': player, 'from': from, 'to': to}
	return {}


## Nearest point the creature could actually sit on, using the navmesh when the
## level has one and a downward probe when it does not.
func _standable_point(near: Vector3) -> Vector3:
	if _has_navigation():
		var map_rid := nav_agent.get_navigation_map()
		var nav_point := NavigationServer3D.map_get_closest_point(map_rid, near)
		if nav_point.distance_to(near) > 3.0:
			return Vector3.INF
		return nav_point + Vector3.UP * 0.35

	var query := PhysicsRayQueryParameters3D.create(
		near + Vector3.UP * 1.5,
		near + Vector3.DOWN * 3.0,
		surface_mask,
		_cling_exclusions
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return (hit['position'] as Vector3) + Vector3.UP * 0.35


func _overhead_announce_position() -> Vector3:
	var players := _living_players()
	if players.is_empty():
		return lair_position
	var player: CharacterBody3D = players[randi() % players.size()]
	return player.global_position + Vector3.UP * 3.2


func _begin_patrol() -> void:
	_set_manifested(true)
	patrol_lap = 0
	patrol_index = 0
	patrol_point_timer = patrol_point_timeout
	patrol_chitter_timer = randf_range(patrol_chitter_interval_min, patrol_chitter_interval_max)
	_set_state(CrawlerState.PATROL)


## The slow sweep. It drags itself along the route at a crawl, biased upward so
## it spends the patrol on walls and ceilings, listening. Finding nobody after
## `patrol_laps` sends it home.
func _update_patrol(delta: float) -> void:
	patrol_chitter_timer -= delta
	if patrol_chitter_timer <= 0.0:
		patrol_chitter_timer = randf_range(patrol_chitter_interval_min, patrol_chitter_interval_max)
		if not chitter_audio.playing:
			chitter_audio.play()

	if patrol_points.is_empty():
		# No route authored. Sweep around the lair rather than standing still.
		_set_state(CrawlerState.SEARCHING)
		last_noise_position = lair_position
		return

	var target: Vector3 = patrol_points[patrol_index % patrol_points.size()]
	patrol_point_timer -= delta
	if global_position.distance_to(target) <= patrol_arrive_distance or patrol_point_timer <= 0.0:
		_advance_patrol_point()
		return

	# Aim above the marker so the route pulls it up the walls and onto the
	# ceiling of the room it is crossing. Three conditions, all of them learned
	# the hard way:
	#   - only from level floor, never from a staircase,
	#   - only when the marker is on this level. Adding 2 m of climb to a marker
	#     that is already a storey up aims it at a point inside the building's
	#     structure, and it climbs into the stairwell shaft and wedges there
	#     instead of simply taking the stairs, and
	#   - only as far as the real headroom allows (see _effective_climb_bias).
	# Cross-floor legs are pure navigation, which is what knows about stairs.
	var level := absf(target.y - global_position.y) <= same_level_height
	var on_ground := surface_normal.dot(Vector3.UP) > ground_surface_threshold

	# Changing floors is done on the stairs, like everything else in the house.
	# Navigation is only consulted from walkable ground, so hanging off a ceiling
	# with a target one storey down leaves it steering by straight line into the
	# floor slab - it has to come down first.
	if not level and not on_ground and has_surface:
		_drop_to_floor()
		return

	var flat := surface_normal.dot(Vector3.UP) > flat_floor_threshold
	var climb := _effective_climb_bias() if (level and flat) else 0.0
	_crawl_toward(delta, target, crawl_speed, climb)


## Climb bias, clipped to whatever headroom actually exists. The raw bias aims
## at a point metres overhead; under a low slab that is a point inside solid
## geometry, and steering at it drove the crawler up into the 0.75 m void under
## the second floor and wedged it there, oscillating between the void's floor
## and its ceiling until the route timeout fired. Aiming just below the real
## ceiling gets the same behaviour - up the wall, across the ceiling - in rooms
## that have the room for it, and no behaviour at all in the ones that do not.
func _effective_climb_bias() -> float:
	if patrol_climb_bias <= 0.0:
		return 0.0
	var probe := patrol_climb_bias + 0.5
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.UP * probe,
		surface_mask,
		_cling_exclusions
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return patrol_climb_bias
	var headroom := global_position.distance_to(hit['position'])
	return maxf(headroom - 0.7, 0.0)


func _advance_patrol_point() -> void:
	patrol_index += 1
	patrol_point_timer = patrol_point_timeout
	if patrol_index < patrol_points.size():
		return

	patrol_index = 0
	patrol_lap += 1
	patrol_lap_completed.emit(patrol_lap)
	if hunt_cycle_enabled and patrol_lap >= patrol_laps:
		_begin_retreat()


## Gave up. One scream, loud enough to be heard through the whole house, and
## then it is gone - which is also the all-clear the player needs.
func _begin_retreat() -> void:
	retreat_timer = retreat_scream_duration
	scream_audio.play()
	_set_state(CrawlerState.RETREATING)


func _update_retreating(delta: float) -> void:
	_brake(delta)
	retreat_timer -= delta
	if retreat_timer > 0.0:
		return
	retreated.emit()
	_enter_hidden(randf_range(hidden_delay_min, hidden_delay_max))


func _update_hunting(delta: float) -> void:
	if not has_noise_fix:
		_set_state(CrawlerState.SEARCHING)
		return

	if _maul_contact():
		return

	pounce_cooldown_timer = maxf(pounce_cooldown_timer - delta, 0.0)
	var pounce_target := _pounce_candidate()
	if pounce_target:
		_begin_pounce(pounce_target)
		return

	# Dead band closer. A leap needs `pounce_min_range` of run-up and a maul
	# needs `touch_detection_range` of contact, and the gap between the two used
	# to be a safe pocket: make a noise with the crawler already a metre away and
	# it would arrive at the sound, decide it had arrived, and wander off into a
	# search sweep without ever touching you. Inside the leap's minimum it walks
	# the last stretch in by hand. This still needs a live fix, so it is not a
	# way of finding a player who is standing still.
	var closing_target := _closest_living_player()
	if closing_target \
		and noise_confidence >= pounce_min_confidence \
		and global_position.distance_to(closing_target.global_position) < pounce_min_range:
		_crawl_toward(delta, closing_target.global_position, hunting_speed)
		return

	var to_noise := last_noise_position - global_position
	if to_noise.length() <= arrive_distance:
		_set_state(CrawlerState.SEARCHING)
		_brake(delta)
		return

	if noise_confidence < search_confidence:
		_set_state(CrawlerState.SEARCHING)
		return

	_crawl_toward(delta, last_noise_position, hunting_speed)


## Arrived where the sound was and found nothing. It sweeps the area, pausing on
## whatever surface it is on to listen - which is when a player pinned behind a
## sofa gets to watch it pass overhead.
func _update_searching(delta: float) -> void:
	if _maul_contact():
		return

	pounce_cooldown_timer = maxf(pounce_cooldown_timer - delta, 0.0)
	var pounce_target := _pounce_candidate()
	if pounce_target:
		_begin_pounce(pounce_target)
		return

	search_timer -= delta
	if search_timer <= 0.0:
		# Lost them. Rejoin the sweep where it left off rather than giving up on
		# the whole cycle - the lap counter is what ends a hunt, not one failure.
		if hunt_cycle_enabled or not patrol_points.is_empty():
			_set_state(CrawlerState.PATROL)
		return

	search_point_timer -= delta
	if search_point_timer <= 0.0:
		search_point_timer = search_point_interval
		var angle := randf() * TAU
		var radius := randf_range(search_radius * 0.35, search_radius)
		search_point = last_noise_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
		if not chitter_audio.playing and randf() < 0.4:
			chitter_audio.play()

	if global_position.distance_to(search_point) <= arrive_distance:
		_brake(delta)
		return
	_crawl_toward(delta, search_point, crawl_speed)


func _update_pounce_windup(delta: float) -> void:
	_brake(delta)
	pounce_timer -= delta
	if pounce_timer > 0.0:
		return

	var target := noise_source
	if not is_instance_valid(target):
		_set_state(CrawlerState.RECOVERING)
		return

	# Aim where the target will be, not where it is. It is blind and committed
	# from this moment - breaking your line during the windup is the dodge.
	var aim := target.global_position + target.velocity * pounce_lead_time
	var launch := aim - global_position
	var distance := launch.length()
	if distance < 0.01:
		_set_state(CrawlerState.RECOVERING)
		return

	has_surface = false
	airborne_time = cling_lost_time
	pounce_air_time = 0.0
	velocity = launch.normalized() * pounce_speed
	# Arc over the gap only when the target is not below it. Leaping off a
	# ceiling is a dive, and adding lift there sends it into the plaster instead
	# of onto the player - which is most of what this creature does now that it
	# patrols overhead.
	if aim.y >= global_position.y - 0.5:
		velocity += Vector3.UP * (distance * pounce_arc)
	scream_audio.play()
	_set_state(CrawlerState.POUNCING)
	pounce_started.emit(aim)


func _update_pouncing(delta: float) -> void:
	pounce_air_time += delta

	var victim := _pounce_contact()
	if victim:
		_kill(victim)
		return

	# A short blind window so the launch frame's own contact with the surface it
	# pushed off does not immediately count as landing.
	if pounce_air_time < 0.12:
		return
	# Hit something, or ran out of air. Either way the leap is spent, and
	# _resolve_wall_transition re-grips from the impact on the same frame.
	var struck := get_slide_collision_count() > 0 or is_on_floor() or is_on_wall()
	if struck or pounce_air_time >= pounce_max_air_time:
		pounce_missed.emit()
		pounce_cooldown_timer = pounce_cooldown
		_set_state(CrawlerState.RECOVERING)


## The gap a player has to break away in. It is face down on the ground with its
## limbs folded the wrong way, and it takes a moment to get them back under it.
func _update_recovering(delta: float) -> void:
	_brake(delta)
	recovery_timer -= delta
	if recovery_timer <= 0.0:
		_set_state(CrawlerState.HUNTING if has_noise_fix else CrawlerState.SEARCHING)


func _begin_pounce(target: CharacterBody3D) -> void:
	noise_source = target
	pounce_timer = pounce_windup
	_brake(1.0)
	_set_state(CrawlerState.POUNCE_WINDUP)


## A pounce needs a live fix, not just a body in range: a player who has gone
## completely silent is not pounced on even from two metres away. That is the
## reward for holding still, and it is why this checks confidence rather than
## distance alone.
##
## The candidate also has to line up with the fix. Without that, a blind hunter
## sent after a noise on the far side of a room will instead throw itself at
## whatever silent player happens to be standing near it, over and over, and
## never reach the sound it was chasing.
func _pounce_candidate() -> CharacterBody3D:
	if pounce_cooldown_timer > 0.0 or noise_confidence < pounce_min_confidence:
		return null
	for player: CharacterBody3D in _living_players():
		var distance := global_position.distance_to(player.global_position)
		if distance > pounce_range or distance < pounce_min_range:
			continue
		# Purely positional on purpose. Matching on `noise_source` instead would
		# keep a player targetable long after they went quiet and walked away,
		# which is the one thing going quiet is supposed to buy.
		if player.global_position.distance_to(last_noise_position) > pounce_fix_tolerance:
			continue
		if _is_occluded(player.global_position, player):
			continue
		return player
	return null


## Anything it is physically touching, it kills - no pounce required. A pounce
## has a minimum range, so without this the creature is completely harmless once
## it is close enough to reach out, which is the exact opposite of what a player
## watching it crawl toward them expects. Deliberately not checked while it is
## recovering from a miss: that window has to stay survivable even if the player
## is still lying underneath it.
func _maul_contact() -> bool:
	for player: CharacterBody3D in _living_players():
		if global_position.distance_to(player.global_position) > touch_detection_range:
			continue
		if _is_occluded(player.global_position, player):
			continue
		scream_audio.play()
		_kill(player)
		return true
	return false


func _pounce_contact() -> CharacterBody3D:
	for player: CharacterBody3D in _living_players():
		if global_position.distance_to(player.global_position) > pounce_kill_radius:
			continue
		# Occlusion still matters at contact range: without it a pounce that
		# lands on the floor above kills the player standing underneath it.
		if _is_occluded(player.global_position, player):
			continue
		return player
	return null


func _kill(player: CharacterBody3D) -> void:
	if player.has_method('kill_by_ghost'):
		player.kill_by_ghost(self)
	killed_player.emit(player)
	pounce_cooldown_timer = pounce_cooldown
	_set_state(CrawlerState.RECOVERING)


# --- Locomotion ---------------------------------------------------------------


func _crawl_toward(delta: float, point: Vector3, speed: float, climb_bias: float = 0.0) -> void:
	if point.distance_to(steering_goal) > 0.5:
		steering_goal = point
		best_goal_distance = INF
		no_progress_time = 0.0

	var direction := _steering_direction(point, climb_bias)
	if direction.is_zero_approx():
		_brake(delta)
		return

	var tangent_direction := direction - surface_normal * direction.dot(surface_normal)
	if tangent_direction.length_squared() < 0.0001:
		# Target is straight through the surface we are stuck to. Keep crawling
		# along the current facing so it slides off the edge and finds the way.
		tangent_direction = facing_direction - surface_normal * facing_direction.dot(surface_normal)
		if tangent_direction.length_squared() < 0.0001:
			_brake(delta)
			return
	tangent_direction = tangent_direction.normalized()

	var normal_speed := velocity.dot(surface_normal)
	var tangent_velocity := velocity - surface_normal * normal_speed
	tangent_velocity = tangent_velocity.move_toward(
		tangent_direction * speed,
		acceleration * delta
	)
	velocity = tangent_velocity + surface_normal * normal_speed


## While it is on a floor it routes with the navmesh like anything else. The
## moment it is on a wall or a ceiling it drops navigation entirely and takes the
## straight line, climbing whatever is in the way. That switch is the character:
## the house's floor plan stops applying to it.
##
## Being stuck deliberately does NOT switch it to direct steering. It used to,
## and that produced a deadlock: standing on the ground floor directly above a
## basement route point, the direct vector pointed straight down through the
## floor, it stopped moving, being stopped kept navigation switched off, and it
## ground against the same spot until the route timeout rescued it twenty
## seconds later. Navigation is exactly what knows where the stairs are.
## Genuine wedging is handled by _release_grip instead.
func _steering_direction(point: Vector3, climb_bias: float = 0.0) -> Vector3:
	var direct := point - global_position
	if direct.length_squared() < 0.0001:
		return Vector3.ZERO

	var on_ground := surface_normal.dot(Vector3.UP) > ground_surface_threshold
	if not on_ground or not _has_navigation():
		# The climb bias only applies to the straight line. Feeding a point
		# metres above the floor to the navigation agent makes it snap the
		# destination to whatever navmesh polygon happens to be nearest that
		# empty air, which routes it somewhere else entirely.
		return (direct + Vector3.UP * climb_bias).normalized()

	if nav_agent.target_position.distance_squared_to(point) > 0.04:
		nav_agent.target_position = point
	var next_point := nav_agent.get_next_path_position()
	var to_next := next_point - global_position
	if nav_agent.get_current_navigation_path().size() > 1 and to_next.length_squared() > 0.0001:
		return to_next.normalized()
	return direct.normalized()


func _has_navigation() -> bool:
	var map_rid := nav_agent.get_navigation_map()
	return map_rid.is_valid() \
		and NavigationServer3D.map_get_iteration_id(map_rid) > 0 \
		and not NavigationServer3D.map_get_regions(map_rid).is_empty()


func _brake(delta: float) -> void:
	var normal_speed := velocity.dot(surface_normal)
	var tangent_velocity := velocity - surface_normal * normal_speed
	tangent_velocity = tangent_velocity.move_toward(Vector3.ZERO, acceleration * delta * 2.0)
	velocity = tangent_velocity + surface_normal * normal_speed


## Wedged against something the navmesh thinks is passable. Dropping to direct
## steering for a moment makes it climb the obstruction instead of grinding
## along it, which is both the fix and exactly what this creature should do.
func _update_stuck_state(delta: float) -> void:
	var moved := global_position.distance_to(last_position)
	last_position = global_position

	var should_be_moving := state == CrawlerState.HUNTING \
		or state == CrawlerState.SEARCHING \
		or state == CrawlerState.PATROL
	if not should_be_moving:
		stuck_timer = 0.0
		no_progress_time = 0.0
		best_goal_distance = INF
		return

	if moved < 0.004:
		stuck_timer += delta
		if stuck_timer >= stuck_release_time:
			_release_grip()
			return
	else:
		stuck_timer = maxf(stuck_timer - delta * 2.0, 0.0)

	# Wedged does not always mean motionless. Skating back and forth in a corner
	# passes the movement check above forever while getting no closer to
	# anything, so progress toward the actual goal is what is measured here.
	var goal_distance := global_position.distance_to(steering_goal)
	if goal_distance < best_goal_distance - 0.15:
		best_goal_distance = goal_distance
		no_progress_time = 0.0
		failed_releases = 0
		return

	no_progress_time += delta
	if no_progress_time >= stuck_release_time:
		no_progress_time = 0.0
		best_goal_distance = INF
		_release_grip()


## Lets go on purpose. Used when it has wedged itself somewhere no amount of
## steering resolves - typically the corner where two walls meet a ceiling,
## where every face is in contact and each one looks like a better surface than
## the last. Dropping out of it costs a second and usually works.
func _release_grip() -> void:
	_drop_to_floor()
	failed_releases += 1
	if failed_releases >= unstick_relocate_after:
		_relocate_after_wedging()


## Deliberately lets go and falls. Distinct from _release_grip because it is
## also used as ordinary navigation - dropping off a ceiling to take the stairs
## is not a failure and must not count toward relocating.
func _drop_to_floor() -> void:
	stuck_timer = 0.0
	has_surface = false
	airborne_time = cling_lost_time
	regrip_cooldown_timer = regrip_cooldown
	velocity += -surface_normal * 1.4 + Vector3.DOWN * 1.2
	surface_normal = Vector3.UP
	_play_bone_snap()


## Last resort. A building assembled from modular panels has slots a 0.68 m
## sphere can enter and not steer out of, and no amount of local escape logic
## fixes all of them. Rather than let one of those strand the patrol - the
## symptom being a crawler that walks up a staircase and never comes back down -
## it relocates to its next route marker.
##
## Only ever while unobserved, so a player never sees it blink across a room.
## If it is being watched it just keeps struggling, which is at least honest.
func _relocate_after_wedging() -> void:
	if _is_visible_to_any_player():
		return

	var destination := lair_position
	if not patrol_points.is_empty():
		destination = patrol_points[patrol_index % patrol_points.size()]
	var landing := _standable_point(destination)
	if landing == Vector3.INF:
		landing = destination

	failed_releases = 0
	no_progress_time = 0.0
	best_goal_distance = INF
	stuck_timer = 0.0
	patrol_point_timer = patrol_point_timeout
	global_position = landing
	last_position = landing
	velocity = Vector3.ZERO
	surface_normal = Vector3.UP
	has_surface = false
	airborne_time = 0.0


func _is_visible_to_any_player() -> bool:
	for player: CharacterBody3D in _living_players():
		if 'eyes_closed' in player and player.eyes_closed:
			continue
		var camera := player.get_node_or_null('CameraPivot/Camera3D') as Camera3D
		if not camera:
			continue
		if not camera.is_position_in_frustum(global_position):
			continue
		var query := PhysicsRayQueryParameters3D.create(
			camera.global_position,
			global_position,
			surface_mask,
			[player.get_rid(), get_rid()]
		)
		query.hit_from_inside = true
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return true
	return false


func _closest_living_player() -> CharacterBody3D:
	var closest: CharacterBody3D
	var closest_distance := INF
	for player: CharacterBody3D in _living_players():
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = player
	return closest


func _living_players() -> Array[CharacterBody3D]:
	var players: Array[CharacterBody3D] = []
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player:
			continue
		if 'is_alive' in player and not player.is_alive:
			continue
		players.append(player)
	return players


func _update_player_threat() -> void:
	# Hidden means genuinely gone: the overlay has to go fully clear, or the
	# player never gets the relief that makes the next omen land.
	var threatening := state != CrawlerState.DORMANT and state != CrawlerState.HIDDEN
	for node: Node in get_tree().get_nodes_in_group('players'):
		var player := node as CharacterBody3D
		if not player:
			continue
		var amount := 0.0
		if threatening:
			var distance := global_position.distance_to(player.global_position)
			amount = clampf(1.0 - distance / maxf(dread_radius, 0.01), 0.0, 1.0)
			if state == CrawlerState.POUNCE_WINDUP or state == CrawlerState.POUNCING:
				amount = maxf(amount, 0.85)
			elif state == CrawlerState.OMEN or state == CrawlerState.RETREATING:
				amount = maxf(amount, 0.6)
		if player.has_method('set_threat_from'):
			player.set_threat_from('crawler', amount)
		elif player.has_method('set_statue_threat'):
			player.set_statue_threat(amount)


# --- Presentation -------------------------------------------------------------


func _prepare_materials() -> void:
	var source := _primitive_material(skull)
	if source is ShaderMaterial:
		flesh_material = (source as ShaderMaterial).duplicate()
	if not flesh_material:
		return
	for node: Node in visual_root.find_children('*', 'MeshInstance3D', true, false):
		var mesh_instance := node as MeshInstance3D
		if _primitive_material(mesh_instance) == source:
			mesh_instance.material_override = flesh_material


func _primitive_material(mesh_instance: MeshInstance3D) -> Material:
	var primitive := mesh_instance.mesh as PrimitiveMesh
	return primitive.material if primitive else null


func _play_bone_snap() -> void:
	bone_audio.pitch_scale = randf_range(0.82, 1.15)
	bone_audio.play()


func _update_presentation(delta: float) -> void:
	presentation_time += delta

	var tangent_speed := (velocity - surface_normal * velocity.dot(surface_normal)).length()
	var speed_scale := tangent_speed / maxf(crawl_speed, 0.1)

	match state:
		CrawlerState.POUNCE_WINDUP:
			_animate_coil(delta, 1.0 - clampf(pounce_timer / maxf(pounce_windup, 0.01), 0.0, 1.0))
		CrawlerState.POUNCING:
			_animate_coil(delta, 1.0)
		CrawlerState.RECOVERING:
			_animate_collapse(delta)
		_:
			_animate_crawl(delta, speed_scale)

	_update_head_tracking(delta)
	_update_audio(tangent_speed)

	var proximity := 0.0
	for player: CharacterBody3D in _living_players():
		var distance := global_position.distance_to(player.global_position)
		proximity = maxf(proximity, clampf(1.0 - distance / maxf(dread_radius, 0.01), 0.0, 1.0))

	var target_agitation := 0.0
	match state:
		CrawlerState.PATROL:
			# Almost inert on the sweep. The flush going out of it is what makes
			# the change when it finally hears you read at a glance.
			target_agitation = maxf(proximity * 0.5, 0.12)
		CrawlerState.OMEN:
			target_agitation = 1.0
		CrawlerState.HUNTING:
			target_agitation = maxf(proximity, 0.45)
		CrawlerState.SEARCHING:
			target_agitation = maxf(proximity * 0.8, 0.2)
		CrawlerState.POUNCE_WINDUP, CrawlerState.POUNCING:
			target_agitation = 1.0
		CrawlerState.RECOVERING:
			target_agitation = 0.7
		CrawlerState.RETREATING:
			target_agitation = 0.9
	agitation = move_toward(agitation, target_agitation, delta * 3.0)

	# Breathing is fast and shallow when it is hunting, deep and slow on patrol -
	# the ribcage is the only part of it that moves when it is barely crawling.
	var breath_rate := lerpf(0.7, 4.2, agitation)
	breath = sin(presentation_time * breath_rate) * 0.5 + 0.5

	if flesh_material:
		flesh_material.set_shader_parameter('agitation', agitation)
		flesh_material.set_shader_parameter('breath', breath)

	drip.emitting = manifested and state != CrawlerState.DORMANT
	drip.amount_ratio = lerpf(drip.amount_ratio, lerpf(0.25, 1.0, agitation), minf(delta * 3.0, 1.0))


func _update_audio(tangent_speed: float) -> void:
	var crawling := tangent_speed > crawl_audio_min_speed and state != CrawlerState.POUNCING
	if crawling:
		crawl_audio.pitch_scale = clampf(0.7 + tangent_speed * 0.16, 0.7, 1.6)
		if not crawl_audio.playing:
			crawl_audio.play(randf_range(0.0, 1.5))
	elif crawl_audio.playing:
		crawl_audio.stop()

	# Audible breathing is the last warning before it is on top of you.
	var closest := INF
	for player: CharacterBody3D in _living_players():
		closest = minf(closest, global_position.distance_to(player.global_position))
	var should_breathe := closest < dread_radius * 0.45 and manifested
	if should_breathe and not breath_audio.playing:
		breath_audio.play()
	elif not should_breathe and breath_audio.playing:
		breath_audio.stop()


## The head is the only part that aims: it is blind, so it points its face at
## the sound like a dish, and holds there even after the sound stops.
func _update_head_tracking(delta: float) -> void:
	var blend := minf(delta * 6.0, 1.0)
	if not has_noise_fix:
		neck_pivot.rotation.y = lerp_angle(neck_pivot.rotation.y, 0.0, blend)
		return

	var local_target := to_local(last_noise_position)
	var yaw := atan2(-local_target.x, -local_target.z)
	neck_pivot.rotation.y = lerp_angle(
		neck_pivot.rotation.y,
		clampf(wrapf(yaw, -PI, PI), deg_to_rad(-95.0), deg_to_rad(95.0)),
		blend
	)
	var pitch := clampf(atan2(local_target.y, Vector2(local_target.x, local_target.z).length()), -1.1, 1.1)
	head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(18.0) + pitch, blend)


func _apply_rest_pose() -> void:
	for index: int in limb_roots.size():
		_pose_limb(index, 0.0, 0.0)
	body_pivot.rotation = Vector3.ZERO
	neck_pivot.rotation = Vector3.ZERO
	head_pivot.rotation = Vector3(deg_to_rad(18.0), 0.0, 0.0)
	tail_pivot.rotation = Vector3.ZERO
	tail_tip_pivot.rotation = Vector3.ZERO
	jaw_open = 0.15
	_apply_jaw()


func _animate_crawl(delta: float, raw_speed_scale: float) -> void:
	# Capped because the gait is measured against the patrol crawl, and the omen
	# dash is more than ten times that - uncapped, the limbs blur into a solid.
	var speed_scale := clampf(raw_speed_scale, 0.12, 3.0)
	crawl_phase += delta * crawl_animation_speed * speed_scale

	# The two diagonal pairs alternate. limb_roots is ordered so index 0/1 are
	# one diagonal and 2/3 the other, which is why the offset is just index >= 2.
	for index: int in limb_roots.size():
		var phase := crawl_phase + (PI if index >= 2 else 0.0)
		_pose_limb(index, phase, speed_scale)

	var stride := sin(crawl_phase)
	var counter := sin(crawl_phase + PI)
	# The spine works side to side like something dragging itself, not up and
	# down like something walking.
	body_pivot.rotation.y = stride * 0.14 * speed_scale
	body_pivot.rotation.z = counter * 0.09 * speed_scale
	body_pivot.position.y = absf(sin(crawl_phase * 2.0)) * 0.025 * speed_scale

	tail_pivot.rotation.y = -stride * 0.3 * speed_scale
	tail_pivot.rotation.x = deg_to_rad(-6.0) + counter * 0.08
	tail_tip_pivot.rotation.y = -counter * 0.42 * speed_scale

	head_pivot.rotation.z = sin(crawl_phase * 1.7) * 0.08
	jaw_open = lerpf(jaw_open, 0.2 + breath * 0.35 + agitation * 0.3, minf(delta * 5.0, 1.0))
	_apply_jaw()


## One limb of the four. `phase` runs the reach/plant cycle; `speed_scale` fades
## the whole motion out so a stationary crawler settles rather than treading.
func _pose_limb(index: int, phase: float, speed_scale: float) -> void:
	var limb := limb_roots[index]
	var lower := limb_lowers[index]
	var hand := limb_hands[index]
	var side := LIMB_SIDE_SIGNS[index]
	var front := LIMB_FRONT_SIGNS[index]

	var reach := sin(phase) * speed_scale
	# Only the recovery half of the cycle lifts the hand off the surface; the
	# other half is the power stroke and stays planted.
	var lift := maxf(sin(phase + PI * 0.5), 0.0) * speed_scale

	limb.rotation.z = deg_to_rad(side * (LIMB_UPPER_SPLAY + lift * 14.0))
	limb.rotation.x = deg_to_rad(LIMB_UPPER_PITCH * front + reach * 26.0)
	limb.rotation.y = deg_to_rad(-side * reach * 12.0)

	lower.rotation.z = deg_to_rad(side * (LIMB_LOWER_FOLD + lift * 22.0))
	lower.rotation.x = deg_to_rad(-reach * 20.0 - lift * 26.0)

	hand.rotation.x = deg_to_rad(LIMB_HAND_FLAT - lift * 34.0)
	hand.rotation.z = deg_to_rad(-side * 12.0)


## Windup and leap: everything folds in under the body, then the spine whips
## straight as it launches.
func _animate_coil(delta: float, progress: float) -> void:
	var blend := minf(delta * 12.0, 1.0)
	var coil := ease(clampf(progress, 0.0, 1.0), 0.6)
	for index: int in limb_roots.size():
		var limb := limb_roots[index]
		var lower := limb_lowers[index]
		var side := LIMB_SIDE_SIGNS[index]
		var front := LIMB_FRONT_SIGNS[index]
		limb.rotation.z = lerpf(limb.rotation.z, deg_to_rad(side * (LIMB_UPPER_SPLAY + 26.0)), blend)
		limb.rotation.x = lerpf(limb.rotation.x, deg_to_rad(front * 46.0), blend)
		lower.rotation.z = lerpf(lower.rotation.z, deg_to_rad(side * (LIMB_LOWER_FOLD + 34.0)), blend)

	body_pivot.rotation.x = lerpf(body_pivot.rotation.x, deg_to_rad(-14.0 * coil), blend)
	body_pivot.position.y = lerpf(body_pivot.position.y, -0.05 * (1.0 - coil), blend)
	head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(-32.0), blend)
	jaw_open = maxf(jaw_open, coil)
	_apply_jaw()


## Face down with its limbs still folded backwards, getting them under itself
## again. This is the visual tell for the window the player has to run.
func _animate_collapse(delta: float) -> void:
	var blend := minf(delta * 7.0, 1.0)
	for index: int in limb_roots.size():
		var limb := limb_roots[index]
		var lower := limb_lowers[index]
		var side := LIMB_SIDE_SIGNS[index]
		limb.rotation.z = lerpf(limb.rotation.z, deg_to_rad(side * 148.0), blend)
		limb.rotation.x = lerpf(limb.rotation.x, deg_to_rad(sin(presentation_time * 9.0) * 8.0), blend)
		lower.rotation.z = lerpf(lower.rotation.z, deg_to_rad(side * -46.0), blend)

	body_pivot.rotation.x = lerpf(body_pivot.rotation.x, deg_to_rad(4.0), blend)
	body_pivot.rotation.z = lerpf(body_pivot.rotation.z, sin(presentation_time * 6.0) * 0.05, blend)
	body_pivot.position.y = lerpf(body_pivot.position.y, -0.06, blend)
	head_pivot.rotation.x = lerpf(head_pivot.rotation.x, deg_to_rad(34.0), blend)
	jaw_open = lerpf(jaw_open, 0.85, blend)
	_apply_jaw()


func _apply_jaw() -> void:
	jaw_pivot.rotation.x = deg_to_rad(jaw_open * 42.0)
