extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_scene := load("res://player/player.tscn") as PackedScene
	var statue_scene := load("res://ghosts/statue_ghost.tscn") as PackedScene
	var crawler_scene := load("res://ghosts/crawler_ghost.tscn") as PackedScene
	if not player_scene or not statue_scene or not crawler_scene:
		_fail("Ghost safety test resources could not be loaded.")
		return

	var player := player_scene.instantiate() as CharacterBody3D
	var statue := statue_scene.instantiate() as CharacterBody3D
	var crawler := crawler_scene.instantiate() as CharacterBody3D
	root.add_child(player)
	root.add_child(statue)
	root.add_child(crawler)
	player.set_physics_process(false)
	statue.set_physics_process(false)
	crawler.set_physics_process(false)

	player.call("acquire_minigame_ghost_safety")
	if not bool(statue.get("dev_attack_suspended")) \
		or not bool(crawler.get("dev_attack_suspended")):
		_fail("The minigame did not suspend both hostile ghost attack systems.")
		return
	if bool(player.call("can_be_targeted_by_ghosts")):
		_fail("A protected minigame player remained targetable by ghosts.")
		return

	player.call("kill_by_ghost", statue)
	if not bool(player.get("is_alive")):
		_fail("The final player-side guard allowed a ghost kill during the minigame.")
		return

	statue.set("state", 3) # STALKING
	statue.call("_begin_attack")
	if int(statue.get("state")) == 4: # ATTACK_WINDUP
		_fail("The statue entered attack windup while dev safety was active.")
		return
	crawler.set("state", 4) # HUNTING
	crawler.call("_begin_pounce", player)
	if int(crawler.get("state")) == 6: # POUNCE_WINDUP
		_fail("The crawler entered pounce windup while dev safety was active.")
		return

	player.call("release_minigame_ghost_safety")
	player.call("_update_minigame_ghost_safety", 2.0)
	if bool(statue.get("dev_attack_suspended")) \
		or bool(crawler.get("dev_attack_suspended")):
		_fail("Ghost attacks did not resume after the post-minigame grace period.")
		return

	print("Minigame ghost safety smoke test passed.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
