extends SceneTree

## Covers the five things that define the huntsman and would silently rot:
## it only gets in through a breached door, it follows the trail a player leaves
## on the floor rather than sight or sound, its lantern locks on and its grab
## kills, sealing the last breach traps it inside, and an open breach lets it
## walk back out.

const FLOOR_Y := 0.0
const DOOR_Z := 6.0

# HunterState lives on the hunter's script, which this SceneTree script has no
# static handle on. These mirror the enum's declaration order.
const HunterState_DORMANT := 0
const HunterState_ENTERING := 1
const HunterState_TRACKING := 2
const HunterState_LOCKED := 5
const HunterState_LEAVING := 8

var hunter_scene: PackedScene
var door_scene: PackedScene


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_build_room()
	hunter_scene = load('res://ghosts/hunter_ghost.tscn') as PackedScene
	door_scene = load('res://door/defense_door.tscn') as PackedScene

	if not await _test_enters_through_a_breach():
		return
	if not await _test_sealing_before_arrival_keeps_it_out():
		return
	if not await _test_follows_the_trail():
		return
	if not await _test_unreachable_mark_does_not_freeze_it():
		return
	if not await _test_lantern_lock_and_seize():
		return
	if not await _test_minigame_safety_blocks_the_grab():
		return
	if not await _test_sealing_the_last_breach_traps_it():
		return
	if not await _test_leaves_through_a_breach():
		return

	print(
		'Hunter ghost smoke test passed: breach entry, sealed-out, trail following, '
		+ 'unreachable-mark recovery, lantern lock and seize, attack safety, '
		+ 'sealed-in, breach exit.'
	)
	quit()


## A bare floor slab. Everything this creature does is on the ground, so there is
## deliberately no ceiling or wall geometry to confuse the navigation fallback.
func _build_room() -> void:
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 60.0)
	shape_node.shape = box
	body.add_child(shape_node)
	root.add_child(body)
	body.global_position = Vector3(0.0, FLOOR_Y - 0.1, 0.0)


## The house centre is derived from the sweep route, so the route is what tells
## the huntsman which side of a doorway is indoors.
func _add_sweep_markers() -> Array[Node3D]:
	var markers: Array[Node3D] = []
	for point: Vector3 in [Vector3(0.0, 0.2, 0.0), Vector3(3.0, 0.2, -3.0), Vector3(-3.0, 0.2, -3.0)]:
		var marker := Marker3D.new()
		marker.add_to_group('hunter_sweep_points')
		root.add_child(marker)
		marker.global_position = point
		markers.append(marker)
	return markers


func _add_door() -> Node3D:
	var door := door_scene.instantiate() as Node3D
	root.add_child(door)
	door.global_position = Vector3(0.0, FLOOR_Y, DOOR_Z)
	for node_name: String in ['WarningAudio', 'StrongAttackAudio']:
		var audio_player := door.get_node_or_null(node_name) as AudioStreamPlayer3D
		if audio_player:
			audio_player.stop()
			audio_player.stream = null
	return door


func _spawn_hunter(at: Vector3, overrides: Dictionary = {}) -> CharacterBody3D:
	var hunter := hunter_scene.instantiate() as CharacterBody3D
	hunter.set('entry_delay_min', 0.4)
	hunter.set('entry_delay_max', 0.4)
	for key: String in overrides:
		hunter.set(key, overrides[key])
	root.add_child(hunter)
	hunter.global_position = at
	_silence(hunter)
	# Route and door subscriptions are resolved one deferred call after _ready.
	await process_frame
	await physics_frame
	return hunter


func _spawn_player(at: Vector3) -> CharacterBody3D:
	var player := (load('res://player/player.tscn') as PackedScene).instantiate() as CharacterBody3D
	player.set('automatic_blink_enabled', false)
	root.add_child(player)
	player.global_position = at
	return player


## queue_free only takes effect at the end of the idle frame, so a bare
## `await physics_frame` would leave the previous actor in the world and the next
## one spawns embedded in it.
func _despawn(node: Node) -> void:
	node.queue_free()
	await process_frame
	await physics_frame


func _despawn_all(nodes: Array) -> void:
	for node: Node in nodes:
		await _despawn(node)


## The audio streams are irrelevant to the behaviour under test and a headless
## run has nowhere to play them.
func _silence(hunter: Node) -> void:
	for node_name: String in [
		'FootstepAudio',
		'HookAudio',
		'BreathAudio',
		'SniffAudio',
		'HornAudio',
		'SeizeAudio',
		'BreachAudio',
	]:
		var audio_player := hunter.get_node_or_null(node_name) as AudioStreamPlayer3D
		if audio_player:
			audio_player.stop()
			audio_player.stream = null


## The entry contract: it is not in the world at all until a door actually
## breaks, and then it walks in through that doorway on foot.
func _test_enters_through_a_breach() -> bool:
	var markers := _add_sweep_markers()
	var door := _add_door()
	var hunter := await _spawn_hunter(Vector3(0.0, 0.15, 20.0))

	if hunter.get('manifested'):
		return _fail('Huntsman was already in the world with every door intact.', hunter)

	door.call('take_damage', 999.0, true)
	await create_timer(0.8).timeout

	if not hunter.get('manifested'):
		return _fail('A breached door did not bring the huntsman to the doorway.', hunter)
	if hunter.global_position.z <= DOOR_Z:
		return _fail(
			'Huntsman appeared inside the house instead of outside the breach (z %.2f).'
				% hunter.global_position.z,
			hunter
		)

	await create_timer(4.0).timeout

	if not hunter.get('inside_house'):
		return _fail('Huntsman never finished walking in through the breach.', hunter)
	if hunter.global_position.z > DOOR_Z - 1.0:
		return _fail(
			'Huntsman is still in the doorway rather than in the house (z %.2f).'
				% hunter.global_position.z,
			hunter
		)

	await _despawn(hunter)
	await _despawn(door)
	await _despawn_all(markers)
	return true


## Rebuilding the door inside the entry delay is the whole reward for repairing
## fast: nothing ever comes in.
func _test_sealing_before_arrival_keeps_it_out() -> bool:
	var markers := _add_sweep_markers()
	var door := _add_door()
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 20.0),
		{'entry_delay_min': 3.0, 'entry_delay_max': 3.0}
	)

	door.call('take_damage', 999.0, true)
	await physics_frame
	door.set('repair_unlocked_after_breach', true)
	door.call('repair', 100.0)
	await create_timer(4.0).timeout

	if hunter.get('manifested') or hunter.get('inside_house'):
		return _fail('A door rebuilt before the huntsman arrived still let it in.', hunter)
	if int(hunter.get('state')) != HunterState_DORMANT:
		return _fail('Huntsman left its dormant state without a standing breach.', hunter)

	await _despawn(hunter)
	await _despawn(door)
	await _despawn_all(markers)
	return true


## The signature behaviour: it is given no noise, no sight and no target, only
## the marks a player left walking across the floor, and it has to follow them.
func _test_follows_the_trail() -> bool:
	var markers := _add_sweep_markers()
	# Lantern detection off, so nothing here can be explained by it seeing them.
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 0.0),
		{
			'entry_enabled': false,
			'lantern_range': 0.0,
			'certain_range': 0.0,
			'cast_duration': 0.2,
			'running_hearing_range': 0.0,
		}
	)
	var player := _spawn_player(Vector3(1.5, 0.9, 0.0))
	await physics_frame

	hunter.call('dev_force_spawn', null)
	var start_x: float = hunter.global_position.x
	# Lay a trail out along +x by walking the player away one step at a time. The
	# huntsman is already following it while the trail is still being laid, which
	# is exactly the intended behaviour, so travel is measured from here.
	for step: int in 18:
		player.global_position = Vector3(1.5 + step * 0.55, 0.9, 0.0)
		await create_timer(0.2).timeout

	if hunter.call('get_trail_size') <= 0:
		return _fail('No trail was recorded for a player walking around the house.', hunter)
	if not hunter.call('has_trail_lead'):
		return _fail('Huntsman could not read a fresh trail laid at its feet.', hunter)

	await create_timer(6.0).timeout
	var travelled: float = hunter.global_position.x - start_x

	if travelled < 5.0:
		return _fail(
			'Huntsman did not follow the trail: moved %.2f m along it.' % travelled,
			hunter
		)
	# Following the marks has to actually deliver it to whoever left them.
	var reached: float = hunter.global_position.distance_to(player.global_position)
	if reached > 3.5:
		return _fail(
			'Huntsman followed the trail but never closed on the player (%.2f m away).' % reached,
			hunter
		)

	await _despawn(hunter)
	await _despawn(player)
	await _despawn_all(markers)
	return true


## The failure this creature is most prone to: a mark it can smell but cannot
## walk to - one left above its head, or behind a wall it has no way through -
## used to fixate it forever, and the whole hunt ended with it standing in place.
## It has to notice it is getting nowhere, drop that mark, and carry on hunting.
func _test_unreachable_mark_does_not_freeze_it() -> bool:
	var markers := _add_sweep_markers()
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 0.0),
		{
			'entry_enabled': false,
			'lantern_range': 0.0,
			'certain_range': 0.0,
			# This isolated test deliberately makes the impossible airborne mark
			# readable. Normal gameplay keeps the close nose to the current floor.
			'nose_height_range': 5.0,
			'cast_duration': 0.2,
			'stuck_release_time': 1.0,
			'trail_point_timeout': 3.0,
		}
	)
	# Standing on nothing, four metres up: readable, and completely unreachable.
	var player := _spawn_player(Vector3(0.0, 4.0, 3.0))
	player.set_physics_process(false)
	await physics_frame

	hunter.call('dev_force_spawn', null)
	await create_timer(1.5).timeout
	if not hunter.call('has_trail_lead'):
		return _fail('Huntsman could not smell the marks it is supposed to fixate on.', hunter)

	# Long enough that a fixated huntsman would still be standing under them.
	await create_timer(8.0).timeout

	if int(hunter.get('state')) == HunterState_TRACKING and hunter.call('has_trail_lead'):
		return _fail(
			'Huntsman is still reading a mark it has had eight seconds to fail to reach.',
			hunter
		)
	if hunter.global_position.distance_to(Vector3(0.0, 0.15, 0.0)) < 1.0:
		return _fail(
			'Huntsman never moved off the spot under an unreachable mark.',
			hunter
		)

	await _despawn(hunter)
	await _despawn(player)
	await _despawn_all(markers)
	return true


## Lantern into a lock, lock into a charge, charge into a grab that kills.
func _test_lantern_lock_and_seize() -> bool:
	var markers := _add_sweep_markers()
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 0.0),
		{'entry_enabled': false, 'seize_windup': 0.2, 'spot_time_far': 0.3}
	)
	var player := _spawn_player(Vector3(0.0, 0.9, -4.0))
	await physics_frame

	hunter.call('dev_force_spawn', null)
	# Facing -Z, which is where the player is standing.
	hunter.rotation.y = 0.0

	var locked := [false]
	hunter.locked_on.connect(func(_target: Node3D) -> void: locked[0] = true)
	await create_timer(4.0).timeout

	if not locked[0]:
		return _fail('Huntsman never locked on to a player standing in its lantern.', hunter)
	if player.get('is_alive'):
		return _fail('Huntsman charged a locked player without ever seizing them.', hunter)

	await _despawn(hunter)
	await _despawn(player)
	await _despawn_all(markers)
	return true


## The shared ghost safety contract: while the door minigame owns the screen no
## hostile ghost may land an attack, and this one is no exception.
func _test_minigame_safety_blocks_the_grab() -> bool:
	var markers := _add_sweep_markers()
	var hunter := await _spawn_hunter(
		Vector3(0.0, 0.15, 0.0),
		{'entry_enabled': false, 'seize_windup': 0.2, 'spot_time_far': 0.3}
	)
	var player := _spawn_player(Vector3(0.0, 0.9, -2.5))
	await physics_frame

	hunter.call('dev_force_spawn', null)
	hunter.rotation.y = 0.0
	hunter.call('set_dev_attack_suspended', true)
	await create_timer(3.0).timeout

	if not player.get('is_alive'):
		return _fail('Huntsman killed a player while its attacks were suspended.', hunter)

	await _despawn(hunter)
	await _despawn(player)
	await _despawn_all(markers)
	return true


## The trap the whole creature is built around: repair every breach while it is
## inside and it has nowhere to go.
func _test_sealing_the_last_breach_traps_it() -> bool:
	var markers := _add_sweep_markers()
	var door := _add_door()
	var hunter := await _spawn_hunter(Vector3(0.0, 0.15, 20.0), {'entry_enabled': true})

	door.call('take_damage', 999.0, true)
	await create_timer(4.0).timeout
	if not hunter.get('inside_house'):
		return _fail('Huntsman never got inside, so it cannot be sealed in.', hunter)

	var sealed := [false]
	hunter.sealed_inside.connect(func() -> void: sealed[0] = true)
	door.set('repair_unlocked_after_breach', true)
	door.call('repair', 100.0)
	await physics_frame

	if not sealed[0]:
		return _fail('Rebuilding the last breach did not seal the huntsman in.', hunter)
	if not hunter.get('trapped'):
		return _fail('Huntsman is sealed in but does not know it.', hunter)

	hunter.call('force_leave')
	await create_timer(1.0).timeout
	if int(hunter.get('state')) == HunterState_LEAVING:
		return _fail('A sealed-in huntsman is still trying to walk out of the house.', hunter)
	if not hunter.get('inside_house'):
		return _fail('A sealed-in huntsman left the house anyway.', hunter)

	await _despawn(hunter)
	await _despawn(door)
	await _despawn_all(markers)
	return true


## With a hole still open it does leave, and leaving takes it out of the world
## entirely rather than parking it in a corner.
func _test_leaves_through_a_breach() -> bool:
	var markers := _add_sweep_markers()
	var door := _add_door()
	var hunter := await _spawn_hunter(Vector3(0.0, 0.15, 20.0))

	door.call('take_damage', 999.0, true)
	await create_timer(4.0).timeout
	if not hunter.get('inside_house'):
		return _fail('Huntsman never got inside, so it cannot walk back out.', hunter)

	var left := [false]
	hunter.left_house.connect(func(_door: Node) -> void: left[0] = true)
	hunter.call('force_leave')
	await create_timer(12.0).timeout

	if not left[0]:
		return _fail('Huntsman never finished leaving through the open breach.', hunter)
	if hunter.get('inside_house') or hunter.get('manifested'):
		return _fail('Huntsman reported leaving but is still in the world.', hunter)
	if int(hunter.get('state')) != HunterState_DORMANT:
		return _fail('Huntsman did not return to dormant after leaving.', hunter)

	# The door it walked out of is still a hole, so once the quiet between visits
	# is spent it comes back through it without needing another door to break.
	hunter.set('reentry_cooldown_min', 0.2)
	hunter.set('reentry_cooldown_max', 0.2)
	hunter.set('_reentry_cooldown', 0.2)
	await create_timer(4.0).timeout
	if not hunter.get('manifested'):
		return _fail('A breach left standing never invited the huntsman back.', hunter)

	await _despawn(hunter)
	await _despawn(door)
	await _despawn_all(markers)
	return true


func _fail(message: String, hunter: Node = null) -> bool:
	if hunter:
		push_error('%s (state %s, position %s)' % [
			message,
			hunter.get('state'),
			hunter.global_position,
		])
	else:
		push_error(message)
	quit(1)
	return false
