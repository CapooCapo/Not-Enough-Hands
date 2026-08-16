extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if not packed:
		_fail("Main scene with Dev Tools could not be loaded.")
		return

	var game := packed.instantiate()
	root.add_child(game)
	var dev_tools := game.get_node("DevTools") as DevTools
	var player := game.get_node("Player") as CharacterBody3D
	var statue := game.get_node("StatueGhost") as CharacterBody3D
	var crawler := game.get_node("CrawlerGhost") as CharacterBody3D
	var director := game.get_node("DoorAttackDirector") as DoorAttackDirector
	if not dev_tools or not player or not statue or not crawler or not director:
		_fail("Dev Tools could not resolve its main-scene dependencies.")
		return

	director.automatic_waves = false
	statue.set_physics_process(false)
	crawler.set_physics_process(false)
	for door: Node in get_nodes_in_group("defense_doors"):
		door.set_physics_process(false)

	dev_tools.set_panel_open(true)
	if not dev_tools.panel_open or not dev_tools.panel.visible:
		_fail("F1 panel API did not show Dev Tools.")
		return
	dev_tools.set_invincibility_enabled(true)
	if not bool(player.get("dev_invincible")) \
		or bool(player.call("can_be_targeted_by_ghosts")):
		_fail("Invincibility did not protect the player from ghost targeting.")
		return
	player.call("kill_by_ghost", statue)
	if not bool(player.get("is_alive")):
		_fail("A ghost killed the player while Dev Tools invincibility was enabled.")
		return

	dev_tools.set_fast_movement_enabled(true)
	if not bool(player.get("dev_fast_movement")) \
		or not is_equal_approx(float(player.get("current_stamina")), float(player.get("max_stamina"))):
		_fail("Fast movement did not enable or refill development stamina.")
		return

	if not dev_tools.spawn_statue() or not statue.get_node("VisualRoot").visible:
		_fail("Dev Tools did not force the statue to manifest.")
		return
	if not dev_tools.spawn_crawler() or not bool(crawler.get("manifested")):
		_fail("Dev Tools did not force the crawler to manifest.")
		return

	dev_tools.set_selected_entrance(4)
	if not dev_tools.force_selected_door_attack():
		_fail("Dev Tools could not start an attack at entrance 04.")
		return
	var attacked_door: DefenseDoor
	for door: Node in get_nodes_in_group("defense_doors"):
		if int(door.get("entrance_id")) == 4:
			attacked_door = door as DefenseDoor
			break
	if not attacked_door \
		or attacked_door.attack_phase != DefenseDoor.AttackPhase.STALKING \
		or not attacked_door.planned_attack:
		_fail("The selected entrance did not receive the forced real attack.")
		return

	dev_tools.set_panel_open(false)
	if dev_tools.panel_open or dev_tools.panel.visible:
		_fail("Dev Tools panel did not close.")
		return

	for audio: AudioStreamPlayer3D in [
		statue.get_node("TeleportAudio"),
		statue.get_node("AttackAudio"),
		statue.get_node("SpottedJumpscareAudio"),
		crawler.get_node("CrawlAudio"),
		crawler.get_node("ChitterAudio"),
		crawler.get_node("BreathAudio"),
		crawler.get_node("ScreamAudio"),
		crawler.get_node("BoneAudio"),
	]:
		audio.stop()
	game.queue_free()
	await process_frame
	print("Dev Tools smoke test passed: invincibility, x3 speed, both ghosts, and selected-door attack.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
