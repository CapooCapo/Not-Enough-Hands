extends SceneTree

## Covers the totem-burning objective end to end without a map: the 4:00 AM
## ceiling still carried by the clock's raw `skip_minutes()` jump, what a burn
## actually pays now (runway, not a jump), the two-handed carry rule, and the
## burn -> fire out -> firewood -> relight loop the brazier enforces.

class EscortGhost extends Node3D:
	var hunts := 0
	var noises := 0
	func request_hunt_soon(_seconds: float) -> bool:
		hunts += 1
		return true
	func report_noise(_position: Vector3, _loudness: float, _source: Node) -> void:
		noises += 1


var _root: Node3D
var _clock: NightClock
var _brazier: TotemBrazier
var _ritual: TotemRitual
var _player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _check_clock_ceiling():
		return
	if not await _build_world():
		return
	if not _check_two_handed_carry():
		return
	if not await _check_burn_loop():
		return
	if not await _check_line_of_sight():
		return
	if not await _check_spawn_rules():
		return
	if not _check_per_player_pricing():
		return
	if not await _check_completion():
		return

	print("Totem ritual smoke passed: escort, bank gating, N+1 burns, guidance and cleanup.")
	quit()


## The clock's raw jump primitive, which burns no longer use - they pay through
## add_fuel() - but which test setup and any direct jump still do, ceiling and
## all. Nine 30-minute jumps is exactly 11:55 PM -> 4:00 AM, and the ninth is
## the one that gets clipped: 3:55 AM + 30 must land on 4:00 AM, not 4:25 AM.
func _check_clock_ceiling() -> bool:
	var clock := (load("res://ui/night_clock.tscn") as PackedScene).instantiate() as NightClock
	clock.pause_on_victory = false
	root.add_child(clock)
	clock.set_process(false)

	if clock.get_minutes_until_skip_limit() != 245:
		return _fail("11:55 PM to 4:00 AM should leave 245 skippable minutes, got %d." % clock.get_minutes_until_skip_limit())
	for i: int in 8:
		if clock.skip_minutes(30) != 30:
			return _fail("Burn %d should have granted a full 30 minutes." % (i + 1))
	if clock.get_formatted_time() != "3:55 AM":
		return _fail("Eight 30-minute burns should reach 3:55 AM, got %s." % clock.get_formatted_time())
	if clock.skip_minutes(30) != 5:
		return _fail("A burn at 3:55 AM should have been clipped to the 5 minutes left.")
	if clock.get_formatted_time() != "4:00 AM":
		return _fail("The clipped burn should land exactly on 4:00 AM, got %s." % clock.get_formatted_time())
	if clock.skip_minutes(30) != 0 or clock.get_minutes_until_skip_limit() != 0:
		return _fail("Nothing may be granted once the night is at 4:00 AM.")
	if clock.won:
		return _fail("Reaching the skip ceiling must not end the night early.")

	clock.free()
	return true


func _build_world() -> bool:
	_root = Node3D.new()
	root.add_child(_root)

	_clock = (load("res://ui/night_clock.tscn") as PackedScene).instantiate() as NightClock
	_clock.pause_on_victory = false
	_root.add_child(_clock)
	_clock.set_process(false)

	_brazier = (load("res://items/totem_brazier.tscn") as PackedScene).instantiate() as TotemBrazier
	_root.add_child(_brazier)

	_ritual = TotemRitual.new()
	# Restocking needs a map full of room markers. The burn-loop checks below hand
	# every item in by name, so this director cannot create its own population;
	# keeping the normal target also prevents its deferred burn restock from
	# treating the next test's manually created totem as surplus.
	# One fake player is in the group by now; the hard floor still keeps five.
	_ritual.firewood_in_world = 0
	_root.add_child(_ritual)
	await _ritual.begin()
	_ritual.set_process(false)

	_player = (load("res://player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_root.add_child(_player)
	_player.set_physics_process(false)

	if _brazier.is_lit != true:
		return _fail("The brazier should start the night already lit.")
	return true


func _check_two_handed_carry() -> bool:
	var totem := _spawn(&"res://items/totem.tscn")
	var firewood := _spawn(&"res://items/firewood.tscn")

	if PlayerEquipment.get_item_slot_cost(totem) != 2:
		return _fail("A totem must declare a two-slot carry cost.")
	if PlayerEquipment.get_item_slot_cost(firewood) != 1:
		return _fail("Firewood must stay a one-slot pickup.")
	if not _player.try_pick_up_item(totem):
		return _fail("A totem should be pickable with both hands free.")
	if _player.equipment.get_slot_item(0) != totem or _player.equipment.get_slot_item(1) != totem:
		return _fail("A totem should occupy both equipment slots.")
	if _player.try_pick_up_item(firewood):
		return _fail("Nothing else may be picked up while a totem fills both hands.")

	if not _player.release_held_item(totem):
		return _fail("release_held_item() should hand a carried totem back.")
	if not _player.equipment.is_slot_empty(0) or not _player.equipment.is_slot_empty(1):
		return _fail("Releasing a totem should clear both slots.")
	if not _player.try_pick_up_item(firewood):
		return _fail("Firewood should be pickable once the hands are free.")
	if not _player.equipment.is_slot_empty(1):
		return _fail("Firewood should take one slot, not both.")
	_player.release_held_item(firewood)
	firewood.queue_free()
	totem.queue_free()
	return true


func _check_burn_loop() -> bool:
	var totem := _spawn(&"res://items/totem.tscn")
	_player.try_pick_up_item(totem)
	if not _brazier.burn_totem(_player, totem):
		return _fail("Burning a totem at a lit brazier should succeed.")
	if _brazier.is_lit:
		return _fail("The fire must go out with the totem it consumed.")
	# A burn buys runway; it does not move the hands. The night advances only as
	# real time is spent against what the burn paid for, which is the whole
	# difference between this and the old skip_minutes() jump.
	if _clock.get_formatted_time() != "11:55 PM":
		return _fail("A burn moved the clock directly instead of paying runway, got %s." % _clock.get_formatted_time())
	# There is no bank ceiling any more, so a burn is worth its whole price on
	# top of whatever was already banked - never "up to the cap".
	var unit: int = _clock.get_total_night_minutes() / (_ritual.get_burns_required() + 1)
	if _clock.fuel_minutes != unit * 2:
		return _fail(
			"The opening tank plus one burn should be %d runway, got %d."
			% [unit * 2, _clock.fuel_minutes]
		)
	_clock.advance_real_seconds(30.0 * _clock.real_seconds_per_game_minute)
	if _clock.get_formatted_time() != "12:25 AM":
		return _fail("Runway bought by a burn did not run the night, got %s." % _clock.get_formatted_time())
	await process_frame

	var second := _spawn(&"res://items/totem.tscn")
	_player.try_pick_up_item(second)
	if _brazier.burn_totem(_player, second):
		return _fail("A dead fire must refuse a totem.")
	if _player.equipment.get_slot_item(0) != second:
		return _fail("A refused burn must leave the totem in the player's hands.")

	var firewood := _spawn(&"res://items/firewood.tscn")
	if _player.try_pick_up_item(firewood):
		return _fail("Firewood cannot be carried in the same trip as a totem.")
	_player.release_held_item(second)
	_player.try_pick_up_item(firewood)
	if not _brazier.relight(_player, firewood):
		return _fail("Firewood should bring the fire back.")
	if not _brazier.is_lit:
		return _fail("The brazier should be lit again after being fed firewood.")

	_player.try_pick_up_item(second)
	if not _brazier.burn_totem(_player, second):
		return _fail("The relit fire should accept the next totem.")
	# Thirty minutes were spent above, so the second burn adds a whole unit on
	# top of what was left rather than being clipped: runway accumulates, and a
	# team that burns before it is empty keeps every minute of the difference.
	if _clock.fuel_minutes != _clock.get_minutes_remaining():
		return _fail(
			"The second burn should have brought the runway to %d, got %d."
			% [unit * 3 - 30, _clock.fuel_minutes]
		)
	_clock.advance_real_seconds(30.0 * _clock.real_seconds_per_game_minute)
	if _clock.get_formatted_time() != "12:55 AM":
		return _fail("The second burn's runway should reach 12:55 AM, got %s." % _clock.get_formatted_time())
	return true


## The highlight is a "you can see it" hint, so a wall has to switch it off and
## so does simply not looking at it.
func _check_line_of_sight() -> bool:
	var camera := Camera3D.new()
	_root.add_child(camera)
	camera.global_position = Vector3(0, 1.6, 0)
	camera.look_at(Vector3(0, 1.6, -6), Vector3.UP)
	camera.current = true

	var totem := _spawn(&"res://items/totem.tscn")
	totem.global_position = Vector3(0, 1.4, -4)
	await physics_frame
	if not totem.is_seen_by_camera():
		return _fail("A totem in the open, in front of the camera, should be seen.")

	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.4)
	shape.shape = box
	wall.add_child(shape)
	_root.add_child(wall)
	wall.global_position = Vector3(0, 1.6, -2)
	await physics_frame
	if totem.is_seen_by_camera():
		return _fail("A wall between the camera and a totem must switch the highlight off.")

	wall.queue_free()
	totem.global_position = Vector3(0, 1.4, 4)
	await physics_frame
	if totem.is_seen_by_camera():
		return _fail("A totem behind the camera is out of frustum and must not glow.")

	totem.queue_free()
	camera.queue_free()
	return true


## Restocking on a stage of its own: two rooms, one under the players' feet and
## one 120 m away, so "at least 70 m from everybody" has exactly one answer.
func _check_spawn_rules() -> bool:
	_player.free()
	await process_frame
	var stage := Node3D.new()
	root.add_child(stage)
	_fake_room(stage, Vector3.ZERO)
	var far_room := _fake_room(stage, Vector3(120, 0, 0))
	var player := _fake_player(stage, Vector3(2, 0, 0))
	var director := TotemRitual.new()
	stage.add_child(director)
	await director.begin()
	director.set_process(false)
	if not get_nodes_in_group(&"totems").is_empty():
		return _fail("A funded bank must not spawn a totem.")
	_clock.fuel_minutes = 0
	director.restock()
	var totems := get_nodes_in_group(&"totems")
	if totems.size() != 1:
		return _fail("An empty bank must spawn exactly one totem.")
	var totem := totems[0] as Node3D
	if totem.global_position.distance_to(far_room.global_position) > 3.0:
		return _fail("The objective must use the farthest room.")
	director._update_objective_markers()
	if not totem.is_guidance_highlight_active() or director._markers.size() != 2:
		return _fail("Both objective and brazier need through-wall guidance.")
	var ghost := EscortGhost.new()
	stage.add_child(ghost)
	ghost.add_to_group(&"hostile_ghosts")
	totem.reparent(player)
	director._update_escort(0.1)
	if ghost.hunts != 1 or ghost.noises != 1:
		return _fail("Picking up the totem must shorten hunts and attract listening ghosts.")
	director.restock()
	if not director.escort_active or get_nodes_in_group(&"totems").size() != 1:
		return _fail("Pickup must escalate the escort without spawning another totem.")
	totem.reparent(stage)
	director._update_escort(0.1)
	if not director.escort_active:
		return _fail("Dropping the totem must not cancel escort pressure.")
	totem.queue_free()
	director.on_totem_burned()
	await process_frame
	director.restock()
	director._update_objective_markers()
	if not director._markers.is_empty():
		return _fail("Burned objectives must clear both route markers.")
	if director.escort_active or not get_nodes_in_group(&"totems").is_empty():
		return _fail("Burning must end pressure and wait for the bank to empty.")
	_clock.fuel_minutes = 0
	director.restock()
	if get_nodes_in_group(&"totems").size() != 1:
		return _fail("The next empty bank must release one objective.")
	director._clear_remaining_items()
	stage.queue_free()
	await process_frame
	return true


func _fake_room(stage: Node3D, point: Vector3) -> Marker3D:
	var room := Marker3D.new()
	room.add_to_group(&"house2_rooms")
	room.set_meta(&"room_size", Vector3(4, 3, 4))
	stage.add_child(room)
	room.global_position = point
	return room


## Run a complete funded night at every supported lobby size.
func _check_per_player_pricing() -> bool:
	for heads: int in [1, 2, 3, 4]:
		var stage := Node3D.new()
		root.add_child(stage)
		for i: int in heads:
			_fake_player(stage, Vector3(i, 0, 0))
		var ritual := TotemRitual.new()
		stage.add_child(ritual)
		ritual.set_process(false)
		var clock := (load("res://ui/night_clock.tscn") as PackedScene).instantiate() as NightClock
		clock.pause_on_victory = false
		stage.add_child(clock)
		clock.set_process(false)
		ritual._clock = clock
		ritual._burns_required = ritual._head_count() + 1
		if ritual.get_burns_required() != heads + 1:
			return _fail("Quota must be N + 1.")
		ritual._sync_runway_pricing()
		# A death cannot lower the already committed quota.
		stage.get_child(0).remove_from_group(&"players")
		if ritual.get_burns_required() != heads + 1:
			return _fail("The quota changed after losing a player.")
		clock.advance_real_seconds(clock.fuel_minutes * clock.real_seconds_per_game_minute)
		for burn: int in heads + 1:
			if clock.won or ritual.on_totem_burned() <= 0:
				return _fail("Every owed burn must be needed and buy time.")
			clock.advance_real_seconds(clock.fuel_minutes * clock.real_seconds_per_game_minute)
		if not clock.won or ritual.on_totem_burned() != 0:
			return _fail("Exactly N + 1 burns must pay through dawn.")
		stage.free()
	return true


func _fake_player(stage: Node3D, point: Vector3) -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.add_to_group(&"players")
	stage.add_child(player)
	player.global_position = point
	return player


## The ritual now ends with the night, not at the old 4:00 AM ceiling: it is what
## reaches dawn, so a finish line short of dawn would strand the run. The ceiling
## is lifted here only to drive the clock there in one jump.
func _check_completion() -> bool:
	var leftover := _spawn(&"res://items/totem.tscn")
	_clock.skip_limit_hour = 6
	_clock.skip_limit_minute = 0
	_clock.skip_minutes(600)
	if _clock.get_formatted_time() != "6:00 AM":
		return _fail("The night should have run out at 6:00 AM, got %s." % _clock.get_formatted_time())
	if _ritual.is_complete != true:
		return _fail("The ritual should have completed when the night reached dawn.")
	await process_frame
	if is_instance_valid(leftover):
		return _fail("Totems left in the world should be cleared once the ritual is over.")
	# process_frame fires just *before* the nodes tick, so the brazier needs one
	# more frame to have rewritten its prompt.
	await process_frame
	if _brazier.interactable.prompt_text != "NGHI LỄ ĐÃ HOÀN TẤT":
		return _fail("A finished ritual should say so on the brazier prompt, got %s." % _brazier.interactable.prompt_text)
	return true


func _spawn(path: StringName) -> Node3D:
	var item := (load(path) as PackedScene).instantiate() as Node3D
	_root.add_child(item)
	item.set_process(false)
	return item


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
