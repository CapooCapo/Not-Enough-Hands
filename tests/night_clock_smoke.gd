extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://ui/night_clock.tscn") as PackedScene
	if not packed:
		_fail("Night clock scene could not be loaded.")
		return

	var clock := packed.instantiate() as NightClock
	clock.pause_on_victory = false
	root.add_child(clock)
	clock.set_process(false)
	var tick: float = clock.real_seconds_per_game_minute
	# 605 exactly is not reachable - 605/365 repeats - so a second either way is
	# the honest tolerance for "one match is 605 seconds".
	if absf(tick * 365.0 - 605.0) > 1.0:
		_fail("A 365-minute night should run 605 real seconds, got %.1f." % (tick * 365.0))
		return
	if clock.get_formatted_time() != "11:55 PM":
		_fail("Night clock did not start at 11:55 PM.")
		return

	clock.advance_real_seconds(tick - 0.001)
	if clock.get_formatted_time() != "11:55 PM":
		_fail("The clock advanced before a whole tick had elapsed.")
		return
	clock.advance_real_seconds(0.001)
	if clock.get_formatted_time() != "11:56 PM":
		_fail("One tick did not advance exactly one game minute.")
		return

	clock.advance_real_seconds(tick * 5.0)
	if clock.get_formatted_time() != "12:01 AM":
		_fail("Clock did not roll from 11:59 PM to 12:00 AM correctly.")
		return
	clock.advance_real_seconds(tick)
	if clock.get_formatted_time() != "12:02 AM":
		_fail("12:01 AM to 12:02 AM did not take exactly one tick.")
		return

	# --- Runway ---------------------------------------------------------------
	# The night is bought, not waited out. Spend what it opened with and it stops
	# where it stands, however much real time is pumped into it afterwards.
	clock.advance_real_seconds(float(clock.fuel_minutes) * tick)
	if clock.fuel_minutes != 0:
		_fail("Running the night did not spend its runway minute for minute.")
		return
	var stalled_at := clock.get_formatted_time()
	clock.advance_real_seconds(tick * 20.0)
	if clock.get_formatted_time() != stalled_at:
		_fail("The night kept running with no runway left.")
		return

	# Grants accumulate rather than replacing: a team that works ahead has to be
	# buying a buffer, or waiting until empty becomes the optimal play.
	# Measured in thirds of the ceiling rather than in minutes: what an objective
	# pays now scales with the head count, so TotemRitual moves this ceiling to
	# match and any literal here would be describing a one-player night only.
	var step: int = maxi(clock.max_fuel_minutes / 3, 1)
	if clock.add_fuel(step) != step or clock.fuel_minutes != step:
		_fail("A first grant did not land whole.")
		return
	if clock.add_fuel(step) != step or clock.fuel_minutes != step * 2:
		_fail("Runway did not accumulate; a second grant must add, never reset.")
		return
	var to_ceiling: int = clock.max_fuel_minutes - step * 2
	if clock.add_fuel(clock.max_fuel_minutes) != to_ceiling \
			or clock.fuel_minutes != clock.max_fuel_minutes:
		_fail("Runway was allowed past its bank ceiling.")
		return
	clock.advance_real_seconds(tick)
	if clock.get_formatted_time() == stalled_at \
			or clock.fuel_minutes != clock.max_fuel_minutes - 1:
		_fail("Buying runway did not restart the night at a minute per minute.")
		return

	# A freeze is the other kind of stop, and it means the opposite thing: the
	# house is broken. It holds the night still and spends nothing, so an outage
	# costs real time and never the runway already earned.
	clock.hold(&"blackout")
	var frozen_at := clock.get_formatted_time()
	var fuel_at_freeze := clock.fuel_minutes
	clock.advance_real_seconds(tick * 10.0)
	if clock.get_formatted_time() != frozen_at:
		_fail("A frozen night still advanced.")
		return
	if clock.fuel_minutes != fuel_at_freeze:
		_fail("A freeze burned runway the team had already earned.")
		return
	clock.hold(&"second_source")
	clock.release(&"blackout")
	clock.advance_real_seconds(tick * 2.0)
	if clock.get_formatted_time() != frozen_at:
		_fail("Releasing one hold restarted the night while another still held it.")
		return
	clock.release(&"second_source")
	clock.advance_real_seconds(tick)
	if clock.get_formatted_time() == frozen_at:
		_fail("The night did not resume once the last hold was released.")
		return

	var victory_count := [0]
	clock.victory_reached.connect(func() -> void: victory_count[0] += 1)
	# Driven to dawn the way play drives it: buy runway, spend it, buy more. No
	# single grant can reach 6:00 AM, which is the point of the bank ceiling.
	var passes := 0
	while not clock.won and passes < 200:
		passes += 1
		clock.add_fuel(clock.max_fuel_minutes)
		clock.advance_real_seconds(float(maxi(clock.fuel_minutes, 1)) * tick)
	if clock.get_formatted_time() != "6:00 AM" or not clock.won:
		_fail("Night clock did not declare victory at 6:00 AM.")
		return
	if victory_count[0] != 1 or not clock.victory_overlay.visible:
		_fail("Victory signal/overlay did not fire exactly once at dawn.")
		return

	print(
		"Night clock smoke test passed: 605-second night, midnight rollover, "
		+ "runway spend/stall/accumulate/cap, freeze holds, and 6:00 AM victory."
	)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
