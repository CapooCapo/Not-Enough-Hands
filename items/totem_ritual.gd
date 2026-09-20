class_name TotemRitual
extends Node

## One shared escort objective. A new totem appears only with an empty bank.
## The starting team owes N + 1 burns; deaths do not discount the objective.
## Burns buy playable night minutes, never a time skip.

signal totem_burned(granted_minutes: int)
signal ritual_completed()

const TOTEM_SCENE: PackedScene = preload("res://items/totem.tscn")
const FIREWOOD_SCENE: PackedScene = preload("res://items/firewood.tscn")
const BATTERY_SCENE: PackedScene = preload("res://items/flashlight_battery.tscn")
const BRAZIER_SCENE: PackedScene = preload("res://items/totem_brazier.tscn")
## Logs kept in the world at once, as a flat count rather than one per player.
## The fire needs one after every burn, so a log has to be findable from
## wherever the last totem left you rather than being a second search on top of
## the first. Nine keeps several options available across the Villa's 80 x 60 m
## and three storeys. It never drops below the per-player count either.
@export_range(0, 16, 1) var firewood_in_world: int = 9
## Spare torch batteries loose in the house. Not part of the ritual at all -
## they live here because this node is already the thing that keeps a live item
## population spread over both maps' room markers, and a second director would
## be the same eighty lines of room-picking written twice.
##
## Deliberately the easiest population of the three to find. A totem is the
## objective and is *meant* to be a trip; a battery is what lets you see on the
## way there, so hiding it makes the trip worse rather than harder in any way
## worth having. It gets the near slice of the rooms and almost no exclusion
## radius - see `battery_spawn_distance`.
@export_range(0, 16, 1) var batteries_in_world: int = 9
## Exclusion radius for batteries alone, and it exists only so one does not pop
## into existence in the room you are standing in. Everything past it is fair
## game, near slice included, which is the whole difference between this and the
## totems' 22 m.
@export_range(0.0, 60.0, 0.5) var battery_spawn_distance: float = 6.0

@export_category("Totem guidance")
## Duration for explicit guidance requests (normal objective markers persist).
@export_range(1.0, 60.0, 1.0) var totem_hint_duration: float = 12.0
## Objective placement uses the farthest rooms from both team and brazier.
@export_range(0.0, 200.0, 1.0) var min_spawn_distance: float = 40.0
@export_range(0.1, 1.0, 0.05) var near_room_fraction: float = 0.4
@export_range(1.0, 60.0, 1.0) var escort_pressure_interval: float = 12.0

## Marker group the drop points come from. Both maps publish their rooms into
## `house2_rooms`; the villa adds its own markers to it as well.
@export var spawn_room_group: StringName = &"house2_rooms"
## Seconds between restock passes. Items are replaced on a timer rather than the
## instant one is consumed, because a legal drop point may not exist yet: with
## everybody spread out the pass simply finds nothing and tries again.
@export_range(0.25, 10.0, 0.25) var restock_interval: float = 2.0
## Items drop from this height and settle under gravity, which keeps them on
## top of whatever furniture is really there instead of inside it.
@export_range(0.1, 3.0, 0.05) var spawn_drop_height: float = 0.9
## Fraction of a room's half-size the drop point is nudged off centre, so a
## totem does not land on the dining table every single time. Only reached in
## full where a room publishes no cleared tile - see `CLEAR_TILE_RADIUS`.
@export_range(0.0, 0.9, 0.05) var spawn_room_spread: float = 0.34

## Half-width, in metres, of the tile a `clear_point` marks. That point is the
## one tile of the room the map's own furniture pass left empty, so the nudge
## above has to stay inside it. Measured against the whole room instead, it moved
## a log up to two metres sideways into the very wardrobe the cleared tile
## existed to avoid, and the trip back for firewood became a search of the
## furniture rather than of the house.
const CLEAR_TILE_RADIUS := 0.7

var is_complete: bool = false
var totems_burned: int = 0

var _clock: Node = null
var _rng := RandomNumberGenerator.new()
var _restock_timer: float = 0.0
var _last_hinted_totem_path := NodePath()
var _started: bool = false
var _initialized: bool = false
var _burns_required: int = 0
var escort_active: bool = false
var _pressure_timer: float = 0.0
var _markers: Dictionary = {}


func _ready() -> void:
	add_to_group(&"totem_ritual")
	_rng.randomize()
	# The map generates its colliders in its own _ready(), which runs after
	# every child's - dropped items would fall through a floor that does not
	# exist yet, so the first restock waits for the first physics step.
	begin.call_deferred()


## Idempotent: the smoke test calls it directly, `_ready()` defers into it once.
func begin() -> void:
	if _started:
		return
	_started = true
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_clock = get_tree().get_first_node_in_group(&"night_clock")
	if _clock and _clock.has_signal(&"minute_changed"):
		_clock.connect(&"minute_changed", _on_minute_changed)
	_burns_required = _head_count() + 1
	_sync_runway_pricing()
	_ensure_brazier()
	_initialized = true
	restock()
	_check_completion()


func _process(delta: float) -> void:
	if is_complete or not _initialized:
		return
	_restock_timer -= delta
	if _restock_timer <= 0.0:
		_restock_timer = restock_interval
		restock()
	_update_objective_markers()
	if WorldNet.is_world_authority():
		_update_escort(delta)


## Authority chooses the destination once; clients only render that choice.
## The runtime item names are shared by WorldReplicator, so a scene-relative
## NodePath identifies the same spawned totem on every peer.
func _trigger_next_totem_hint() -> bool:
	if not WorldNet.is_world_authority():
		return false
	var candidates: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"totems"):
		var totem := node as Node3D
		if totem and not totem.is_queued_for_deletion() and _is_loose(totem) \
				and totem.has_method(&"show_guidance_highlight"):
			candidates.append(totem)
	if candidates.is_empty():
		return false
	if candidates.size() > 1 and not _last_hinted_totem_path.is_empty():
		var previous := get_node_or_null(_last_hinted_totem_path) as Node3D
		if previous in candidates:
			candidates.erase(previous)
	var selected := candidates[_rng.randi_range(0, candidates.size() - 1)]
	var selected_path := get_path_to(selected)
	_last_hinted_totem_path = selected_path
	_apply_totem_hint(selected_path, totem_hint_duration)
	if _network_session_active():
		_apply_totem_hint.rpc(selected_path, totem_hint_duration)
	return true


@rpc("authority", "call_remote", "reliable")
func _apply_totem_hint(totem_path: NodePath, duration: float) -> void:
	# Clear the prior beacon first so packet retries or a very short configured
	# interval can never leave two timed objective markers active together.
	for node: Node in get_tree().get_nodes_in_group(&"totems"):
		if node.has_method(&"clear_guidance_highlight"):
			node.call(&"clear_guidance_highlight")
	var selected := get_node_or_null(totem_path)
	if selected and selected.has_method(&"show_guidance_highlight"):
		selected.call(&"show_guidance_highlight", duration)


func _network_session_active() -> bool:
	var manager := get_node_or_null("/root/NetworkManager")
	return manager != null and bool(manager.get("session_active"))


## Called by the brazier once a totem has actually gone into the fire. Returns
## the in-game minutes the burn was really worth, which is less than
## `get_minutes_per_totem()` near the runway ceiling and near dawn.
##
## This is the night's first objective, and it pays the clock the way every
## later one will: `add_fuel()`, not `skip_minutes()`. The difference is the
## whole design - a burn buys minutes the team then *plays through* while the
## clock runs, rather than deleting them with a jump.
func on_totem_burned() -> int:
	if not WorldNet.is_world_authority() or is_complete or totems_burned >= get_burns_required():
		return 0
	escort_active = false
	var granted := 0
	if _clock and _clock.has_method(&"add_fuel"):
		granted = int(_clock.call(&"add_fuel", get_minutes_per_totem()))
	totems_burned += 1
	totem_burned.emit(granted)
	_check_completion()
	if not is_complete:
		# The brazier queued the consumed item for deletion just before this call.
		# Deferring lets that item leave its group before the replacement count is
		# measured, while the regular timer remains a fallback if no room is legal.
		restock.call_deferred()
	return granted


func totems_remaining() -> int:
	return get_tree().get_nodes_in_group(&"totems").size()


## Lock the quota at begin so deaths/disconnects cannot remove owed burns.
func get_burns_required() -> int:
	return _burns_required if _burns_required > 0 else _head_count() + 1


func _head_count() -> int:
	# The roster exists before remote player replicas finish loading.
	if _network_session_active():
		var manager := get_node("/root/NetworkManager")
		return maxi((manager.get("players") as Dictionary).size(), 1)
	return maxi(_players_in_run().size(), 1)


func get_totems_in_world() -> int:
	return 1


func get_minutes_per_totem() -> int:
	# The final payment absorbs integer rounding, ensuring exactly N + 1 burns.
	var unit := maxi(_total_night_minutes() / (get_burns_required() + 1), 1)
	if totems_burned == get_burns_required() - 1 and _clock:
		return maxi(int(_clock.call(&"get_minutes_remaining")) - int(_clock.get("fuel_minutes")), 0)
	return unit


func _total_night_minutes() -> int:
	if _clock and _clock.has_method(&"get_total_night_minutes"):
		return maxi(int(_clock.call(&"get_total_night_minutes")), 1)
	# 23:55 -> 06:00. Only reached with no clock in the scene, which is a test
	# harness rather than a run.
	return 365


## Configure the opening bank once, before any objective is consumed.
func _sync_runway_pricing() -> void:
	if not WorldNet.is_world_authority() or _clock == null or not "max_fuel_minutes" in _clock:
		return
	var unit := get_minutes_per_totem()
	_clock.set("max_fuel_minutes", _total_night_minutes())
	_clock.set("start_fuel_minutes", unit)
	# The clock reset itself before this node ran, so the tank it opened with is
	# the authored solo default whatever the room actually holds. Setting it
	# rather than topping it up is the whole point: for two players or more the
	# authored tank is too *large*, and a night that opens over-fuelled is a
	# night finished in fewer burns than the team owes.
	if _clock.has_method(&"set_opening_runway"):
		_clock.call(&"set_opening_runway", unit)


## Only the authority creates replicated items. Carried totems still count.
func restock() -> void:
	if is_complete or not WorldNet.is_world_authority():
		return
	if totems_burned < get_burns_required() and (_clock == null or int(_clock.get("fuel_minutes")) <= 0):
		_restock_group(TOTEM_SCENE, &"totems", 1)
	if _network_session_active():
		_sync_objective.rpc(get_burns_required(), totems_burned, escort_active)
	_restock_group(
		FIREWOOD_SCENE,
		&"fire_fuel",
		maxi(firewood_in_world, _players_in_run().size()),
		false
	)
	_restock_group(
		BATTERY_SCENE,
		&"flashlight_batteries",
		maxi(batteries_in_world, _players_in_run().size()),
		true,
		battery_spawn_distance
	)


## Carried items count towards the population: picking a totem up is not what
## releases another objective; the next empty bank does.
func _restock_group(
	scene: PackedScene,
	group: StringName,
	target: int,
	cluster_near: bool = true,
	exclusion_radius: float = -1.0
) -> void:
	var existing: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(group):
		if not node.is_queued_for_deletion():
			existing.append(node)
	var used: Array[Node3D] = []
	for i: int in maxi(target - existing.size(), 0):
		var room := _pick_objective_room() if group == &"totems" else _pick_far_room(used, cluster_near, exclusion_radius)
		if room == null:
			return
		used.append(room)
		_drop_item(scene, room)
	# A player dropping out of the run lowers the target. Only items nobody is
	# carrying are taken back - never one out of somebody's hands.
	var surplus := existing.size() - target
	for node: Node in existing:
		if surplus <= 0:
			break
		var item := node as Node3D
		if item and _is_loose(item):
			item.queue_free()
			surplus -= 1


## The spawn rule, in two steps: throw out every room inside the exclusion
## radius, then pick at random among the *nearest* `near_room_fraction` of what
## is left, preferring one `exclude` does not already name. Both halves matter -
## the first is what stops an item landing underfoot, the second is what stops
## the trip being a sweep of the whole villa.
##
## `exclusion_radius` defaults to `min_spawn_distance`; a population that is not
## the objective passes its own, much smaller one. How hard something is to find
## is a property of that item, not of the picker.
func _pick_far_room(
	exclude: Array[Node3D] = [],
	cluster_near: bool = true,
	exclusion_radius: float = -1.0
) -> Node3D:
	var radius := min_spawn_distance if exclusion_radius < 0.0 else exclusion_radius
	var players := _players_in_run()
	var qualifying: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for room: Node3D in _spawn_rooms():
		var distance := _distance_to_nearest(_room_floor_point(room), players)
		if distance >= radius:
			qualifying.append({"room": room, "distance": distance})
		else:
			rest.append({"room": room, "distance": distance})
	if not qualifying.is_empty():
		var pool: Array[Node3D] = []
		if cluster_near:
			qualifying.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a["distance"]) < float(b["distance"])
			)
			var take := maxi(1, int(ceil(float(qualifying.size()) * near_room_fraction)))
			qualifying = qualifying.slice(0, take)
		for entry: Dictionary in qualifying:
			pool.append(entry["room"] as Node3D)
		return _random_room(_prefer_unused(pool, exclude))
	if rest.is_empty():
		return null
	# Nothing on this map is far enough from everybody, so the rule degrades to
	# the farthest quarter of the rooms rather than to one fixed room: still as
	# far away as this map gets, still somewhere different every time.
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) > float(b["distance"])
	)
	var farthest: Array[Node3D] = []
	for entry: Dictionary in rest.slice(0, maxi(1, rest.size() / 4)):
		farthest.append(entry["room"] as Node3D)
	return _random_room(_prefer_unused(farthest, exclude))


## Spreading one pass over as many rooms as it has items is a preference, never
## a rule: the distance rule above has already decided which rooms are legal, and
## a second log in the only legal room still beats no second log at all.
func _prefer_unused(rooms: Array[Node3D], exclude: Array[Node3D]) -> Array[Node3D]:
	var fresh: Array[Node3D] = []
	for room: Node3D in rooms:
		if not exclude.has(room):
			fresh.append(room)
	return fresh if not fresh.is_empty() else rooms


func _random_room(rooms: Array[Node3D]) -> Node3D:
	if rooms.is_empty():
		return null
	return rooms[_rng.randi_range(0, rooms.size() - 1)]


func _distance_to_nearest(point: Vector3, players: Array[Node3D]) -> float:
	var nearest := INF
	for player: Node3D in players:
		nearest = minf(nearest, point.distance_to(player.global_position))
	return nearest


## Everyone still in the run. Spectators are out; a downed player is only down,
## and their totem should still be waiting when a teammate lifts them.
func _players_in_run() -> Array[Node3D]:
	var players: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player == null:
			continue
		if "is_spectator" in player and bool(player.get("is_spectator")):
			continue
		var alive: bool = bool(player.get("is_alive")) if "is_alive" in player else true
		var downed: bool = bool(player.get("is_downed")) if "is_downed" in player else false
		if alive or downed:
			players.append(player)
	return players


func _is_loose(item: Node3D) -> bool:
	var parent := item.get_parent()
	return parent != null and not parent.is_in_group(&"players")


func _on_minute_changed(_minutes_of_day: int, _formatted: String) -> void:
	_check_completion()


## The ritual now ends only when the night does. It used to close at the 4:00 AM
## skip ceiling, which made sense while burning was an optional shortcut - there
## was nothing left to buy. As the night's objective it is what *reaches* dawn,
## so a ceiling short of dawn would strand the run with no way to finish it.
func _check_completion() -> void:
	if is_complete or _clock == null or not _clock.has_method(&"get_minutes_remaining"):
		return
	if int(_clock.call(&"get_minutes_remaining")) > 0:
		return
	is_complete = true
	for marker: Label3D in _markers.values():
		marker.queue_free()
	_markers.clear()
	# The sweep is a despawn like any other: the authority frees the items and
	# every client is told. A client doing it itself would race the packet.
	if WorldNet.is_world_authority():
		_clear_remaining_items()
	ritual_completed.emit()


func _clear_remaining_items() -> void:
	var players := get_tree().get_nodes_in_group(&"players")
	for group: StringName in [&"totems", &"fire_fuel", &"flashlight_batteries"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var item := node as Node3D
			if item == null:
				continue
			for player: Node in players:
				if player.has_method(&"release_held_item"):
					player.call(&"release_held_item", item)
			item.queue_free()


func _ensure_brazier() -> void:
	if get_tree().get_first_node_in_group(&"totem_braziers"):
		return
	# Replicated rather than instanced on each peer: the position is derived
	# from where the players happen to be standing, so two peers computing it
	# independently can put the ritual site in two different rooms.
	WorldNet.spawn(BRAZIER_SCENE, get_parent(), _fallback_brazier_position(), 0.0, "RitualBrazier")


## Only used by a map that did not place a brazier itself. Unlike the items, the
## fire is meant to be found immediately: it goes in the room nearest to where
## the players start, so the ritual site is somewhere they walk past rather than
## somewhere they have to be told about.
func _fallback_brazier_position() -> Vector3:
	var anchor := get_tree().get_first_node_in_group(&"players") as Node3D
	var origin := anchor.global_position if anchor else Vector3.ZERO
	var best: Vector3 = origin
	var best_distance := INF
	for room: Node3D in _spawn_rooms():
		var point := _room_floor_point(room)
		if absf(point.y - origin.y) > 2.0:
			continue
		var distance := Vector2(point.x - origin.x, point.z - origin.z).length()
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


func _drop_item(scene: PackedScene, room: Node3D) -> void:
	var extent := Vector3(2.0, 0.0, 2.0)
	if room.has_meta(&"room_size"):
		extent = room.get_meta(&"room_size") as Vector3
	var spread_x := extent.x * 0.5 * spawn_room_spread
	var spread_z := extent.z * 0.5 * spawn_room_spread
	if room.has_meta(&"clear_point"):
		spread_x = minf(spread_x, CLEAR_TILE_RADIUS)
		spread_z = minf(spread_z, CLEAR_TILE_RADIUS)
	var drop_position := _room_floor_point(room) + Vector3(
		_rng.randf_range(-1.0, 1.0) * spread_x,
		spawn_drop_height,
		_rng.randf_range(-1.0, 1.0) * spread_z
	)
	var item := WorldNet.spawn(
		scene,
		get_parent(),
		drop_position,
		_rng.randf_range(0.0, TAU)
	) as Node3D
	if item == null:
		return
	# Unfrozen on purpose - a PickupItem sits frozen in the world, but these are
	# dropped in blind, so gravity is what settles them onto the real floor.
	# On a client the replicator freezes it again: there it only ever follows.
	if item is RigidBody3D:
		(item as RigidBody3D).freeze = false


func _spawn_rooms() -> Array[Node3D]:
	var rooms: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(spawn_room_group):
		var marker := node as Node3D
		if marker:
			rooms.append(marker)
	return rooms


## The villa tags each room marker with a cell its own furniture pass left
## empty; it is stored in the same local space as the marker, so it has to go
## through the marker's parent to come out as a world point.
func _room_floor_point(room: Node3D) -> Vector3:
	var parent := room.get_parent_node_3d()
	if room.has_meta(&"clear_point") and parent:
		return parent.to_global(room.get_meta(&"clear_point") as Vector3)
	return room.global_position


func _pick_objective_room() -> Node3D:
	var anchors := _players_in_run()
	for node: Node in get_tree().get_nodes_in_group(&"totem_braziers"):
		if node is Node3D:
			anchors.append(node)
	var rooms := _spawn_rooms()
	rooms.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _distance_to_nearest(_room_floor_point(a), anchors) > _distance_to_nearest(_room_floor_point(b), anchors)
	)
	# Cleared room tiles remain reachable; distance never bypasses map geometry.
	return _random_room(rooms.slice(0, maxi(1, int(ceil(rooms.size() * 0.15)))))


@rpc("authority", "call_remote", "reliable")
func _sync_objective(required: int, burned: int, escort: bool) -> void:
	_burns_required = required
	totems_burned = burned
	escort_active = escort


func _update_escort(delta: float) -> void:
	var objective: Node3D = null
	for node: Node in get_tree().get_nodes_in_group(&"totems"):
		if node is Node3D and not node.is_queued_for_deletion():
			objective = node
			if not _is_loose(objective):
				escort_active = true
	if not escort_active or objective == null:
		_pressure_timer = 0.0
		return
	_pressure_timer -= delta
	if _pressure_timer > 0.0:
		return
	_pressure_timer = escort_pressure_interval
	for ghost: Node in get_tree().get_nodes_in_group(&"hostile_ghosts"):
		if ghost.has_method(&"request_hunt_soon"):
			ghost.call(&"request_hunt_soon", 3.0)
		if ghost.has_method(&"report_noise"):
			ghost.call(&"report_noise", _objective_position(objective), 1.0, objective.get_parent())


## Local presentation follows replicated item transforms, including the carrier.
## Separate labels remain visible even when a held pickup hides its own meshes.
func _update_objective_markers() -> void:
	var targets: Array[Node] = get_tree().get_nodes_in_group(&"totems")
	var show_route := not targets.is_empty()
	if show_route:
		targets.append_array(get_tree().get_nodes_in_group(&"totem_braziers"))
	for target in _markers.keys():
		if not is_instance_valid(target) or target not in targets or target.is_queued_for_deletion():
			_markers[target].queue_free()
			_markers.erase(target)
	for target: Node3D in targets:
		if target.is_queued_for_deletion():
			continue
		if not _markers.has(target):
			var marker := Label3D.new()
			marker.no_depth_test = true
			marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			marker.fixed_size = true
			marker.font_size = 28
			marker.modulate = Color(1.0, 0.7, 0.25)
			add_child(marker)
			_markers[target] = marker
		var label: Label3D = _markers[target]
		label.global_position = _objective_position(target) + Vector3.UP * 1.8
		label.text = "TOTEM — HỘ TỐNG" if target.is_in_group(&"totems") else "LÒ ĐỐT  %d/%d" % [totems_burned, get_burns_required()]
		if target.has_method(&"show_guidance_highlight"):
			target.call(&"show_guidance_highlight", 1.0)


func _objective_position(item: Node3D) -> Vector3:
	var holder := item.get_parent() as Node3D
	return holder.global_position if holder and holder.is_in_group(&"players") else item.global_position
