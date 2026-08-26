extends SceneTree

## ToiletGhostCaught smoke test. Verifies the standalone scene (Sprint 10)
## in isolation - no player, no toilet minigame, no ghost - since it must be
## instantiable and playable entirely on its own (see minigames/
## toilet_ghost_caught.gd's own doc comment: it carries no gameplay logic).
## Integration with the real catch flow (ToiletMinigame reacting to
## ghost_timed_out) is covered by tests/toilet_ghost_smoke.gd instead.

const SCENE_PATH := "res://minigames/toilet_ghost_caught.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# --- Scene Load: loads and instantiates successfully, with the
	# structural pieces the sprint requires. ---
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Failed to load %s." % SCENE_PATH)
		quit(1)
		return
	var instance := packed.instantiate()
	if instance == null:
		push_error("Scene failed to instantiate.")
		quit(1)
		return
	root.add_child(instance)
	await physics_frame

	if not instance.has_node("AnimationPlayer"):
		push_error("Scene is missing its required AnimationPlayer.")
		quit(1)
		return
	if not instance.has_node("AudioStreamPlayer"):
		push_error("Scene is missing its required AudioStreamPlayer.")
		quit(1)
		return
	if not instance.has_node("VisualRoot"):
		push_error("Scene is missing its required VisualRoot.")
		quit(1)
		return

	var animation_player: AnimationPlayer = instance.get_node("AnimationPlayer")
	if not animation_player.has_animation("caught"):
		push_error("AnimationPlayer has no 'caught' animation.")
		quit(1)
		return

	# --- Caught Event: the sequence starts playing on its own as soon as
	# it's added to the tree - nothing external has to kick it off. ---
	if not animation_player.is_playing() or animation_player.current_animation != "caught":
		push_error("The 'caught' animation did not start automatically on _ready().")
		quit(1)
		return

	# --- Notifies the caller when finished, and removes itself - the two
	# concrete "caller API" requirements from the sprint. Stepped instead of
	# waited-on in real time to keep this deterministic and fast, matching
	# this suite's existing convention. ---
	var finished_count := [0]
	instance.sequence_finished.connect(func(): finished_count[0] += 1)
	var elapsed := 0.0
	while is_instance_valid(instance) and elapsed < 2.0:
		await physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
	if finished_count[0] != 1:
		push_error("sequence_finished did not fire exactly once (got %d)." % finished_count[0])
		quit(1)
		return
	if is_instance_valid(instance):
		push_error("The scene did not remove itself after the sequence finished.")
		quit(1)
		return

	# --- The scene must still work without audio (Sprint 10 section 8: no
	# suitable dedicated asset exists yet) - confirmed above by the whole
	# sequence completing normally with AudioStreamPlayer.stream unset. ---
	print("Toilet ghost caught smoke test passed.")
	quit()
