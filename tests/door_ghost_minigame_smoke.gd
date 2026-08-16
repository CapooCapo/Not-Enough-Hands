extends SceneTree


class SafetyPlayer:
	extends Node3D

	var acquired: int = 0
	var released: int = 0
	var minigame: DoorGhostMinigame

	func acquire_minigame_ghost_safety() -> void:
		acquired += 1

	func release_minigame_ghost_safety() -> void:
		released += 1

	func start_door_minigame(door: Node) -> bool:
		if not minigame or not door.has_method("begin_exorcism"):
			return false
		if not bool(door.call("begin_exorcism")):
			return false
		if minigame.start(self, door):
			return true
		door.call("cancel_exorcism")
		return false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var door_scene := load("res://door/defense_door.tscn") as PackedScene
	var minigame_scene := load("res://minigames/door_ghost_minigame.tscn") as PackedScene
	if not door_scene or not minigame_scene:
		_fail("Door ghost minigame resources could not be loaded.")
		return

	var door := door_scene.instantiate() as DefenseDoor
	root.add_child(door)
	door.set_physics_process(false)
	door.get_node("WarningAudio").stream = null
	door.get_node("StrongAttackAudio").stream = null
	door.take_damage(100.0, true)
	await physics_frame

	var player := SafetyPlayer.new()
	root.add_child(player)
	var minigame := minigame_scene.instantiate() as DoorGhostMinigame
	root.add_child(minigame)
	minigame.set_process(false)
	minigame.set_process_input(false)
	minigame.set_random_seed(7)
	player.minigame = minigame
	if not is_equal_approx(minigame.attempt_duration, 30.0) \
		or not is_equal_approx(minigame.progress_tick_interval, 0.085) \
		or not is_equal_approx(minigame.search_grace_duration, 1.25) \
		or not is_equal_approx(minigame.decay_tick_interval, 0.2) \
		or not is_equal_approx(minigame.instant_dodge_chance_start, 0.06) \
		or not is_equal_approx(minigame.instant_dodge_chance_end, 0.16):
		_fail(
			"The easier minigame balance defaults drifted: %.1fs / %.3f / %.3f / %.3f / %.3f-%.3f."
			% [
				minigame.attempt_duration,
				minigame.progress_tick_interval,
				minigame.search_grace_duration,
				minigame.decay_tick_interval,
				minigame.instant_dodge_chance_start,
				minigame.instant_dodge_chance_end,
			]
		)
		return
	minigame.instant_dodge_chance_start = 0.0
	minigame.instant_dodge_chance_end = 0.0
	if minigame.get_toggled_mouse_mode(Input.MOUSE_MODE_CAPTURED) != Input.MOUSE_MODE_VISIBLE:
		_fail("Alt mouse toggle did not release and show the cursor during the minigame.")
		return
	if minigame.get_toggled_mouse_mode(Input.MOUSE_MODE_VISIBLE) != Input.MOUSE_MODE_CAPTURED:
		_fail("Alt mouse toggle did not recapture the cursor.")
		return

	# The E interaction must open the minigame from the very first rustle, not
	# silently repel the event and reserve gameplay for an already broken door.
	door.reset_door()
	if not door.begin_targeting(true, 30.0):
		_fail("The intact door could not enter its rustling phase.")
		return
	door.interact(player)
	if not minigame.is_running() or not door.minigame_active:
		_fail("Pressing E during the rustling phase did not start the minigame.")
		return
	var durability_before_failure: float = door.current_durability
	door.apply_exorcism_failure()
	if not is_equal_approx(
		door.current_durability,
		durability_before_failure - door.minigame_failure_penalty
	):
		_fail("An early minigame failure did not give the attacker its heavy hit.")
		return
	if not door.complete_exorcism() or int(door.attack_phase) != 0: # IDLE
		_fail("Winning the intact-door minigame did not drive the attacker away.")
		return
	minigame.cancel()
	if player.acquired != 1 or player.released != 1:
		_fail("The early minigame did not balance its ghost-safety lock.")
		return

	# Reset counters so the original breached-door coverage below keeps checking
	# each acquire/release transition from a clean baseline.
	player.acquired = 0
	player.released = 0
	door.reset_door()
	door.take_damage(100.0, true)
	await physics_frame

	if not door.begin_exorcism() or not minigame.start(player, door):
		_fail("A valid breached door could not start the minigame.")
		return
	if player.acquired != 1:
		_fail("Starting the minigame did not acquire dev ghost safety.")
		return

	var position_before_dodge := minigame.ghost_center
	minigame.progress = 10.0
	minigame.debug_place_flashlight_on_face()
	minigame.debug_force_next_instant_dodge()
	minigame.debug_step_gameplay(0.01)
	if not is_equal_approx(minigame.get_hidden_progress(), 7.0):
		_fail("An instant dodge did not apply the regular three-point relocation penalty.")
		return
	if minigame.ghost_center.is_equal_approx(position_before_dodge):
		_fail("The forced instant dodge did not move the face to a new screen anchor.")
		return
	minigame.progress = 0.0
	minigame.charge_since_relocation = 0.0

	minigame.debug_place_flashlight_on_face()
	for _tick: int in 15:
		minigame.debug_step_gameplay(minigame.progress_tick_interval + 0.0001)
	if not is_equal_approx(minigame.get_hidden_progress(), 12.0):
		_fail("Fifteen charge ticks must relocate the ghost and leave 12 progress.")
		return

	minigame.debug_place_flashlight_away()
	minigame.debug_step_gameplay(minigame.search_grace_duration)
	if not is_equal_approx(minigame.get_hidden_progress(), 12.0):
		_fail("Progress decayed during the easier search grace.")
		return
	minigame.debug_step_gameplay(minigame.decay_tick_interval)
	if not is_equal_approx(minigame.get_hidden_progress(), 11.0):
		_fail("Progress did not decay by one after the search grace.")
		return

	minigame.progress = 99.0
	minigame.charge_since_relocation = 0.0
	minigame.debug_place_flashlight_on_face()
	minigame.debug_step_gameplay(minigame.progress_tick_interval_late + 0.0001)
	if not door.repair_unlocked_after_breach:
		_fail("Reaching 100 hidden progress did not unlock door repairs.")
		return
	minigame._process(1.0)
	if minigame.is_running() or player.released != 1:
		_fail("Success did not close the minigame and release ghost safety.")
		return
	if not is_equal_approx(door.repair(7.0), 7.0):
		_fail("The door could not be repaired after a successful minigame.")
		return

	door.reset_door()
	door.take_damage(100.0, true)
	await physics_frame
	if not door.begin_exorcism() or not minigame.start(player, door):
		_fail("The timeout attempt could not start.")
		return
	minigame.time_remaining = 0.01
	minigame._process(0.02)
	if not is_equal_approx(door.repair_cap, 50.0):
		_fail("Timeout did not apply the 20 HP repair-cap penalty.")
		return
	if player.released != 1:
		_fail("Ghost safety was released between a timeout and its retry.")
		return
	minigame._process(1.0)
	minigame._process(0.5)
	if not minigame.is_running() or not is_equal_approx(minigame.get_hidden_progress(), 0.0):
		_fail("Timeout did not restart a fresh 30-second attempt.")
		return
	minigame.cancel()
	if player.released != 2:
		_fail("Cancelling the retry did not release ghost safety.")
		return

	minigame.queue_free()
	player.queue_free()
	door.queue_free()
	await process_frame
	print("Door ghost minigame smoke test passed.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
