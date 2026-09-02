class_name NightClock
extends CanvasLayer

## The night does not run to dawn on its own. It runs on **runway** - in-game
## minutes bought by finishing objectives - and it stops dead when the runway is
## spent. Standing still is therefore not a way to survive the night; it is a way
## to make sure the night never ends.
##
## Two separate things can stop the clock, and they mean opposite things to the
## player:
##
##   OUT OF RUNWAY  nothing left to spend. Go and finish an objective.
##   FROZEN         something in the house is broken - a blackout, today - and
##                  the night refuses to pass until it is fixed. Runway is *not*
##                  spent while frozen, so an outage costs the team real time
##                  and nothing they had earned.
##
## Runway accumulates rather than resetting (20 left plus a 30-minute task is
## 50), because a reset would make waiting until empty the optimal play, which
## is exactly the idling this mechanic exists to kill. It is capped at
## `max_fuel_minutes` so a team that works ahead cannot bank the whole night in
## the first few minutes and leave itself nothing to do.
##
## `skip_minutes()` below is the older, blunter primitive and still exists: it
## jumps the night forward *now*, subject to the 4:00 AM ceiling. Runway is not
## subject to that ceiling - it could not be, or the night would be
## unfinishable - so the two must not be confused. Objectives pay through
## `add_fuel()`; only direct jumps and test setup use `skip_minutes()`.

signal minute_changed(minutes_of_day: int, formatted_time: String)
signal victory_reached()
## Runway or the freeze changed without a minute passing. Both have to reach a
## client the moment they happen: the one bug this mechanic cannot survive is a
## replica whose clock keeps running while the server's is stopped.
signal runway_changed(fuel_minutes: int, is_frozen: bool)

@export_category("Clock")
@export_range(0, 23, 1) var start_hour: int = 23
@export_range(0, 59, 1) var start_minute: int = 55
@export_range(0, 23, 1) var victory_hour: int = 6
@export_range(0, 59, 1) var victory_minute: int = 0
## Ceiling for skip_minutes(). Time granted by the totem ritual stops here:
## the night can still run past 4:00 AM on its own, but nothing can be burned
## to jump it there.
@export_range(0, 23, 1) var skip_limit_hour: int = 4
@export_range(0, 59, 1) var skip_limit_minute: int = 0
## Real seconds per in-game minute, and therefore the length of a whole match:
## 23:55 -> 06:00 is 365 in-game minutes, so 1.6575 makes a night 604.99
## real seconds - 605 to within 13 milliseconds, and 605 exactly is not on the
## table: 605/365 is 1.65753424657..., a repeating decimal no export can hold.
## Raised from 1.5 (547.5 s) to buy the extra minute back.
##
## This one number scales everything the night is measured in - a burn's runway,
## the bladder, the Huntsman's in-game hours - because those are all counted in
## game minutes. What it does *not* scale is anything counted in real seconds:
## the power reserve and the Darkness Ghost's cycle both keep their own clock,
## so lengthening the night gives the house one more chance to go dark and the
## ghost one more haunting. That asymmetry is the point of changing it here
## rather than by moving dawn.
@export var real_seconds_per_game_minute: float = 1.6575

@export_category("Runway")
## What the night opens with, so the first objective is done under a running
## clock rather than a frozen one: one objective's worth.
##
## Both this and the ceiling below are **overwritten at runtime** by
## `TotemRitual._sync_runway_pricing()`, because what an objective is worth now
## depends on how many people are in the run - three burns each, so the more
## hands there are the less one burn buys. The values authored here are the
## solo case and the fallback for a scene with no ritual in it.
@export_range(0, 240, 5) var start_fuel_minutes: int = 92
## Ceiling on banked runway, in in-game minutes. One objective per player plus
## one, so a whole team finishing a round of trips together can cash in without
## the last of them being handed nothing, and a multiple of one objective so
## that - since the night opens with one in the tank - the first completion
## fills the bank exactly rather than being clipped. It is still a round of
## work in hand and no more: four players can bank 145 of a 365-minute night.
@export_range(0, 480, 5) var max_fuel_minutes: int = 184

@export_category("Game state")
@export var player_path: NodePath = NodePath("../Player")
@export var pause_on_victory: bool = true

var running: bool = true
var won: bool = false
var current_minutes_of_day: int = 0
var elapsed_game_minutes: int = 0
## In-game minutes of night still paid for. At zero the clock stops.
var fuel_minutes: int = 0
## Something in the house is holding the night still. Derived from `_holds` on
## the authority and taken from the server on a client, so there is exactly one
## place it is decided.
var is_frozen: bool = false
var _real_time_accumulator: float = 0.0
var _minutes_until_victory: int = 0
var _player: Node
## Freeze sources, by name. Refcounting by source rather than using one bool
## matters as soon as there is more than one: a blackout and whatever comes
## after it can overlap, and whichever ends first would otherwise start the
## night running again while the other is still unresolved.
var _holds: Dictionary = {}
var _power_bound: bool = false

@onready var clock_panel: PanelContainer = $ClockPanel
@onready var time_label: Label = $ClockPanel/Margin/VBox/Time
@onready var runway_bar: ProgressBar = $ClockPanel/Margin/VBox/Runway
@onready var status_label: Label = $ClockPanel/Margin/VBox/Status
@onready var victory_overlay: ColorRect = $VictoryOverlay


func _ready() -> void:
	add_to_group(&"night_clock")
	_player = get_node_or_null(player_path)
	reset_clock()


func _process(delta: float) -> void:
	_bind_power_if_needed()
	if _player and "is_alive" in _player and not bool(_player.get("is_alive")):
		running = false
		clock_panel.visible = false
		return
	clock_panel.visible = running and not won and not _player_is_in_door_minigame()
	advance_real_seconds(delta)


## The blackout freeze, wired from this side so the power manager stays ignorant
## of the night - the same direction every other consumer of that group takes.
## Bound lazily because the manager is a sibling that may not have entered the
## tree when this node runs `_ready()`, and re-checked until it has.
func _bind_power_if_needed() -> void:
	if _power_bound:
		return
	var power := get_tree().get_first_node_in_group(&"power_manager")
	if power == null:
		return
	_power_bound = true
	if power.has_signal(&"blackout"):
		power.connect(&"blackout", _on_blackout_started)
	if power.has_signal(&"power_restored"):
		power.connect(&"power_restored", _on_power_restored)
	# It may already be dark by the time this binds.
	if "is_blackout" in power and bool(power.get("is_blackout")):
		_on_blackout_started()


func _on_blackout_started() -> void:
	hold(&"blackout")


func _on_power_restored() -> void:
	release(&"blackout")


func reset_clock() -> void:
	running = true
	won = false
	elapsed_game_minutes = 0
	fuel_minutes = start_fuel_minutes
	_holds.clear()
	is_frozen = false
	_real_time_accumulator = 0.0
	current_minutes_of_day = _clock_minutes(start_hour, start_minute)
	var target := _clock_minutes(victory_hour, victory_minute)
	_minutes_until_victory = target - current_minutes_of_day
	if _minutes_until_victory <= 0:
		_minutes_until_victory += 24 * 60
	victory_overlay.visible = false
	clock_panel.visible = true
	_update_time_label()


## The night is one clock for the whole house, so only the authority runs it.
## A client's copy is driven by apply_network_time() instead - otherwise four
## machines would each count their own 6:00 AM.
func advance_real_seconds(seconds: float) -> void:
	if not WorldNet.is_world_authority():
		return
	if not running or won or is_frozen or fuel_minutes <= 0 or seconds <= 0.0:
		# A stalled night must not bank the real seconds it spent stalled, or
		# the runway bought to end it would be eaten the instant it arrives.
		_real_time_accumulator = 0.0
		return
	_real_time_accumulator += seconds
	var tick_duration := maxf(real_seconds_per_game_minute, 0.001)
	while _real_time_accumulator >= tick_duration and not won and fuel_minutes > 0:
		_real_time_accumulator -= tick_duration
		fuel_minutes -= 1
		_advance_one_game_minute()


func get_formatted_time() -> String:
	return _format_minutes(current_minutes_of_day)


func get_minutes_remaining() -> int:
	return maxi(_minutes_until_victory - elapsed_game_minutes, 0)


## The whole night, start to dawn, in in-game minutes - not what is left of it.
## An objective that prices itself against the night needs the total, and
## deriving it from start_hour/victory_hour at the call site would mean every
## caller re-implementing the midnight rollover this already handles.
func get_total_night_minutes() -> int:
	return _minutes_until_victory


## Runway the night could still take, after the bank ceiling and the amount of
## night actually left. Banking more than there is night to spend it on is worth
## nothing, so an objective finished at 5:50 AM is handed the ten minutes that
## exist rather than its full price.
func get_fuel_headroom() -> int:
	return maxi(mini(max_fuel_minutes, get_minutes_remaining()) - fuel_minutes, 0)


## What an objective pays the night. Unlike skip_minutes() this grants *runway*
## rather than time: the minutes are played through in real time instead of
## being skipped past, and they add to whatever is left rather than replacing
## it. Returns the minutes actually taken, which is less than asked for near the
## bank ceiling and near dawn.
##
## A client is granted nothing, exactly as with skip_minutes(): the completion
## is reported to the server, which owns the one clock and sends the result back.
func add_fuel(minutes: int) -> int:
	if not WorldNet.is_world_authority():
		return 0
	if not running or won or minutes <= 0:
		return 0
	var granted := mini(minutes, get_fuel_headroom())
	if granted <= 0:
		return 0
	fuel_minutes += granted
	_update_time_label()
	runway_changed.emit(fuel_minutes, is_frozen)
	return granted


## Replaces the opening tank outright, for whichever objective prices the night
## (TotemRitual). `add_fuel()` cannot do this job: it only ever adds, so a clock
## that reset with the solo default before the ritual counted the room kept a
## tank sized for one player and handed a four-player team an hour and a half of
## night nobody burned for.
##
## Legal only while the night has not spent a minute. After that the runway is
## the team's and is added to, never overwritten - otherwise a late joiner would
## reprice the night out from under the people already playing it.
func set_opening_runway(minutes: int) -> void:
	if not WorldNet.is_world_authority() or elapsed_game_minutes != 0:
		return
	var wanted := clampi(minutes, 0, max_fuel_minutes)
	if wanted == fuel_minutes:
		return
	fuel_minutes = wanted
	_update_time_label()
	runway_changed.emit(fuel_minutes, is_frozen)


## Stops the night until `source` releases it, without spending runway. Holds
## are per-source so overlapping ones cannot cancel each other; taking one twice
## is a no-op rather than a second reference, because the callers are signals
## that may fire again for a state already held.
func hold(source: StringName) -> void:
	if not WorldNet.is_world_authority() or _holds.has(source):
		return
	_holds[source] = true
	_apply_hold_state()


func release(source: StringName) -> void:
	if not WorldNet.is_world_authority() or not _holds.has(source):
		return
	_holds.erase(source)
	_apply_hold_state()


func _apply_hold_state() -> void:
	var frozen := not _holds.is_empty()
	if frozen == is_frozen:
		return
	is_frozen = frozen
	_real_time_accumulator = 0.0
	_update_time_label()
	runway_changed.emit(fuel_minutes, is_frozen)


## In-game minutes that skip_minutes() can still hand out before the night hits
## its skip ceiling (4:00 AM by default, and never past dawn).
func get_minutes_until_skip_limit() -> int:
	var ceiling := mini(_skip_limit_elapsed(), _minutes_until_victory)
	return maxi(ceiling - elapsed_game_minutes, 0)


## Jumps the night forward by up to `minutes`, stopping dead at the skip
## ceiling, and returns how many minutes were actually granted. A 30-minute
## burn at 3:50 AM is handed 10. One at 4:00 AM is handed nothing.
## Every minute is stepped through rather than assigned, so minute_changed
## listeners see the jump the same way they see the night pass.
##
## A client is granted nothing: the burn it just made is reported to the server,
## which advances the one real clock and sends the result back. Returning 0 here
## is what stops a totem being worth thirty minutes on every machine at once.
func skip_minutes(minutes: int) -> int:
	if not WorldNet.is_world_authority():
		return 0
	if not running or won or minutes <= 0:
		return 0
	var granted := mini(minutes, get_minutes_until_skip_limit())
	for i: int in granted:
		_advance_one_game_minute()
	return granted


## Takes the server's night wholesale.
##
## The jump is assigned rather than stepped - a peer that joins at 2:00 AM would
## otherwise run a few hundred iterations of _advance_one_game_minute() before
## it could draw a frame - but minute_changed still fires once, because the
## ritual's completion check and the HUD both hang off it and a jump they never
## heard would leave them showing the old night.
func apply_network_time(
	elapsed: int,
	minutes_of_day: int,
	server_won: bool,
	server_fuel: int = -1,
	server_frozen: bool = false
) -> void:
	elapsed_game_minutes = elapsed
	current_minutes_of_day = posmod(minutes_of_day, 24 * 60)
	# Defaulted so an older two-argument caller cannot silently zero the runway;
	# only a payload that actually carries one overwrites it.
	if server_fuel >= 0:
		fuel_minutes = server_fuel
		is_frozen = server_frozen
	_real_time_accumulator = 0.0
	_update_time_label()
	minute_changed.emit(current_minutes_of_day, get_formatted_time())
	if server_won and not won:
		_reach_victory()


func _advance_one_game_minute() -> void:
	elapsed_game_minutes += 1
	current_minutes_of_day = (current_minutes_of_day + 1) % (24 * 60)
	_update_time_label()
	minute_changed.emit(current_minutes_of_day, get_formatted_time())
	if elapsed_game_minutes >= _minutes_until_victory:
		_reach_victory()


func _reach_victory() -> void:
	if won:
		return
	current_minutes_of_day = _clock_minutes(victory_hour, victory_minute)
	_update_time_label()
	running = false
	won = true
	clock_panel.visible = false
	victory_overlay.visible = true
	get_tree().call_group("hostile_ghosts", "set_dev_attack_suspended", true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	victory_reached.emit()
	if pause_on_victory:
		get_tree().paused = true


## The clock sells three states, because the player's response to each is
## different: running (nothing to say), frozen (go and fix the house) and out of
## runway (go and finish a job). A stopped clock with no explanation is the one
## outcome this must never produce.
const RUNNING_TIME_COLOR := Color(0.87, 0.93, 0.95)
const FROZEN_TIME_COLOR := Color(0.98, 0.72, 0.36)
const EMPTY_TIME_COLOR := Color(0.96, 0.44, 0.38)


func _update_time_label() -> void:
	if time_label:
		time_label.text = get_formatted_time()
	if runway_bar:
		runway_bar.max_value = maxf(float(max_fuel_minutes), 1.0)
		runway_bar.value = clampf(float(fuel_minutes), 0.0, runway_bar.max_value)
	var stalled_reason := ""
	var tint := RUNNING_TIME_COLOR
	if is_frozen:
		stalled_reason = "MẤT ĐIỆN - ĐÊM ĐỨNG YÊN"
		tint = FROZEN_TIME_COLOR
	elif fuel_minutes <= 0 and not won:
		stalled_reason = "HẾT THỜI GIAN - LÀM NHIỆM VỤ"
		tint = EMPTY_TIME_COLOR
	if status_label:
		status_label.text = stalled_reason
		status_label.visible = not stalled_reason.is_empty()
		status_label.modulate = tint
	if time_label:
		time_label.add_theme_color_override(&"font_color", tint)


func _player_is_in_door_minigame() -> bool:
	return _player != null \
		and _player.has_method("is_door_minigame_active") \
		and bool(_player.call("is_door_minigame_active"))


## The skip ceiling expressed the way elapsed_game_minutes is - minutes since
## the night started - so a ceiling after midnight compares cleanly.
func _skip_limit_elapsed() -> int:
	var delta := (
		_clock_minutes(skip_limit_hour, skip_limit_minute)
		- _clock_minutes(start_hour, start_minute)
	)
	if delta <= 0:
		delta += 24 * 60
	return delta


func _clock_minutes(hour: int, minute: int) -> int:
	return clampi(hour, 0, 23) * 60 + clampi(minute, 0, 59)


func _format_minutes(value: int) -> String:
	var normalized := posmod(value, 24 * 60)
	var hour_24 := int(normalized / 60)
	var minute := normalized % 60
	var suffix := "AM" if hour_24 < 12 else "PM"
	var hour_12 := hour_24 % 12
	if hour_12 == 0:
		hour_12 = 12
	return "%d:%02d %s" % [hour_12, minute, suffix]
