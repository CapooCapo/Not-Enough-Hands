extends SceneTree

## The villa owns exactly two hunters. The authored first hunter can answer a
## breach immediately; the only reinforcement cannot enter before 180 in-game
## minutes, even if several entrances have already been destroyed.

const VILLA_SCENE := preload("res://house3/villa_main.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := VILLA_SCENE.instantiate()
	root.add_child(game)
	var director := game.get_node_or_null("DoorAttackDirector")
	if director:
		director.set("automatic_waves", false)
	var clock := game.get_node_or_null("NightClock") as NightClock
	if not clock:
		_fail("Villa is missing its NightClock.")
		return
	clock.real_seconds_per_game_minute = 9999.0
	var first := game.get_node_or_null("HunterGhost") as CharacterBody3D
	if not first or not bool(first.get("entry_enabled")):
		_fail("The villa's first HunterGhost is not enabled for breach entry.")
		return
	first.set("entry_delay_min", 0.05)
	first.set("entry_delay_max", 0.05)

	if not await _wait_for_navigation(game):
		_fail("Villa navigation did not become ready.")
		return

	if int(game.get("MAX_HUNTERS")) != 2 \
		or int(game.get("SECOND_HUNTER_UNLOCK_MINUTES")) != 180:
		_fail("Villa hunter count or three-hour unlock contract changed.")
		return
	var doors := get_nodes_in_group("defense_doors")
	if doors.size() < 3:
		_fail("Villa needs at least three exterior defense doors for this test.")
		return
	if int(game.call("live_hunter_count")) != 1:
		_fail("Villa did not start with exactly one hunter.")
		return

	(doors[0] as Node).call("take_damage", 10000.0, true)
	if not await _wait_until_inside(first, 180):
		_fail("The first hunter did not enter through the initial breach.")
		return

	# An early second breach is remembered, but must not spawn a reinforcement.
	(doors[1] as Node).call("take_damage", 10000.0, true)
	for _attempt: int in 20:
		await physics_frame
	if int(game.call("live_hunter_count")) != 1:
		_fail("The second hunter entered before three in-game hours elapsed.")
		return

	var until_last_minute := 179 - clock.elapsed_game_minutes
	if until_last_minute > 0:
		clock.skip_minutes(until_last_minute)
	await process_frame
	if int(game.call("live_hunter_count")) != 1:
		_fail("The second hunter entered at minute 179 instead of after minute 180.")
		return
	clock.skip_minutes(1)
	var second := await _wait_for_second_hunter()
	if not second:
		_fail("The second hunter did not enter after three in-game hours.")
		return
	if not bool(second.get("inside_house")) or not bool(second.get("manifested")):
		_fail("The delayed second hunter spawned without entering the breached doorway.")
		return

	# Further destroyed entrances never create a third body.
	(doors[2] as Node).call("take_damage", 10000.0, true)
	for _attempt: int in 30:
		await physics_frame
	if int(game.call("live_hunter_count")) != 2:
		_fail("A third hunter appeared after another villa entrance was breached.")
		return

	game.queue_free()
	await process_frame
	print("Villa hunter breach spawn smoke test passed: exactly two, second unlocked at 180 minutes.")
	quit()


func _wait_for_navigation(game: Node) -> bool:
	for _attempt: int in 600:
		if bool(game.get("navigation_is_ready")):
			return true
		await physics_frame
	return false


func _wait_until_inside(hunter: CharacterBody3D, attempts: int) -> bool:
	for _attempt: int in attempts:
		await physics_frame
		if is_instance_valid(hunter) and bool(hunter.get("inside_house")):
			return true
	return false


func _wait_for_second_hunter() -> CharacterBody3D:
	for _attempt: int in 60:
		await physics_frame
		for node: Node in get_nodes_in_group("hunter_ghosts"):
			if node.name.begins_with("BreachHunter"):
				return node as CharacterBody3D
	return null


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
