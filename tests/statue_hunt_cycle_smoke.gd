extends SceneTree

var hunted_target: Node3D
var hunted_position := Vector3.INF


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(50.0, 0.2, 50.0)
	ground_shape.shape = ground_box
	ground_shape.position.y = -0.1
	ground.add_child(ground_shape)
	root.add_child(ground)

	var lone_player := _moving_player(Vector3(-10.0, 0.0, 0.0))
	var grouped_player_a := _moving_player(Vector3(5.0, 0.0, 0.0))
	var grouped_player_b := _moving_player(Vector3(6.0, 0.0, 0.0))
	root.add_child(lone_player)
	root.add_child(grouped_player_a)
	root.add_child(grouped_player_b)

	var statue_scene := load('res://ghosts/statue_ghost.tscn') as PackedScene
	var statue := statue_scene.instantiate() as CharacterBody3D
	statue.set('initial_hidden_delay_min', 100.0)
	statue.set('initial_hidden_delay_max', 100.0)
	statue.set('isolation_radius', 3.0)
	statue.set('ambush_min_distance', 4.0)
	statue.set('ambush_max_distance', 5.0)
	root.add_child(statue)
	await physics_frame

	if statue.get_node('TeleportAudio').stream == null or statue.get_node('AttackAudio').stream == null:
		_fail('Statue 3D sound effects were not loaded.')
		return
	# This test exits immediately after the disappear assertion; mute playback
	# after validating the resources so the headless audio driver has no active
	# WAV playback object to flush during shutdown.
	statue.get_node('TeleportAudio').stream = null
	statue.get_node('AttackAudio').stream = null

	if statue.get('state') != 1 or statue.get_node('VisualRoot').visible:
		_fail('Intermittent statue did not begin in its hidden state.')
		return
	if statue.call('_find_most_isolated_moving_player') != lone_player:
		_fail('Hunt selection did not prefer the moving player with the fewest nearby players.')
		return

	# A rejected hunt roll must create a quiet retry window instead of making
	# the statue attack continuously.
	statue.set('hunt_activation_chance', 0.0)
	statue.set('hidden_timer', 0.0)
	await physics_frame
	await physics_frame
	if statue.get('state') != 1:
		_fail('A zero hunt chance still started an attack cycle.')
		return

	statue.hunt_started.connect(_record_hunt)
	statue.set('hunt_activation_chance', 1.0)
	statue.set('hidden_timer', 0.0)
	var hunt_deadline_msec := Time.get_ticks_msec() + 1000
	while not hunted_target and Time.get_ticks_msec() <= hunt_deadline_msec:
		await physics_frame

	if not hunted_target:
		_fail('Guaranteed hunt did not manifest the statue.')
		return
	if hunted_target != lone_player:
		_fail('Ambush targeted a grouped player instead of the isolated moving player.')
		return
	var ambush_position := hunted_position
	var ambush_distance := Vector2(
		ambush_position.x - lone_player.global_position.x,
		ambush_position.z - lone_player.global_position.z
	).length()
	if ambush_distance < 3.95 or ambush_distance > 5.05:
		_fail('Ambush distance %.2f was outside the configured moderate range.' % ambush_distance)
		return
	statue.get_node('TeleportAudio').stop()
	statue.get_node('AttackAudio').stop()
	statue.get_node('TeleportAudio').stream = null
	statue.get_node('AttackAudio').stream = null
	statue.hunt_started.disconnect(_record_hunt)
	hunted_target = null
	statue.queue_free()
	lone_player.queue_free()
	grouped_player_a.queue_free()
	grouped_player_b.queue_free()
	await process_frame

	# Verify the ten-second mechanic with a shortened test value: the countdown
	# starts on first sight and continues even if the player later looks away.
	var player_scene := load('res://player/player.tscn') as PackedScene
	var observer := player_scene.instantiate() as CharacterBody3D
	observer.set('automatic_blink_enabled', false)
	root.add_child(observer)
	observer.global_position = Vector3(0.0, 0.9, 0.0)
	observer.global_rotation = Vector3.ZERO

	var watched_statue := statue_scene.instantiate() as CharacterBody3D
	watched_statue.set('start_hidden', false)
	watched_statue.set('observed_disappear_delay', 0.18)
	root.add_child(watched_statue)
	watched_statue.global_position = Vector3(0.0, 0.02, -5.0)
	watched_statue.set('current_target', observer)
	watched_statue.get_node('TeleportAudio').stream = null
	watched_statue.get_node('AttackAudio').stream = null

	await physics_frame
	await physics_frame
	if not watched_statue.get('is_observed'):
		_fail('Visible statue was not detected by the observing player.')
		return

	observer.rotation.y = PI
	await create_timer(0.24).timeout
	if watched_statue.get('state') != 1:
		_fail('Statue did not disappear after its post-sighting countdown.')
		return
	if watched_statue.get_node('VisualRoot').visible or watched_statue.collision_layer != 0:
		_fail('Disappeared statue remained visible or collidable.')
		return

	watched_statue.get_node('TeleportAudio').stop()
	watched_statue.get_node('AttackAudio').stop()
	watched_statue.get_node('TeleportAudio').stream = null
	watched_statue.get_node('AttackAudio').stream = null
	watched_statue.queue_free()
	observer.queue_free()
	ground.queue_free()
	await process_frame
	print('Statue hunt cycle smoke test passed: intermittent isolated ambush, distance, audio, and disappearance.')
	quit()


func _record_hunt(target: Node3D, position: Vector3) -> void:
	hunted_target = target
	hunted_position = position


func _moving_player(position: Vector3) -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.add_to_group('players')
	player.position = position
	player.velocity = Vector3(1.0, 0.0, 0.0)
	return player


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
