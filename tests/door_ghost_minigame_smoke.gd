extends SceneTree


class SafetyPlayer:
	extends Node

	var acquired: int = 0
	var released: int = 0

	func acquire_minigame_ghost_safety() -> void:
		acquired += 1

	func release_minigame_ghost_safety() -> void:
		released += 1


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
	minigame.instant_dodge_chance_start = 0.0
	minigame.instant_dodge_chance_end = 0.0
	root.add_child(minigame)
	minigame.set_process(false)
	minigame.set_process_input(false)
	minigame.set_random_seed(7)

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
		minigame.debug_step_gameplay(0.1)
	if not is_equal_approx(minigame.get_hidden_progress(), 12.0):
		_fail("Fifteen charge ticks must relocate the ghost and leave 12 progress.")
		return

	minigame.debug_place_flashlight_away()
	minigame.debug_step_gameplay(1.0)
	if not is_equal_approx(minigame.get_hidden_progress(), 12.0):
		_fail("Progress decayed during the one-second search grace.")
		return
	minigame.debug_step_gameplay(0.25)
	if not is_equal_approx(minigame.get_hidden_progress(), 11.0):
		_fail("Progress did not decay by one after the search grace.")
		return

	minigame.progress = 99.0
	minigame.charge_since_relocation = 0.0
	minigame.debug_place_flashlight_on_face()
	minigame.debug_step_gameplay(0.11)
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
		_fail("Timeout did not restart a fresh 25-second attempt.")
		return
	minigame.cancel()
	if player.released != 2:
		_fail("Cancelling the retry did not release ghost safety.")
		return

	print("Door ghost minigame smoke test passed.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
