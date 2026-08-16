extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_scene := load("res://player/player.tscn") as PackedScene
	var player := player_scene.instantiate() as CharacterBody3D
	root.add_child(player)
	await process_frame

	var offsets := player.get("_footstep_offsets") as Array
	if offsets.size() < 12:
		_fail("The wooden-footstep recording was not split into enough transient variations.")
		return
	player.call("_play_wood_footstep", false)
	var footstep_a := player.get_node("FootstepA") as AudioStreamPlayer3D
	var footstep_b := player.get_node("FootstepB") as AudioStreamPlayer3D
	if not footstep_a.playing and not footstep_b.playing:
		_fail("Playing a wooden footstep did not start either audio voice.")
		return

	var ambience := preload("res://audio/house_ambience.gd").new()
	var ambient_bed := AudioStreamPlayer.new()
	ambient_bed.name = "AmbientBed"
	ambience.add_child(ambient_bed)
	var house_event := AudioStreamPlayer3D.new()
	house_event.name = "HouseEvent"
	ambience.add_child(house_event)
	root.add_child(ambience)
	await process_frame

	ambience.call("_begin_ambient_bed")
	if not ambient_bed.stream or not ambient_bed.playing:
		_fail("The ambience director did not start an ambient bed.")
		return
	ambience.call("_play_house_event")
	if not house_event.stream or not house_event.playing:
		_fail("The ambience director did not start an old-house event.")
		return
	ambience.call("_enter_silence", false)
	if int(ambience.get("_state")) != 0 or ambient_bed.volume_db > -59.0:
		_fail("The ambience director did not enter a genuine silent state.")
		return

	print("House audio smoke test passed: %d footstep variations and silence-aware ambience." % offsets.size())
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
