extends CharacterBody3D

## "Kẻ Đi Săn" / The Huntsman.
##
## The third ghost, and the only one the night does not summon: this one is
## summoned by failure. When a defense door finally breaks, this is the thing
## that walks in through the hole.
##
## The other two are each built around one sense, and each has a counter that
## works on that sense:
##
##   statue  - hunts by SIGHT, and freezes for as long as you keep looking.
##   crawler - hunts by SOUND, and loses you completely if you hold still.
##
## The huntsman hunts by TRACK. It does not need to see you and it does not
## need to hear you; it is not looking for you at all, it is reading the floor
## you already walked on. Staring at it does nothing. Holding still does nothing
## either - worse than nothing, because the trail that leads to where you are
## standing is still lying there. Every habit the player has built against the
## other two is worthless here, which is the entire reason it exists.
##
##   ENTERING  it walks in through the breach, on foot, in plain view, and
##             stops in the doorway to sweep the house with its lantern once.
##   TRACKING  it picks up the freshest spoor inside nose range and follows it,
##             room to room, at a walk. It is never in a hurry until it sees you.
##   CASTING   trail lost: it stops dead, sniffs, turns on the spot, then quarters
##             the house along its sweep route until it cuts the trail again.
##   LOCKED    the lantern found you. A horn, and then a charge fractionally
##             faster than a sprint - corners, doorways and stairs are the only
##             counterplay, because it accelerates like something that weighs
##             three hundred kilos and cannot turn.
##   SEIZING   the grab. Half a second of windup, and that half second is the
##             only window there is.
##   LEAVING   the hunt ran out of time: it walks back out through a breach.
##
## Two rules make it the worst thing in the building:
##
##   1. It never teleports and it never vanishes while it is inside. From the
##      moment it steps in it is a physical body somewhere in the house, and its
##      boots and the hook it drags along the floor are audible through walls.
##      The statue is gone when you look away and the crawler is gone between
##      hunts. This is simply *in the house* until it decides to leave.
##   2. It leaves the way it came in. Rebuild every breach while it is inside
##      and it has no way out: it is sealed in with you until dawn, and being
##      sealed in makes it worse. Repairing your own house is therefore no
##      longer an unambiguously correct move, which is the trap the whole
##      creature is built to spring.

enum HunterState {
	DORMANT,
	ENTERING,
	TRACKING,
	CASTING,
	SWEEPING,
	LOCKED,
	SEIZING,
	RECOVERING,
	LEAVING,
}

signal state_changed(new_state: HunterState)
signal entry_scheduled(door: Node, delay: float)
signal entered_house(door: Node)
signal left_house(door: Node)
## Every breach was rebuilt while it was still inside. It cannot leave now.
signal sealed_inside()
signal trail_picked_up(position: Vector3)
signal trail_lost()
signal locked_on(player: Node3D)
signal target_lost(last_seen: Vector3)
signal seize_started(player: Node3D)
signal seize_missed()
signal killed_player(player: Node3D)

@export_category('Behavior')
@export var active: bool = true
## Walking search pace. Under a walking player on purpose: while it has not seen
## you, you can always out-walk it. That is the only mercy in the design.
@export var walk_speed: float = 1.85
## Pace once it has a live trail under it. Still below a sprint.
@export var track_speed: float = 2.6
## The charge. The player sprints at 2.5 * 1.3 = 3.25 m/s, so a straight
## corridor is simply lost - the escape is geometry, not speed.
@export var charge_speed: float = 3.5
## Deliberately low. Everything about the escape depends on it needing several
## metres to get moving and being unable to take a corner cleanly.
@export var acceleration: float = 11.0
@export var turn_speed: float = 4.2
## How much of its speed survives moving in a direction it is not yet facing.
## This is what turns a doorway into cover rather than a formality.
@export_range(0.0, 1.0) var off_axis_speed_floor: float = 0.34
@export var max_step_height: float = 0.6
@export var step_floor_margin: float = 0.08
@export var step_probe_distance: float = 0.3

@export_category('Entry')
## Whether a breached defense door lets it into the house at all.
@export var entry_enabled: bool = true
## The gap between the door breaking and the huntsman arriving at it. This is
## the window the player has to rebuild the door and keep it out entirely.
@export var entry_delay_min: float = 6.0
@export var entry_delay_max: float = 10.0
## How far outside the doorway it materialises, so it is always seen walking in.
@export var entry_offset: float = 2.6
@export var entry_timeout: float = 18.0
## It stops in the doorway and sweeps the lantern across the house before it
## starts. This is the announcement, and it is the only one you get.
@export var entry_scan_duration: float = 3.5
## Quiet between visits once it has left. Long: the house has to feel survivable
## again before the next door goes.
@export var reentry_cooldown_min: float = 75.0
@export var reentry_cooldown_max: float = 140.0

@export_category('Hunt')
## How long it will stay inside without killing anyone before it gives up.
@export var hunt_duration: float = 170.0
## Every time it gets a lock on somebody the hunt is extended. Being seen is
## what keeps it in the house.
@export var hunt_extension_per_lock: float = 30.0
@export var leave_timeout: float = 45.0

@export_category('Tracking')
## How often a player's position is written into the trail. Everything about the
## creature's difficulty is really this number against its nose range.
@export var spoor_interval: float = 0.4
## Marks older than this are gone. Roughly two minutes of your own movement is
## therefore on the floor at any time.
@export var spoor_lifetime: float = 110.0
@export_range(32, 1024, 1) var spoor_capacity: int = 400
## Player speed treated as a full-strength mark.
@export var spoor_reference_speed: float = 2.6
## What standing perfectly still still leaves behind. Not zero, and that is the
## whole difference between this and the crawler: holding your breath does not
## erase the floor you are standing on.
@export_range(0.0, 1.0) var spoor_idle_strength: float = 0.22
@export_range(0.0, 1.0) var crouch_spoor_multiplier: float = 0.45
## Marks weaker than this are unreadable, so faint old crouch-marks go cold long
## before a sprint down the same corridor does.
@export_range(0.0, 1.0) var cold_trail_strength: float = 0.12
## How far it can read the floor while it is walking a trail. Small on purpose:
## following a route is close work, done with its head down.
@export var nose_range: float = 8.5
## Close spoor is something it reads from the floor under its feet, not through
## a ceiling. Other floors remain discoverable by the long cast after it stops
## and sniffs, but can never steal a close trail from the floor it is on.
@export var nose_height_range: float = 1.6
## Added permanently once it has had a lock on you. It has your scent now.
@export var marked_nose_bonus: float = 4.0
## The long sense, used only when there is nothing readable underfoot: it stops,
## lifts its head, takes the strongest mark anywhere in this radius and walks to
## where that was. It is always walking to where you *were*, so it costs a moving
## player nothing - and it is exactly why standing still is not a plan.
@export var cast_lead_range: float = 30.0
@export var trail_arrive_distance: float = 1.2
## A mark on the landing above its head is not something it can stand on. Marks
## are only counted as reached within this vertical band.
@export var trail_arrive_height: float = 1.5
## Give up on a single mark that will not resolve, so one unreachable spot cannot
## strand the whole hunt.
@export var trail_point_timeout: float = 9.0

@export_category('Lantern')
## The lantern is its eye. It hangs off its own hand, sweeps while it searches,
## and locks dead-ahead the moment it finds something.
@export var lantern_range: float = 15.0
@export var lantern_half_angle: float = 27.0
@export var lantern_sweep_half_angle: float = 40.0
@export var lantern_sweep_speed: float = 0.9
## Time in the beam before it locks on, at contact range and at maximum range.
@export var spot_time_near: float = 0.18
@export var spot_time_far: float = 0.85
@export_range(0.0, 1.0) var crouch_spot_multiplier: float = 0.55
## Inside this it does not need the beam at all. Nothing survives sharing a
## corner with it.
@export var certain_range: float = 4.0
## How long it keeps charging after losing sight. Long enough that ducking
## behind one sofa is not an escape.
@export var lose_sight_time: float = 6.0
@export_flags_3d_physics var sight_blocking_mask: int = 1

@export_category('Casting')
## Standing still, sniffing, turning on the spot after the trail runs out.
@export var cast_duration: float = 5.5
@export var cast_turn_speed: float = 1.4
## Route markers it quarters the house along when it has no trail at all.
@export var sweep_point_group: StringName = 'hunter_sweep_points'
@export var sweep_arrive_distance: float = 2.0
## Abandon a sweep marker that will not resolve, so one unreachable room cannot
## strand the whole hunt.
@export var sweep_point_timeout: float = 26.0
## It is not deaf, it is just not listening. A full sprint this close is loud
## enough to give it a fresh place to start reading the floor.
@export var running_hearing_range: float = 11.0
@export_range(0.0, 1.0) var running_hearing_loudness: float = 0.6

@export_category('Unsticking')
## How long it may make no progress toward whatever it is walking to before it
## accepts that it cannot get there. Without this a single unreachable mark - one
## on the landing above its head, one behind a bannister - fixates it forever,
## and the whole hunt quietly ends with it standing on the stairs.
@export var stuck_release_time: float = 2.0
## After giving up it walks off at an angle for this long instead of straight at
## the thing it just failed to reach, which is what actually peels it off a
## doorframe or a corner.
@export var unstick_duration: float = 1.2
## Consecutive failures before it stops struggling and relocates. Only ever used
## while no player can see it.
@export_range(1, 10, 1) var unstick_relocate_after: int = 3
## Wedging is not always standing still: pressed against a stairwell rail with a
## player on the other side it slides back and forth at full speed forever, which
## passes any "has it moved" test. This is the second, slower test - has it
## closed any distance on its goal at all in this long a window - and it is what
## catches skating.
@export var no_closing_time: float = 7.0
## While it can see its target it does not give up and go back to sniffing: it
## drops navigation for this long and pushes straight at them instead, which is
## what gets it around a rail rather than dithering along one.
@export var direct_press_duration: float = 2.5
## How long a place it failed to reach stays written off. Burning the single mark
## is not enough: a player standing still keeps printing fresh marks in the same
## impossible spot, and it would pick the next one up and fixate again forever.
## Writing off the ground itself is what sends it away to hunt elsewhere.
@export var give_up_memory: float = 25.0
@export var give_up_radius: float = 2.5

@export_category('Seize')
## Reach. It is two and a half metres of hunched shoulders with a butcher's hook
## on the end of one arm, and this is deliberately longer than a person's: over a
## bannister, across a stairwell rail, through a doorway it cannot fit through.
## Anything shorter and a player standing behind a railing two metres away - in
## its lantern, being stared at - is untouchable, which is exactly the hole this
## creature must not have.
@export var seize_range: float = 2.35
## The only dodge window in the whole creature.
@export var seize_windup: float = 0.5
@export var seize_kill_radius: float = 2.8
@export var seize_recovery: float = 1.7
@export var seize_cooldown: float = 3.2
## Vertical separation that rules out a grab, so it cannot take somebody through
## a floor while standing on the landing above them.
@export var max_attack_height_difference: float = 1.6
@export var attack_ray_height: float = 1.1

@export_category('Sealed in')
## What being locked in with you is worth to it.
@export var trapped_speed_bonus: float = 0.5
@export var trapped_nose_bonus: float = 3.0
@export_range(0.1, 1.0) var trapped_cast_scale: float = 0.6

@export_category('Presentation')
## Distance at which the lantern bounce, the breathing and the dread overlay
## start coming up.
@export var dread_radius: float = 13.0
@export var stride_length: float = 0.95
@export var footstep_volume_db: float = -6.0

var state: HunterState = HunterState.DORMANT
## True from the moment it steps through a breach until it steps back out.
var inside_house: bool = false
## Every breach was sealed behind it. It is in here until dawn now.
var trapped: bool = false
## It has had a lock on a player at least once tonight.
var prey_marked: bool = false
var manifested: bool = false
var current_target: CharacterBody3D
var last_seen_position: Vector3
var hunt_time_remaining: float = 0.0
var entry_door: Node3D
var exit_door: Node3D
var dev_attack_suspended: bool = false
var attack_resume_grace_remaining: float = 0.0

var _clock: float = 0.0
var _spoor: Array[Dictionary] = []
var _spoor_timer: float = 0.0
## Timestamp of the last mark it committed to. It only ever reads marks newer
## than this, so it walks your route forwards and can never be sent in a circle
## by its own history.
var _trail_time: float = -1.0
var _trail_target: Vector3
var _trail_target_time: float = -1.0
var _trail_point_timer: float = 0.0
var _has_trail_target: bool = false
var _goal_position: Vector3
var _has_goal: bool = false
var _last_progress_position: Vector3
var _no_progress_time: float = 0.0
var _closest_goal_distance: float = INF
var _no_closing_time: float = 0.0
var _direct_press_timer: float = 0.0
var _unstick_timer: float = 0.0
var _unstick_sign: float = 1.0
var _failed_goals: int = 0
var _dead_spots: Array[Dictionary] = []
var _spot_progress: Dictionary = {}
var _sight_timer: float = 0.0
var _entry_timer: float = 0.0
var _pending_entry_door: Node3D
var _reentry_cooldown: float = 0.0
var _state_timer: float = 0.0
var _seize_cooldown_timer: float = 0.0
var _sweep_index: int = 0
var _sweep_timer: float = 0.0
var _sweep_points: Array[Vector3] = []
var _noise_lead: Vector3
var _has_noise_lead: bool = false
## Timestamp of the mark a long-range lead came from, or -1 for a lead that came
## from an actual noise. Reaching a lead has to retire the mark behind it, or the
## same mark is picked again the moment it arrives and it paces there forever.
var _noise_lead_time: float = -1.0
## After live sight is broken it must first reach the exact place where the
## player vanished. Reading arbitrary spoor before that made a nearby mark under
## the floor send it down a staircase, only for it to climb straight back up.
var _last_seen_lead: Vector3
var _has_last_seen_lead: bool = false
var _breached_doors: Array[Node] = []
var _travel_target: Vector3
var _travel_stage: int = 0
var _normal_collision_layer: int
var _normal_collision_mask: int
var _gravity: float = ProjectSettings.get_setting('physics/3d/default_gravity')

var _stride_phase: float = 0.0
var _agitation: float = 0.0
var _lantern_energy: float = 0.0
var _sweep_phase: float = 0.0
var _sniff_timer: float = 0.0
var _jaw_open: float = 0.0
var _hide_material: ShaderMaterial
var _visual_rest_y: float = 0.0

@onready var visual_root: Node3D = $VisualRoot
@onready var body_pivot: Node3D = $VisualRoot/BodyPivot
@onready var torso_pivot: Node3D = $VisualRoot/BodyPivot/TorsoPivot
@onready var neck_pivot: Node3D = $VisualRoot/BodyPivot/TorsoPivot/NeckPivot
@onready var head_pivot: Node3D = $VisualRoot/BodyPivot/TorsoPivot/NeckPivot/HeadPivot
@onready var jaw_pivot: Node3D = $VisualRoot/BodyPivot/TorsoPivot/NeckPivot/HeadPivot/JawPivot
@onready var coat_pivot: Node3D = $VisualRoot/BodyPivot/CoatPivot
@onready var lantern_arm: Node3D = $VisualRoot/BodyPivot/TorsoPivot/LanternArm
@onready var lantern_forearm: Node3D = $VisualRoot/BodyPivot/TorsoPivot/LanternArm/ForearmPivot
@onready var lantern_pivot: Node3D = $VisualRoot/BodyPivot/TorsoPivot/LanternArm/ForearmPivot/LanternPivot
@onready var lantern_light: SpotLight3D = $VisualRoot/BodyPivot/TorsoPivot/LanternArm/ForearmPivot/LanternPivot/LanternLight
@onready var lantern_flame: MeshInstance3D = $VisualRoot/BodyPivot/TorsoPivot/LanternArm/ForearmPivot/LanternPivot/Flame
@onready var hook_arm: Node3D = $VisualRoot/BodyPivot/TorsoPivot/HookArm
@onready var hook_forearm: Node3D = $VisualRoot/BodyPivot/TorsoPivot/HookArm/ForearmPivot
@onready var left_leg_pivot: Node3D = $VisualRoot/BodyPivot/LeftLegPivot
@onready var left_shin_pivot: Node3D = $VisualRoot/BodyPivot/LeftLegPivot/ShinPivot
@onready var right_leg_pivot: Node3D = $VisualRoot/BodyPivot/RightLegPivot
@onready var right_shin_pivot: Node3D = $VisualRoot/BodyPivot/RightLegPivot/ShinPivot
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var footstep_audio: AudioStreamPlayer3D = $FootstepAudio
@onready var hook_audio: AudioStreamPlayer3D = $HookAudio
@onready var breath_audio: AudioStreamPlayer3D = $BreathAudio
@onready var sniff_audio: AudioStreamPlayer3D = $SniffAudio
@onready var horn_audio: AudioStreamPlayer3D = $HornAudio
@onready var seize_audio: AudioStreamPlayer3D = $SeizeAudio
@onready var breach_audio: AudioStreamPlayer3D = $BreachAudio

## Transient starts inside the boot recording, so a step can be triggered from an
## arbitrary offset instead of replaying the same two seconds of walking.
const FOOTSTEP_OFFSETS: Array[float] = [0.12, 0.68, 1.21, 1.79, 2.34, 2.92, 3.44]
const FOOTSTEP_SLICE := 0.34


func _ready() -> void:
	add_to_group('hunter_ghosts')
	add_to_group('hostile_ghosts')
	_normal_collision_layer = collision_layer
	_normal_collision_mask = collision_mask
	last_seen_position = global_position
	_travel_target = global_position
	_visual_rest_y = visual_root.position.y
	_prepare_materials()
	_set_manifested(false)
	# Doors and route markers are ordinary level nodes, so they only exist once
	# the rest of the scene has entered the tree.
	_resolve_level.call_deferred()


## Picks up the sweep route and subscribes to every defense door in the level.
## Nothing here is hard-coded to House2: drop `Marker3D`s into the sweep group
## and put `DefenseDoor`s in `defense_doors` and the creature works unchanged.
func _resolve_level() -> void:
	if not is_inside_tree():
		return
	_sweep_points.clear()
	for node: Node in get_tree().get_nodes_in_group(sweep_point_group):
		var marker := node as Node3D
		if marker:
			_sweep_points.append(marker.global_position)

	for node: Node in get_tree().get_nodes_in_group('defense_doors'):
		if node.has_signal('breached') and not node.is_connected('breached', _on_door_breached):
			node.connect('breached', _on_door_breached)
		if node.has_signal('rebuilt') and not node.is_connected('rebuilt', _on_door_rebuilt):
			node.connect('rebuilt', _on_door_rebuilt)
		# A door that was already broken before this node was ready still counts.
		if _door_durability(node) <= 0.0:
			_register_breach(node)


func _physics_process(delta: float) -> void:
	_clock += delta
	attack_resume_grace_remaining = maxf(attack_resume_grace_remaining - delta, 0.0)
	if not active:
		velocity = Vector3.ZERO
		return

	# The trail is recorded whether or not it is in the house. That is the point:
	# when it finally walks in, an hour of your movement is already on the floor
	# waiting for it.
	_record_spoor(delta)

	if state == HunterState.DORMANT:
		velocity = Vector3.ZERO
		_update_dormant(delta)
		_update_player_threat()
		return

	if inside_house:
		_update_hunt_timer(delta)
	# Detection runs from the moment it is visible, which includes the walk in:
	# stand in the doorway watching it arrive and it can lock on to you there.
	if manifested:
		_update_lantern_detection(delta)

	match state:
		HunterState.ENTERING:
			_update_entering(delta)
		HunterState.TRACKING:
			_update_tracking(delta)
		HunterState.CASTING:
			_update_casting(delta)
		HunterState.SWEEPING:
			_update_sweeping(delta)
		HunterState.LOCKED:
			_update_locked(delta)
		HunterState.SEIZING:
			_update_seizing(delta)
		HunterState.RECOVERING:
			_update_recovering(delta)
		HunterState.LEAVING:
			_update_leaving(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if is_on_floor():
		_try_step_up(horizontal_motion)
	move_and_slide()

	_update_goal_progress(delta)
	_update_player_threat()
	_update_presentation(delta)


# --- The trail ----------------------------------------------------------------


## Writes one mark per living player per interval. A mark is a position, a time
## and a strength, and strength is everything: it is what separates a sprint
## down a corridor from a crouched player who has not moved in a minute.
func _record_spoor(delta: float) -> void:
	_spoor_timer -= delta
	if _spoor_timer > 0.0:
		return
	_spoor_timer = maxf(spoor_interval, 0.05)

	for player: CharacterBody3D in _living_players():
		_spoor.append({
			'position': player.global_position,
			'time': _clock,
			'strength': _spoor_strength(player),
		})

	while _spoor.size() > spoor_capacity:
		_spoor.remove_at(0)
	while not _spoor.is_empty() and _clock - float(_spoor[0]['time']) > spoor_lifetime:
		_spoor.remove_at(0)


## How much of a mark a player is currently leaving. Sprinting prints hard,
## crouching barely prints at all, and standing still still prints - faintly,
## and directly under your feet.
func _spoor_strength(player: CharacterBody3D) -> float:
	var real_velocity := player.get_real_velocity()
	var horizontal_speed := Vector2(real_velocity.x, real_velocity.z).length()
	var effort := clampf(horizontal_speed / maxf(spoor_reference_speed, 0.01), 0.0, 1.0)
	var strength := lerpf(spoor_idle_strength, 1.0, effort)
	if 'is_crouching' in player and player.is_crouching:
		strength *= crouch_spoor_multiplier
	return clampf(strength, 0.0, 1.0)


func _effective_nose_range() -> float:
	var reach := nose_range
	if prey_marked:
		reach += marked_nose_bonus
	if trapped:
		reach += trapped_nose_bonus
	return reach


## The freshest readable mark within nose range that it has not already used.
## Newest rather than oldest on purpose: it cuts the corner toward wherever you
## went next instead of pedantically retracing every footprint, and it can still
## only ever act on ground it is physically standing near.
func _pick_trail_sample() -> int:
	var reach := _effective_nose_range()
	var best_index := -1
	var best_time := _trail_time
	for index: int in _spoor.size():
		var sample := _spoor[index]
		var sample_time := float(sample['time'])
		if sample_time <= best_time:
			continue
		var age := _clock - sample_time
		if age > spoor_lifetime:
			continue
		var effective := float(sample['strength']) * (1.0 - age / maxf(spoor_lifetime, 0.01))
		if effective < cold_trail_strength:
			continue
		var sample_position: Vector3 = sample['position']
		if absf(sample_position.y - global_position.y) > nose_height_range:
			continue
		if global_position.distance_to(sample_position) > reach:
			continue
		if _is_written_off(sample_position):
			continue
		best_index = index
		best_time = sample_time
	return best_index


## Ground it has already proved it cannot walk to, and how long ago it proved it.
func _write_off_ground(position: Vector3) -> void:
	_dead_spots.append({'position': position, 'time': _clock})
	while _dead_spots.size() > 8:
		_dead_spots.remove_at(0)


func _is_written_off(position: Vector3) -> bool:
	for spot: Dictionary in _dead_spots:
		if _clock - float(spot['time']) > give_up_memory:
			continue
		if position.distance_to(spot['position']) <= give_up_radius:
			return true
	return false


## The long sense. Same readability rules as the close one, over a much larger
## radius, and used only when there is nothing to follow underfoot - so it never
## overrides an actual trail, it just stops the hunt from ever going dead.
func _pick_cold_lead() -> int:
	var best_index := -1
	var best_time := _trail_time
	for index: int in _spoor.size():
		var sample := _spoor[index]
		var sample_time := float(sample['time'])
		if sample_time <= best_time:
			continue
		var age := _clock - sample_time
		if age > spoor_lifetime:
			continue
		var effective := float(sample['strength']) * (1.0 - age / maxf(spoor_lifetime, 0.01))
		if effective < cold_trail_strength:
			continue
		if global_position.distance_to(sample['position']) > cast_lead_range:
			continue
		if _is_written_off(sample['position']):
			continue
		best_index = index
		best_time = sample_time
	return best_index


## Public noise channel, mirroring the crawler's so that anything in the level
## that already reports noise can report to this too. It does not hunt sound -
## a noise only ever gives it a place to go and start reading the floor.
func report_noise(position: Vector3, loudness: float, _source: Node = null) -> void:
	if not inside_house or loudness < running_hearing_loudness:
		return
	if global_position.distance_to(position) > running_hearing_range:
		return
	_noise_lead = position
	_noise_lead_time = -1.0
	_has_noise_lead = true


func _listen_for_running() -> void:
	for player: CharacterBody3D in _living_players():
		var real_velocity := player.get_real_velocity()
		var horizontal_speed := Vector2(real_velocity.x, real_velocity.z).length()
		var loudness := clampf(horizontal_speed / maxf(spoor_reference_speed, 0.01), 0.0, 1.0)
		if 'is_crouching' in player and player.is_crouching:
			loudness *= crouch_spoor_multiplier
		report_noise(player.global_position, loudness, player)


# --- The lantern --------------------------------------------------------------


## The lantern is the only way it can find you directly, and it is a physical
## object hanging off its hand: what the beam is pointing at on screen is
## exactly what can get you caught.
func _update_lantern_detection(delta: float) -> void:
	if state == HunterState.SEIZING or _attacks_blocked():
		return

	for player: CharacterBody3D in _living_players():
		var key := player.get_instance_id()
		var progress: float = _spot_progress.get(key, 0.0)
		var distance := global_position.distance_to(player.global_position)
		var in_beam := _is_in_lantern(player)
		var close_enough := distance <= certain_range and _has_line_of_sight(player)

		if in_beam or close_enough:
			var span := maxf(lantern_range - certain_range, 0.01)
			var far_ratio := clampf((distance - certain_range) / span, 0.0, 1.0)
			var required := lerpf(spot_time_near, spot_time_far, far_ratio)
			if 'is_crouching' in player and player.is_crouching:
				required /= maxf(crouch_spot_multiplier, 0.05)
			progress += delta / maxf(required, 0.02)
		else:
			# Decays rather than resetting: stepping in and out of a sweeping beam
			# repeatedly is not a way to stay unseen forever.
			progress -= delta * 0.75

		progress = clampf(progress, 0.0, 1.2)
		_spot_progress[key] = progress

		if progress >= 1.0 and _is_targetable(player):
			_lock_on(player)
			return


func _is_in_lantern(player: CharacterBody3D) -> bool:
	var beam_origin := lantern_light.global_position
	var to_player := (player.global_position + Vector3.UP * 0.9) - beam_origin
	var distance := to_player.length()
	if distance > lantern_range or distance < 0.05:
		return false
	# -Z is the SpotLight3D's own beam axis, so the sweep animation applied to
	# the lantern pivot changes detection exactly as it changes the visible cone.
	var beam_axis := -lantern_light.global_basis.z.normalized()
	if beam_axis.dot(to_player / distance) < cos(deg_to_rad(lantern_half_angle)):
		return false
	return _has_line_of_sight(player)


func _has_line_of_sight(player: CharacterBody3D) -> bool:
	var origin := global_position + Vector3.UP * attack_ray_height
	var target_point := player.global_position + Vector3.UP * attack_ray_height
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		target_point,
		sight_blocking_mask,
		[get_rid(), player.get_rid()]
	)
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _lock_on(player: CharacterBody3D) -> void:
	if state == HunterState.LOCKED and current_target == player:
		return
	if not inside_house:
		# Spotted somebody through the doorway on the way in. The hunt starts
		# here rather than after the scripted arrival scan.
		inside_house = true
		hunt_time_remaining = hunt_duration
		entered_house.emit(entry_door)
	current_target = player
	last_seen_position = player.global_position
	_sight_timer = lose_sight_time
	_spot_progress.clear()
	# Once it has had you in the light it has your scent for the rest of the
	# night, and every lock keeps it in the house longer.
	prey_marked = true
	hunt_time_remaining += hunt_extension_per_lock
	horn_audio.play()
	_set_state(HunterState.LOCKED)
	locked_on.emit(player)


# --- States -------------------------------------------------------------------


func _set_state(new_state: HunterState) -> void:
	if state == new_state:
		return
	state = new_state
	_state_timer = 0.0
	match new_state:
		HunterState.CASTING:
			_state_timer = cast_duration * (trapped_cast_scale if trapped else 1.0)
			sniff_audio.play()
		HunterState.SEIZING:
			_state_timer = seize_windup
		HunterState.RECOVERING:
			_state_timer = seize_recovery
		HunterState.LEAVING:
			_state_timer = leave_timeout
	state_changed.emit(new_state)


func _update_dormant(delta: float) -> void:
	_reentry_cooldown = maxf(_reentry_cooldown - delta, 0.0)
	if not entry_enabled or _reentry_cooldown > 0.0:
		return

	if not is_instance_valid(_pending_entry_door):
		# A hole left standing is a standing invitation. Once the quiet between
		# visits is spent it picks a breach itself rather than waiting for the
		# player to lose another door, so leaving one broken is a real cost.
		var door := _nearest_breached_door()
		if not is_instance_valid(door):
			return
		_pending_entry_door = door
		_entry_timer = randf_range(entry_delay_min, entry_delay_max)
		entry_scheduled.emit(door, _entry_timer)

	_entry_timer -= delta
	if _entry_timer <= 0.0:
		_begin_entry(_pending_entry_door)


## Walks in. No navigation: the ground outside the building is not part of the
## baked route graph, and this is a straight line through a doorway anyway.
func _update_entering(delta: float) -> void:
	_state_timer += delta
	var flat_offset := _travel_target - global_position
	flat_offset.y = 0.0
	if flat_offset.length() <= 0.7 or _state_timer >= entry_timeout:
		inside_house = true
		hunt_time_remaining = hunt_duration
		_trail_time = -1.0
		entered_house.emit(entry_door)
		# It stops in the doorway and sweeps the room before it commits. This is
		# the announcement the player gets, and it is the only one.
		_set_state(HunterState.CASTING)
		_state_timer = maxf(entry_scan_duration, 0.5)
		return
	_steer_toward(delta, _travel_target, walk_speed, false)


## The core of the creature: read the floor, walk to the mark, read again.
func _update_tracking(delta: float) -> void:
	_listen_for_running()

	# A broken line of sight is resolved before any scent decision. This keeps a
	# corner dodge local: reach the doorway/corner where the player disappeared,
	# then read the fresh marks in that room instead of an older floor below.
	if _has_last_seen_lead:
		var to_last_seen := _last_seen_lead - global_position
		var flat_last_seen := Vector2(to_last_seen.x, to_last_seen.z).length()
		if flat_last_seen <= trail_arrive_distance * 2.0 \
			and absf(to_last_seen.y) <= trail_arrive_height:
			_has_last_seen_lead = false
		else:
			_steer_toward(delta, _last_seen_lead, track_speed + _speed_bonus())
			return

	var sample_index := _pick_trail_sample()
	if sample_index >= 0:
		var sample := _spoor[sample_index]
		if not _has_trail_target or _trail_target.distance_to(sample['position']) > 0.35:
			_trail_target = sample['position']
			_trail_target_time = float(sample['time'])
			# The allowance has to include the walk. A mark in the bedroom above is
			# a thirty-metre route through the hall and up two flights, and a flat
			# timeout threw away perfectly good marks halfway up the stairs.
			_trail_point_timer = trail_point_timeout \
				+ global_position.distance_to(_trail_target) / maxf(track_speed, 0.5) * 1.6
			if not _has_trail_target:
				trail_picked_up.emit(_trail_target)
			_has_trail_target = true

		# Arrival is horizontal, with a vertical band. A mark left on the landing
		# above its head is not somewhere it can ever stand, and testing straight
		# 3D distance meant it could walk to directly underneath a motionless
		# player and then hold that pose until dawn.
		var to_mark := _trail_target - global_position
		var flat_distance := Vector2(to_mark.x, to_mark.z).length()
		if flat_distance <= trail_arrive_distance and absf(to_mark.y) <= trail_arrive_height:
			# Consuming the mark is what stops it from reading its own past.
			_trail_time = _trail_target_time
			_has_trail_target = false

		_trail_point_timer -= delta
		if _trail_point_timer <= 0.0:
			# This one is not resolving. Burn it and read the next rather than
			# spending the rest of the night walking at a wall.
			_abandon_goal()
			return

		_steer_toward(delta, _trail_target, track_speed + _speed_bonus())
		return

	if _has_trail_target:
		_has_trail_target = false
		trail_lost.emit()

	if _has_noise_lead:
		# Something ran nearby, or a long scent pointed this way. It does not know
		# what or where, only that the floor over there is worth reading.
		if global_position.distance_to(_noise_lead) <= trail_arrive_distance * 2.0:
			_has_noise_lead = false
			# Retire the mark that sent it here, so arriving is progress rather
			# than the start of the same walk again.
			if _noise_lead_time > _trail_time:
				_trail_time = _noise_lead_time
			_noise_lead_time = -1.0
			_set_state(HunterState.CASTING)
			return
		_steer_toward(delta, _noise_lead, track_speed + _speed_bonus())
		return

	_set_state(HunterState.CASTING)


## Lost it. It stands where the trail ran out, turns on the spot, sniffs, and
## sweeps the lantern - and then it goes back to quartering the house.
func _update_casting(delta: float) -> void:
	_listen_for_running()
	_brake(delta)

	_sniff_timer -= delta
	if _sniff_timer <= 0.0:
		_sniff_timer = randf_range(1.6, 3.4)
		if not sniff_audio.playing:
			sniff_audio.play()

	# Turning on the spot is how the sweeping lantern gets to cover a whole room
	# rather than one wall of it.
	rotation.y += cast_turn_speed * delta * (1.0 if int(_clock * 0.25) % 2 == 0 else -1.0)

	if _pick_trail_sample() >= 0:
		_set_state(HunterState.TRACKING)
		return

	_state_timer -= delta
	if _state_timer <= 0.0:
		# Nothing here. Move on to the next room and read that floor instead.
		_set_state(HunterState.SWEEPING)


## Quartering the house. It walks the authored route at its search pace, and
## stops at every marker to cast about again. Given long enough this covers the
## whole building, which is why hiding in one room forever is not a plan.
func _update_sweeping(delta: float) -> void:
	_listen_for_running()

	if _pick_trail_sample() >= 0 or _has_noise_lead:
		_set_state(HunterState.TRACKING)
		return

	# Nothing underfoot. It lifts its head and takes the longest scent it has,
	# then walks to where that was. Against a player who keeps moving this is
	# always one address out of date and costs them nothing; against a player who
	# has stopped, it is the thing that eventually opens their door.
	var lead_index := _pick_cold_lead()
	if lead_index >= 0:
		_noise_lead = _spoor[lead_index]['position']
		_noise_lead_time = float(_spoor[lead_index]['time'])
		_has_noise_lead = true
		if not sniff_audio.playing:
			sniff_audio.play()
		_set_state(HunterState.TRACKING)
		return

	if _sweep_points.is_empty():
		# No authored route. Stay where it is and keep casting rather than
		# walking off in an arbitrary direction.
		_brake(delta)
		_set_state(HunterState.CASTING)
		return

	_sweep_timer -= delta
	var target := _sweep_points[_sweep_index % _sweep_points.size()]
	if global_position.distance_to(target) <= sweep_arrive_distance or _sweep_timer <= 0.0:
		_sweep_index += 1
		_sweep_timer = sweep_point_timeout
		_set_state(HunterState.CASTING)
		return
	_steer_toward(delta, target, walk_speed + _speed_bonus())


## It has you. Everything else stops mattering: it charges, and it does not
## stop charging until it has been unable to see you for several seconds.
func _update_locked(delta: float) -> void:
	if not is_instance_valid(current_target) or not _is_targetable(current_target):
		_drop_target()
		return

	var visible_now := _has_line_of_sight(current_target) \
		and (_is_in_lantern(current_target) \
			or global_position.distance_to(current_target.global_position) <= certain_range)
	if visible_now:
		_sight_timer = lose_sight_time
		last_seen_position = current_target.global_position
	else:
		_sight_timer -= delta
		if _sight_timer <= 0.0:
			_drop_target()
			return

	_seize_cooldown_timer = maxf(_seize_cooldown_timer - delta, 0.0)
	var offset := current_target.global_position - global_position
	var flat_offset := offset
	flat_offset.y = 0.0
	if _seize_cooldown_timer <= 0.0 \
		and not _attacks_blocked() \
		and flat_offset.length() <= seize_range \
		and absf(offset.y) <= max_attack_height_difference \
		and _has_line_of_sight(current_target):
		_begin_seize()
		return

	# Pressing: navigation is what dithers along a rail, so for a couple of
	# seconds after failing to close it goes straight at them instead.
	_direct_press_timer = maxf(_direct_press_timer - delta, 0.0)
	_steer_toward(
		delta,
		current_target.global_position,
		charge_speed + _speed_bonus(),
		_direct_press_timer <= 0.0
	)


func _begin_seize() -> void:
	seize_audio.play()
	_set_state(HunterState.SEIZING)
	seize_started.emit(current_target)


## Half a second, arms out, lantern up into your face. Break out of reach in that
## time and it commits to nothing but empty air.
func _update_seizing(delta: float) -> void:
	_brake(delta)
	if _attacks_blocked():
		_seize_cooldown_timer = seize_cooldown
		_set_state(HunterState.RECOVERING)
		return

	if is_instance_valid(current_target):
		var to_target := current_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			var target_yaw := atan2(-to_target.x, -to_target.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * 2.0 * delta, 1.0))

	_state_timer -= delta
	if _state_timer > 0.0:
		return

	_seize_cooldown_timer = seize_cooldown
	if is_instance_valid(current_target) \
		and not _attacks_blocked() \
		and global_position.distance_to(current_target.global_position) <= seize_kill_radius \
		and _has_line_of_sight(current_target):
		_kill(current_target)
		return

	seize_missed.emit()
	_set_state(HunterState.RECOVERING)


func _update_recovering(delta: float) -> void:
	_brake(delta)
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	if is_instance_valid(current_target) and _sight_timer > 0.0:
		_set_state(HunterState.LOCKED)
	else:
		_drop_target()


## Walks back out through a breach. If it reaches the doorway and the doorway is
## gone, it is not going anywhere.
func _update_leaving(delta: float) -> void:
	_state_timer -= delta
	if not is_instance_valid(exit_door) or not _is_breached(exit_door):
		exit_door = _nearest_breached_door()
		if not is_instance_valid(exit_door):
			_become_trapped()
			return
		_travel_stage = 0

	if _travel_stage == 0:
		var inside_point := _door_side_point(exit_door, true)
		if global_position.distance_to(inside_point) <= 1.0 or _state_timer <= 0.0:
			_travel_stage = 1
		else:
			_steer_toward(delta, inside_point, walk_speed + _speed_bonus())
			return

	var outside_point := _door_side_point(exit_door, false)
	var flat_offset := outside_point - global_position
	flat_offset.y = 0.0
	if flat_offset.length() <= 0.8 or _state_timer <= -entry_timeout:
		_leave_house()
		return
	_steer_toward(delta, outside_point, walk_speed + _speed_bonus(), false)


func _update_hunt_timer(delta: float) -> void:
	if trapped:
		return
	hunt_time_remaining -= delta
	if hunt_time_remaining > 0.0:
		return
	if state == HunterState.LOCKED or state == HunterState.SEIZING:
		# It is not walking out of the house with a player in the lantern.
		hunt_time_remaining = hunt_extension_per_lock
		return
	if state != HunterState.LEAVING:
		exit_door = _nearest_breached_door()
		_travel_stage = 0
		if not is_instance_valid(exit_door):
			_become_trapped()
			return
		_set_state(HunterState.LEAVING)


func _drop_target() -> void:
	var seen_at := last_seen_position
	current_target = null
	_spot_progress.clear()
	# It goes to where you were before reading anything else. Losing it is only a
	# reprieve: the trail is hottest exactly at the corner where it lost you.
	_trail_time = _clock - 6.0
	_has_trail_target = false
	# A live sighting is stronger evidence than any sound/cold-cast lead that was
	# queued before the lock, so none of those may resume after this corner check.
	_has_noise_lead = false
	_noise_lead_time = -1.0
	_last_seen_lead = seen_at
	_has_last_seen_lead = true
	_set_state(HunterState.TRACKING)
	target_lost.emit(seen_at)


func _kill(player: CharacterBody3D) -> void:
	if _attacks_blocked():
		return
	if player.has_method('kill_by_ghost'):
		player.kill_by_ghost(self)
	killed_player.emit(player)
	_set_state(HunterState.RECOVERING)


# --- Doors --------------------------------------------------------------------


func _on_door_breached(door: Node) -> void:
	_register_breach(door)


func _register_breach(door: Node) -> void:
	var body := door as Node3D
	if not body or _breached_doors.has(body):
		return
	_breached_doors.append(body)
	if not entry_enabled or inside_house or state != HunterState.DORMANT:
		return
	if is_instance_valid(_pending_entry_door):
		return
	_pending_entry_door = body
	_entry_timer = randf_range(entry_delay_min, entry_delay_max)
	entry_scheduled.emit(body, _entry_timer)


func _on_door_rebuilt(door: Node) -> void:
	_breached_doors.erase(door)
	if _pending_entry_door == door:
		# Sealed before it arrived. It will use another hole if the house has one.
		_pending_entry_door = _nearest_breached_door()
		if is_instance_valid(_pending_entry_door):
			_entry_timer = randf_range(entry_delay_min, entry_delay_max)
			entry_scheduled.emit(_pending_entry_door, _entry_timer)
	if inside_house and not trapped and not is_instance_valid(_nearest_breached_door()):
		_become_trapped()


## Doors report their own durability, but the entry system is deliberately not
## typed to DefenseDoor: any Node3D can stand in as a doorway (a smoke test uses
## a bare Marker-like body), and anything without the property is treated as an
## open hole rather than crashing on the cast.
func _door_durability(door: Node) -> float:
	var value: Variant = door.get('current_durability')
	return float(value) if value != null else 0.0


func _is_breached(door: Node) -> bool:
	return is_instance_valid(door) \
		and _breached_doors.has(door) \
		and _door_durability(door) <= 0.0


func _nearest_breached_door() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node: Node in _breached_doors:
		var door := node as Node3D
		if not is_instance_valid(door) or _door_durability(door) > 0.0:
			continue
		var distance := global_position.distance_to(door.global_position)
		if distance < best_distance:
			best_distance = distance
			best = door
	return best


## Which side of a doorway is indoors. A door only knows its own facing, so the
## interior side is decided by which of the two candidates lies nearer the middle
## of the building - which is derived from the level's own markers, never
## hard-coded to one house.
func _door_side_point(door: Node3D, inside: bool) -> Vector3:
	var axis := door.global_basis.z.normalized()
	if axis.length_squared() < 0.0001:
		axis = Vector3.FORWARD
	var centre := _house_centre()
	var forward_point := door.global_position + axis * entry_offset
	var backward_point := door.global_position - axis * entry_offset
	var forward_is_inside := forward_point.distance_to(Vector3(centre.x, forward_point.y, centre.z)) \
		< backward_point.distance_to(Vector3(centre.x, backward_point.y, centre.z))
	if inside == forward_is_inside:
		return forward_point
	return backward_point


func _house_centre() -> Vector3:
	if not _sweep_points.is_empty():
		var total := Vector3.ZERO
		for point: Vector3 in _sweep_points:
			total += point
		return total / float(_sweep_points.size())
	var door_total := Vector3.ZERO
	var door_count := 0
	for node: Node in get_tree().get_nodes_in_group('defense_doors'):
		var door := node as Node3D
		if door:
			door_total += door.global_position
			door_count += 1
	return door_total / float(door_count) if door_count > 0 else Vector3.ZERO


func _begin_entry(door: Node3D) -> void:
	if not is_instance_valid(door):
		_pending_entry_door = null
		return
	entry_door = door
	_pending_entry_door = null
	_travel_target = _door_side_point(door, true)
	var outside_point := _door_side_point(door, false)
	# Its origin is at its boots, like the statue's, so this is a small clearance
	# hop rather than a drop from head height.
	global_position = outside_point + Vector3.UP * 0.15
	# Face the hole it is about to come through.
	var facing := _travel_target - outside_point
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		rotation.y = atan2(-facing.x, -facing.z)
	velocity = Vector3.ZERO
	_reset_hunt_memory()
	_set_manifested(true)
	breach_audio.play()
	_set_state(HunterState.ENTERING)


func _leave_house() -> void:
	var door := exit_door
	inside_house = false
	current_target = null
	exit_door = null
	entry_door = null
	_reentry_cooldown = randf_range(reentry_cooldown_min, reentry_cooldown_max)
	_pending_entry_door = null
	_set_manifested(false)
	velocity = Vector3.ZERO
	_set_state(HunterState.DORMANT)
	left_house.emit(door)


## Every breach rebuilt behind it. It has no way out of the building now, and it
## stops pacing itself: it is here until dawn.
func _become_trapped() -> void:
	if trapped:
		return
	trapped = true
	prey_marked = true
	hunt_time_remaining = INF
	horn_audio.play()
	breach_audio.play()
	if state == HunterState.LEAVING:
		_set_state(HunterState.CASTING)
	sealed_inside.emit()


# --- Movement -----------------------------------------------------------------


func _steer_toward(
	delta: float,
	point: Vector3,
	speed: float,
	use_navigation: bool = true
) -> void:
	if not _has_goal or _goal_position.distance_to(point) > 0.6:
		_goal_position = point
		_has_goal = true
		_last_progress_position = global_position
		_no_progress_time = 0.0
		_no_closing_time = 0.0
		_closest_goal_distance = INF

	var direction := _steering_direction(point, use_navigation)
	if direction.is_zero_approx():
		_brake(delta)
		return

	# Peeling off whatever it just failed to walk through. Steering across the
	# obstruction for a moment is what gets it around a doorframe; steering at the
	# obstruction again is what got it stuck in the first place.
	if _unstick_timer > 0.0:
		_unstick_timer -= delta
		var sideways := Vector3(-direction.z, 0.0, direction.x) * _unstick_sign
		direction = (direction * 0.35 + sideways).normalized()

	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))

	# It cannot sidestep. Speed is scaled by how far the requested direction is
	# from the way it is actually pointing, so every corner costs it real time
	# and a doorway taken at an angle is a genuine escape rather than a formality.
	var facing := -global_basis.z
	facing.y = 0.0
	var alignment := 1.0
	if facing.length_squared() > 0.0001:
		alignment = clampf(facing.normalized().dot(direction), 0.0, 1.0)
	var desired := direction * speed * lerpf(off_axis_speed_floor, 1.0, alignment)
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)


func _steering_direction(point: Vector3, use_navigation: bool) -> Vector3:
	var direct := point - global_position
	direct.y = 0.0

	if use_navigation and _has_navigation():
		if nav_agent.target_position.distance_squared_to(point) > 0.04:
			nav_agent.target_position = point
		var to_next := nav_agent.get_next_path_position() - global_position
		to_next.y = 0.0
		if nav_agent.get_current_navigation_path().size() > 1 and to_next.length_squared() > 0.0001:
			return to_next.normalized()

	if direct.length_squared() < 0.0001:
		return Vector3.ZERO
	return direct.normalized()


func _has_navigation() -> bool:
	var map_rid := nav_agent.get_navigation_map()
	return map_rid.is_valid() \
		and NavigationServer3D.map_get_iteration_id(map_rid) > 0 \
		and not NavigationServer3D.map_get_regions(map_rid).is_empty()


func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta * 2.0)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta * 2.0)


## Catches a body that is walking and going nowhere: wedged in a doorframe,
## grinding on a bannister, or standing under a mark on the floor above with its
## feet still going.
##
## Deliberately measured as ground actually covered, not as distance closed on
## the goal. Distance-to-goal is the obvious metric and it is wrong here: routing
## to a room upstairs starts by walking *away* from it toward the staircase, so a
## closing-distance test declares a perfectly healthy stair route stuck every
## time. Fixating on somewhere it genuinely cannot reach is caught separately, by
## the per-mark timeout.
func _update_goal_progress(delta: float) -> void:
	var should_be_travelling := state == HunterState.TRACKING \
		or state == HunterState.SWEEPING \
		or state == HunterState.LOCKED \
		or state == HunterState.LEAVING \
		or state == HunterState.ENTERING
	if not should_be_travelling or not _has_goal:
		_no_progress_time = 0.0
		_no_closing_time = 0.0
		_closest_goal_distance = INF
		_last_progress_position = global_position
		return

	# Second, slower test: skating. Pressed against a rail with a player on the
	# other side it slides back and forth at full speed and covers plenty of
	# ground while closing no distance whatsoever, so the distance it has ever
	# managed to get to its goal is tracked over a long window as well.
	var goal_distance := global_position.distance_to(_goal_position)
	if goal_distance < _closest_goal_distance - 0.2:
		_closest_goal_distance = goal_distance
		_no_closing_time = 0.0
	else:
		_no_closing_time += delta

	if global_position.distance_to(_last_progress_position) > 0.35:
		_last_progress_position = global_position
		_no_progress_time = 0.0
		_failed_goals = 0
		if _no_closing_time < no_closing_time:
			return
	else:
		_no_progress_time += delta
		if _no_progress_time < stuck_release_time and _no_closing_time < no_closing_time:
			return

	_abandon_goal()


## Gives up on the current destination and picks the next best thing to do. Every
## travelling state needs an answer here, because "I cannot reach this" must
## never resolve to "then I will stand still".
func _abandon_goal() -> void:
	_no_progress_time = 0.0
	_no_closing_time = 0.0
	_closest_goal_distance = INF
	_last_progress_position = global_position
	_has_goal = false
	_failed_goals += 1
	_unstick_timer = unstick_duration
	_unstick_sign = 1.0 if randf() < 0.5 else -1.0

	match state:
		HunterState.TRACKING:
			# Burn the mark it could not reach, along with everything older, and
			# write off the ground under it - otherwise a player standing still
			# prints a fresh mark in the same impossible place every 0.4 s and it
			# re-fixates immediately.
			if _has_trail_target:
				_write_off_ground(_trail_target)
				if _trail_target_time > _trail_time:
					_trail_time = _trail_target_time
			elif _has_last_seen_lead:
				_write_off_ground(_last_seen_lead)
			elif _has_noise_lead:
				_write_off_ground(_noise_lead)
			_has_trail_target = false
			_has_last_seen_lead = false
			_has_noise_lead = false
			_set_state(HunterState.CASTING)
		HunterState.SWEEPING:
			_sweep_index += 1
			_sweep_timer = sweep_point_timeout
			_set_state(HunterState.CASTING)
		HunterState.LOCKED:
			# It has them in the light and cannot close. Giving up here is the one
			# thing it must never do while it can still see somebody, so it drops
			# navigation and pushes straight at them instead - which is what gets
			# it around a stairwell rail rather than dithering along one. Only a
			# target it can no longer see is written off and abandoned.
			if is_instance_valid(current_target) and _has_line_of_sight(current_target):
				_direct_press_timer = direct_press_duration
				_failed_goals = 0
			else:
				if is_instance_valid(current_target):
					_write_off_ground(current_target.global_position)
				_drop_target()
		HunterState.LEAVING:
			if _travel_stage == 0:
				_travel_stage = 1
			else:
				_leave_house()
		HunterState.ENTERING:
			_travel_target = _door_side_point(entry_door, true) if is_instance_valid(entry_door) \
				else global_position

	if _failed_goals >= unstick_relocate_after:
		_relocate_after_wedging()


## Last resort. A house assembled from modular panels has corners a body this
## size can enter and not steer out of, and no amount of local escape logic
## covers all of them. Rather than let one of those end the hunt with the
## huntsman standing on a staircase until dawn, it walks itself to the nearest
## room on its route - but only while nobody is watching, so it is never seen to
## blink across the house.
func _relocate_after_wedging() -> void:
	if _sweep_points.is_empty() or _is_visible_to_any_player():
		return

	var destination := _sweep_points[_sweep_index % _sweep_points.size()]
	var landing := _standable_point(destination)
	if landing == Vector3.INF:
		return

	_failed_goals = 0
	_has_goal = false
	_no_progress_time = 0.0
	_no_closing_time = 0.0
	_closest_goal_distance = INF
	_last_progress_position = global_position
	global_position = landing
	velocity = Vector3.ZERO
	_set_state(HunterState.CASTING)


## Nearest point it could actually stand on, using the navmesh where the level
## has one and a downward probe where it does not.
func _standable_point(near: Vector3) -> Vector3:
	if _has_navigation():
		var map_rid := nav_agent.get_navigation_map()
		var nav_point := NavigationServer3D.map_get_closest_point(map_rid, near)
		if nav_point.distance_to(near) > 4.0:
			return Vector3.INF
		return nav_point + Vector3.UP * 0.1

	var query := PhysicsRayQueryParameters3D.create(
		near + Vector3.UP * 1.5,
		near + Vector3.DOWN * 3.0,
		sight_blocking_mask,
		[get_rid()]
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return (hit['position'] as Vector3) + Vector3.UP * 0.1


func _is_visible_to_any_player() -> bool:
	for player: CharacterBody3D in _living_players():
		if 'eyes_closed' in player and player.eyes_closed:
			continue
		var camera := player.get_node_or_null('CameraPivot/Camera3D') as Camera3D
		if not camera:
			continue
		if camera.is_position_in_frustum(global_position + Vector3.UP * 1.0) \
			and _has_line_of_sight(player):
			return true
	return false


func _speed_bonus() -> float:
	return trapped_speed_bonus if trapped else 0.0


## Hops it onto a stair riser blocking its horizontal motion, the same probe
## sequence player.gd and statue_ghost.gd use: forward, up, forward again from
## the raised height, then down for a walkable landing.
func _try_step_up(horizontal_motion: Vector3) -> void:
	if horizontal_motion.is_zero_approx():
		return
	if is_on_floor() and get_floor_normal().dot(up_direction) < 0.98:
		return

	var forward_collision := KinematicCollision3D.new()
	if not test_move(global_transform, horizontal_motion, forward_collision, safe_margin, false):
		return
	if forward_collision.get_normal().dot(up_direction) >= cos(floor_max_angle):
		return

	var available_step_height := max_step_height
	var up_collision := KinematicCollision3D.new()
	if test_move(
		global_transform,
		Vector3.UP * max_step_height,
		up_collision,
		safe_margin,
		false
	):
		available_step_height = up_collision.get_travel().y
	if available_step_height <= 0.02:
		return

	var probe_motion := horizontal_motion
	if probe_motion.length() < step_probe_distance:
		probe_motion = probe_motion.normalized() * step_probe_distance

	var raised_transform := global_transform
	raised_transform.origin += Vector3.UP * available_step_height
	if test_move(raised_transform, probe_motion):
		return

	var forward_transform := raised_transform
	forward_transform.origin += probe_motion
	var down_collision := KinematicCollision3D.new()
	if not test_move(
		forward_transform,
		Vector3.DOWN * (available_step_height + step_floor_margin),
		down_collision
	):
		return
	if down_collision.get_normal().dot(up_direction) < 0.65:
		return

	var landing_y := forward_transform.origin.y + down_collision.get_travel().y
	var step_height := landing_y - global_position.y
	if step_height > 0.02 and step_height <= available_step_height + step_floor_margin:
		global_position.y += step_height


# --- Shared ghost API ---------------------------------------------------------


func set_dev_attack_suspended(suspended: bool) -> void:
	if dev_attack_suspended == suspended:
		return
	dev_attack_suspended = suspended
	if suspended:
		attack_resume_grace_remaining = 0.0
		_spot_progress.clear()
		if state == HunterState.SEIZING:
			_seize_cooldown_timer = seize_cooldown
			_set_state(HunterState.RECOVERING)
	else:
		attack_resume_grace_remaining = maxf(attack_resume_grace_remaining, seize_cooldown)
	_update_player_threat()


func _attacks_blocked() -> bool:
	return dev_attack_suspended or attack_resume_grace_remaining > 0.0


## Development hook: puts it in the house immediately, beside the chosen player,
## without waiting for a door to break. It behaves exactly as it would after a
## real entry - including needing an actual breach to ever leave again.
func dev_force_spawn(target: CharacterBody3D = null) -> bool:
	active = true
	var spawn_position := global_position
	if is_instance_valid(target):
		var forward := -target.global_basis.z
		var camera := target.get_node_or_null('CameraPivot/Camera3D') as Camera3D
		if camera:
			forward = -camera.global_basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			spawn_position = target.global_position + forward.normalized() * 6.0
		else:
			spawn_position = target.global_position + Vector3.FORWARD * 6.0
		spawn_position.y = target.global_position.y

	# Snap to real standable ground. Dropping it at a raw offset in front of the
	# player put it inside walls and furniture, where it could never walk out.
	var landing := _standable_point(spawn_position)
	if landing == Vector3.INF and is_instance_valid(target):
		landing = _standable_point(target.global_position)
	global_position = landing + Vector3.UP * 0.15 if landing != Vector3.INF \
		else spawn_position + Vector3.UP * 0.15
	velocity = Vector3.ZERO
	_reset_hunt_memory()
	inside_house = true
	hunt_time_remaining = hunt_duration
	entry_door = null
	_set_manifested(true)
	horn_audio.play()
	_set_state(HunterState.CASTING)
	entered_house.emit(null)
	return true


func _reset_hunt_memory() -> void:
	current_target = null
	_spot_progress.clear()
	_trail_time = -1.0
	_trail_target_time = -1.0
	_trail_point_timer = 0.0
	_has_trail_target = false
	_has_last_seen_lead = false
	_has_noise_lead = false
	_noise_lead_time = -1.0
	_has_goal = false
	_last_progress_position = global_position
	_no_progress_time = 0.0
	_no_closing_time = 0.0
	_closest_goal_distance = INF
	_direct_press_timer = 0.0
	_failed_goals = 0
	_unstick_timer = 0.0
	_sight_timer = 0.0
	_seize_cooldown_timer = 0.0
	_sweep_timer = sweep_point_timeout
	_travel_stage = 0
	_sweep_index = _nearest_sweep_index()


func _nearest_sweep_index() -> int:
	var best_index := 0
	var best_distance := INF
	for index: int in _sweep_points.size():
		var distance := global_position.distance_to(_sweep_points[index])
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


func _set_manifested(is_manifested: bool) -> void:
	manifested = is_manifested
	visual_root.visible = is_manifested
	collision_layer = _normal_collision_layer if is_manifested else 0
	collision_mask = _normal_collision_mask if is_manifested else 0
	lantern_light.visible = is_manifested
	if not is_manifested:
		footstep_audio.stop()
		hook_audio.stop()
		breath_audio.stop()
		for player: CharacterBody3D in _living_players():
			if player.has_method('set_threat_from'):
				player.set_threat_from(&'hunter', 0.0)


## Alive is not the same as attackable: the door minigame temporarily protects
## whoever is playing it, and nothing may lock on to a protected player.
func _is_targetable(player: CharacterBody3D) -> bool:
	if not player.has_method('can_be_targeted_by_ghosts'):
		return true
	return bool(player.call('can_be_targeted_by_ghosts'))


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
	for player: CharacterBody3D in _living_players():
		if not player.has_method('set_threat_from'):
			continue
		var threat := 0.0
		if manifested and not _attacks_blocked():
			var distance := global_position.distance_to(player.global_position)
			threat = clampf(1.0 - distance / maxf(dread_radius, 0.01), 0.0, 1.0) * 0.6
			if current_target == player:
				match state:
					HunterState.LOCKED:
						threat = maxf(threat, 0.85)
					HunterState.SEIZING:
						threat = 1.0
					_:
						threat = maxf(threat, 0.4)
			if trapped:
				threat = minf(threat * 1.2, 1.0)
		player.set_threat_from(&'hunter', threat)


# --- Presentation -------------------------------------------------------------


func _prepare_materials() -> void:
	for node: Node in find_children('*', 'MeshInstance3D', true, false):
		var mesh_instance := node as MeshInstance3D
		var material := mesh_instance.get_active_material(0) as ShaderMaterial
		if material and material.shader:
			_hide_material = material
			break


func _update_presentation(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var charging := state == HunterState.LOCKED or state == HunterState.SEIZING
	var target_agitation := 0.0
	if charging:
		target_agitation = 1.0
	elif state == HunterState.TRACKING:
		target_agitation = 0.35
	_agitation = move_toward(_agitation, target_agitation, delta * 1.6)

	# Gait. One stride per stride_length of ground covered, so the boots always
	# land where the legs actually are.
	var previous_phase := _stride_phase
	_stride_phase += horizontal_speed / maxf(stride_length, 0.05) * delta * TAU * 0.5
	var swing := sin(_stride_phase)
	var opposite := sin(_stride_phase + PI)
	left_leg_pivot.rotation.x = swing * 0.44
	right_leg_pivot.rotation.x = opposite * 0.44
	left_shin_pivot.rotation.x = -maxf(swing, 0.0) * 0.55
	right_shin_pivot.rotation.x = -maxf(opposite, 0.0) * 0.55
	# The whole body drops onto each planted boot: a heavy, uneven limp rather
	# than a walk cycle.
	visual_root.position.y = _visual_rest_y - absf(sin(_stride_phase)) * 0.045
	body_pivot.rotation.z = sin(_stride_phase) * 0.05
	body_pivot.rotation.x = lerpf(0.0, -0.16, _agitation) + sin(_stride_phase * 2.0) * 0.012
	coat_pivot.rotation.x = -swing * 0.1
	coat_pivot.rotation.z = sin(_stride_phase * 0.5) * 0.06

	if int(previous_phase / PI) != int(_stride_phase / PI) and horizontal_speed > 0.25:
		_play_footstep(horizontal_speed)

	# The hook drags the whole time it moves. This is the sound that tells a
	# player two rooms away exactly how close it is.
	hook_arm.rotation.x = 0.22 + opposite * 0.12
	hook_forearm.rotation.x = -0.35 + sin(_stride_phase * 0.5) * 0.08
	_update_hook_audio(horizontal_speed)

	# Head. It leads with the muzzle while tracking - nose down, reading - and
	# snaps level the instant it is charging something.
	var searching := state == HunterState.CASTING \
		or state == HunterState.SWEEPING \
		or state == HunterState.TRACKING
	neck_pivot.rotation.x = lerpf(neck_pivot.rotation.x, 0.34 if searching else 0.05, minf(delta * 4.0, 1.0))
	head_pivot.rotation.x = lerpf(head_pivot.rotation.x, 0.2 if searching else -0.08, minf(delta * 4.0, 1.0))
	head_pivot.rotation.y = sin(_clock * (1.6 if searching else 0.4)) * (0.4 if searching else 0.08)
	_jaw_open = move_toward(_jaw_open, 1.0 if charging else 0.12, delta * 3.0)
	jaw_pivot.rotation.x = _jaw_open * 0.42

	# Lantern. It sweeps while it is searching and locks dead on you when it is
	# not - so a beam that stops moving is the worst thing you can see.
	_sweep_phase += delta * lantern_sweep_speed * (1.0 if searching else 0.25)
	lantern_arm.rotation.x = lerpf(lantern_arm.rotation.x, -0.95 if charging else -0.72, minf(delta * 3.0, 1.0))
	lantern_forearm.rotation.x = lerpf(lantern_forearm.rotation.x, -0.5, minf(delta * 3.0, 1.0))
	lantern_pivot.rotation.y = lerp_angle(
		lantern_pivot.rotation.y,
		sin(_sweep_phase) * 0.3 if searching else 0.0,
		minf(delta * 5.0, 1.0)
	)
	_aim_lantern(delta, searching, charging)
	var target_energy := 0.0
	if manifested:
		target_energy = lerpf(3.2, 6.4, _agitation)
	_lantern_energy = move_toward(_lantern_energy, target_energy, delta * 8.0)
	lantern_light.light_energy = _lantern_energy * (0.94 + sin(_clock * 13.0) * 0.06)
	lantern_light.light_color = Color(1.0, 0.72, 0.36).lerp(Color(1.0, 0.36, 0.18), _agitation)
	lantern_flame.scale = Vector3.ONE * (0.9 + sin(_clock * 17.0) * 0.08 + _agitation * 0.3)

	if _hide_material:
		_hide_material.set_shader_parameter('agitation', _agitation)
		_hide_material.set_shader_parameter('lantern_glow', 0.35 + _agitation * 0.9)

	_update_breath_audio()


## The beam is aimed in world space rather than inherited from the arm chain.
## The arm swings, the lantern body swings with it, and the light itself stays
## a deliberate, steerable cone: what the player sees sweeping the corridor is
## exactly the volume `_is_in_lantern` tests against, so getting caught is never
## something that happened off-screen.
func _aim_lantern(delta: float, searching: bool, charging: bool) -> void:
	var yaw := rotation.y
	var pitch := -0.1
	if charging and is_instance_valid(current_target):
		var to_target := (current_target.global_position + Vector3.UP * 0.9) \
			- lantern_light.global_position
		if to_target.length_squared() > 0.0001:
			var direction := to_target.normalized()
			yaw = atan2(-direction.x, -direction.z)
			pitch = asin(clampf(direction.y, -1.0, 1.0))
	elif searching:
		yaw += sin(_sweep_phase) * deg_to_rad(lantern_sweep_half_angle)
		pitch += sin(_sweep_phase * 0.5) * 0.06

	var target_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	lantern_light.global_basis = lantern_light.global_basis.orthonormalized().slerp(
		target_basis,
		minf(delta * 9.0, 1.0)
	).orthonormalized()


func _play_footstep(horizontal_speed: float) -> void:
	if not footstep_audio.stream:
		return
	var offset_index := randi() % FOOTSTEP_OFFSETS.size()
	footstep_audio.pitch_scale = randf_range(0.62, 0.72)
	footstep_audio.volume_db = footstep_volume_db + minf(horizontal_speed, 3.5)
	footstep_audio.play(FOOTSTEP_OFFSETS[offset_index])
	# The recording is a continuous walk; cut it back to one boot fall.
	get_tree().create_timer(FOOTSTEP_SLICE, false).timeout.connect(
		func() -> void:
			if is_instance_valid(footstep_audio) and footstep_audio.playing:
				footstep_audio.stop()
	)


func _update_hook_audio(horizontal_speed: float) -> void:
	if not hook_audio.stream:
		return
	if horizontal_speed < 0.2:
		if hook_audio.playing:
			hook_audio.stop()
		return
	if not hook_audio.playing:
		hook_audio.play(randf_range(0.0, maxf(hook_audio.stream.get_length() - 1.5, 0.0)))
	hook_audio.pitch_scale = 0.55 + horizontal_speed * 0.05
	hook_audio.volume_db = lerpf(-22.0, -9.0, clampf(horizontal_speed / 3.0, 0.0, 1.0))


func _update_breath_audio() -> void:
	if not breath_audio.stream:
		return
	var nearest := INF
	for player: CharacterBody3D in _living_players():
		nearest = minf(nearest, global_position.distance_to(player.global_position))
	if nearest > dread_radius * 0.55:
		if breath_audio.playing:
			breath_audio.stop()
		return
	if not breath_audio.playing:
		breath_audio.play()
	breath_audio.pitch_scale = lerpf(0.58, 0.78, _agitation)


# --- Test and tooling hooks ---------------------------------------------------


## Lets a smoke test drive an entry without instancing the whole door scene.
func begin_entry_at(door: Node3D) -> bool:
	if not is_instance_valid(door) or inside_house:
		return false
	_begin_entry(door)
	return true


func get_trail_size() -> int:
	return _spoor.size()


func has_trail_lead() -> bool:
	return _pick_trail_sample() >= 0


func get_spot_progress(player: Node) -> float:
	return float(_spot_progress.get(player.get_instance_id(), 0.0))


func force_leave() -> void:
	if not inside_house:
		return
	hunt_time_remaining = 0.0
	_update_hunt_timer(0.0)
