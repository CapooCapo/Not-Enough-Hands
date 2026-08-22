extends SceneTree

## Toilet + bathroom minigame smoke test for the ported (from
## feat/game-character-hoang) nozzle-balance minigame. ToiletMinigame is now
## owned per-toilet (a child of TestToilet), not per-player, so it's fetched
## via toilet.get_node("ToiletMinigame") rather than a fixed player property.
## Interaction goes through the real pipeline (raycast ->
## get_interaction_target -> Interactable -> interact() -> Toilet ->
## Player.start_toilet_minigame); the balance/drain step is driven
## deterministically by calling the minigame's own per-frame helper
## functions directly (with oscillation zeroed out) instead of waiting on
## real oscillation timing. succeed()/cancel() use real Godot timers
## internally, so this test does actually wait on them (~1-2s of wall time).

const STEP_DELTA := 0.05


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://tests/player_test.tscn") as PackedScene
	var test_scene := packed_scene.instantiate()
	root.add_child(test_scene)

	var player := test_scene.get_node("Player") as CharacterBody3D
	var toilet := test_scene.get_node("TestToilet")
	var minigame: Node = toilet.get_node("ToiletMinigame")

	var player_scene := load("res://player/player.tscn") as PackedScene
	var player_b := player_scene.instantiate()
	root.add_child(player_b)
	player_b.global_position = Vector3(50.0, 1.0, 50.0)
	player_b.bladder.bladder_fill_rate = 0.0
	player.bladder.bladder_fill_rate = 0.0

	player.global_position = Vector3(12.0, 1.0, 2.0)
	player.global_rotation = Vector3.ZERO
	toilet.global_position = Vector3(12.0, 1.22, 0.5)

	# Zero oscillation for deterministic driving: with no player input and
	# no automatic sway, the nozzle settles dead-center (the safe zone) and
	# stays there, so bladder-drain progress is driven purely by elapsed
	# calls, not by chasing a moving target.
	minigame.oscillation_amplitude = 0.0

	await physics_frame
	await physics_frame

	# --- Toilet interaction: prompt exists, E starts the minigame. ---
	var target: Node = player.call("get_interaction_target")
	if target != toilet.get_node("Interactable"):
		push_error("Player did not target the Toilet's Interactable.")
		quit(1)
		return
	var prompt_before: String = toilet.get_node("Interactable").get_interaction_prompt("E")
	if not prompt_before.contains("DÙNG BỒN CẦU"):
		push_error("Toilet prompt text was not the expected 'use toilet' prompt.")
		quit(1)
		return

	player.bladder.current_value = 30.0
	player_b.bladder.current_value = 42.0
	player.call("_try_interact")
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("Interacting with the toilet did not start the minigame (state=%s)." % minigame.current_state)
		quit(1)
		return
	if not player.is_toilet_minigame_active():
		push_error("Player.is_toilet_minigame_active() should be true once the minigame starts.")
		quit(1)
		return
	if not player_b.bladder: # sanity: player_b has its own independent component
		push_error("player_b unexpectedly has no bladder.")
		quit(1)
		return
	if player_b.is_toilet_minigame_active():
		push_error("player_b incorrectly inherited the toilet minigame state.")
		quit(1)
		return

	# --- Nozzle oscillates automatically (re-enable briefly to check). ---
	minigame.oscillation_amplitude = 0.08
	minigame.asset_anchor.position.x = 0.0
	minigame.time_passed = 0.0
	for i in 10:
		minigame._update_visuals(STEP_DELTA)
	if is_equal_approx(minigame.asset_anchor.position.x, 0.0):
		push_error("Nozzle did not oscillate with oscillation_amplitude > 0.")
		quit(1)
		return
	minigame.oscillation_amplitude = 0.0 # back to deterministic for the rest of the test

	# --- A/D controls the nozzle (real Input actions, not a fake parameter). ---
	minigame.player_offset = 0.0
	Input.action_press("move_right")
	for i in 10:
		minigame._handle_input(STEP_DELTA)
	Input.action_release("move_right")
	if minigame.player_offset <= 0.0:
		push_error("Holding move_right (D) did not move the nozzle offset positive.")
		quit(1)
		return
	var offset_after_d: float = minigame.player_offset
	Input.action_press("move_left")
	for i in 20:
		minigame._handle_input(STEP_DELTA)
	Input.action_release("move_left")
	if minigame.player_offset >= offset_after_d:
		push_error("Holding move_left (A) did not move the nozzle offset back down.")
		quit(1)
		return
	minigame.player_offset = 0.0 # reset for the deterministic success drive below

	# --- Repeated interact while active must not create a second session. ---
	player.call("_try_interact")
	player.call("_try_interact")
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("Spamming interact disturbed the in-progress session.")
		quit(1)
		return
	if toilet._active_player != player:
		push_error("Spamming interact changed the toilet's active player.")
		quit(1)
		return

	# --- Cancel before completion: bladder unchanged, state restored. ---
	minigame._unhandled_input(_make_cancel_event())
	if minigame.current_state != ToiletMinigame.MinigameState.CANCELLED:
		push_error("ui_cancel did not move the minigame into CANCELLED.")
		quit(1)
		return
	await create_timer(1.0).timeout # cancel's own 0.5s delay + cleanup tween
	if minigame.current_state != ToiletMinigame.MinigameState.IDLE:
		push_error("Minigame did not return to IDLE after cancel's cleanup finished.")
		quit(1)
		return
	if player.bladder.current_value != 30.0:
		push_error("Cancel changed the bladder value; it must stay untouched (got %f)." % player.bladder.current_value)
		quit(1)
		return
	if player.is_toilet_minigame_active() or player.is_door_minigame_active():
		push_error("Player minigame-lock flag did not clear after cancel.")
		quit(1)
		return
	if not player.is_physics_processing():
		push_error("Player movement was not restored after cancel.")
		quit(1)
		return

	# Toilet must be interactable again after cancel.
	await physics_frame
	player.call("_try_interact")
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("Toilet did not accept a new session after the previous one was cancelled.")
		quit(1)
		return

	# --- Success: drive bladder to 0 while parked in the safe zone. ---
	player.bladder.current_value = 5.0 # small on purpose - fast, deterministic drain
	minigame.asset_anchor.position.x = 0.0
	var iterations := 0
	while minigame.current_state == ToiletMinigame.MinigameState.PLAYING and iterations < 2000:
		minigame._evaluate_balance(STEP_DELTA)
		iterations += 1
	if minigame.current_state != ToiletMinigame.MinigameState.SUCCESS:
		push_error("Minigame never reached SUCCESS while parked in the safe zone.")
		quit(1)
		return
	await create_timer(1.5).timeout # success's own 1.0s delay + cleanup tween
	if minigame.current_state != ToiletMinigame.MinigameState.IDLE:
		push_error("Minigame did not return to IDLE after success's cleanup finished.")
		quit(1)
		return
	if player.bladder.current_value != 0.0:
		push_error("Success did not leave the interacting player's bladder at 0.")
		quit(1)
		return
	if player_b.bladder.current_value != 42.0:
		push_error("player_b's bladder was touched by player's success.")
		quit(1)
		return
	if not player.is_physics_processing():
		push_error("Player movement was not restored after success.")
		quit(1)
		return
	if player.is_toilet_minigame_active():
		push_error("Player minigame-lock flag did not clear after success.")
		quit(1)
		return

	# --- Player invalidation mid-session (e.g. death): safe cleanup via
	# cancel, no success, no bladder change.
	#
	# Note: toilet invalidation can no longer be tested by freeing the
	# toilet mid-session. ToiletMinigame is now a *child* of Toilet (per
	# the ported node structure), so toilet.queue_free() frees the minigame
	# with it in the same GC pass - there is no reachable state where the
	# minigame outlives its own toilet to detect and clean up; Godot's own
	# node-tree lifecycle already makes that scenario impossible. (Verified
	# directly: is_instance_valid(minigame) is false immediately after
	# freeing its parent toilet - calling into it from there would be
	# invoking a method on an already-freed Node, which is a genuine
	# use-after-free, not something the minigame needs to guard against.)
	await physics_frame
	player.call("_try_interact")
	if minigame.current_state != ToiletMinigame.MinigameState.PLAYING:
		push_error("Toilet did not start a fresh session for the player-invalidation test.")
		quit(1)
		return
	player.bladder.current_value = 33.0
	player.is_alive = false
	minigame._process(STEP_DELTA) # the real per-frame validity check lives here
	if minigame.current_state == ToiletMinigame.MinigameState.PLAYING:
		push_error("Minigame kept running after its player became invalid.")
		quit(1)
		return
	if minigame.current_state == ToiletMinigame.MinigameState.SUCCESS:
		push_error("Player invalidation must not count as a success.")
		quit(1)
		return
	if player.bladder.current_value != 33.0:
		push_error("Player invalidation must not change the bladder value.")
		quit(1)
		return
	player.is_alive = true

	print("Toilet minigame smoke test passed.")
	quit()


func _make_cancel_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	return event
