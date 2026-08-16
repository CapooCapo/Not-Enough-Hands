extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_scene := load("res://player/player.tscn") as PackedScene
	if not player_scene:
		_fail("Player scene could not be loaded.")
		return

	var player := player_scene.instantiate() as CharacterBody3D
	root.add_child(player)
	player.set_physics_process(false)
	var stamina_bar := player.get_node_or_null(
		"StatusUI/StaminaPanel/Margin/VBox/StaminaBar"
	) as ProgressBar
	if not stamina_bar:
		_fail("Player HUD has no connected stamina bar.")
		return

	player.current_stamina = 37.0
	stamina_bar.call("_process", 0.0)
	if not is_equal_approx(stamina_bar.max_value, player.max_stamina):
		_fail("Stamina HUD max value is not connected to Player.max_stamina.")
		return
	if not is_equal_approx(stamina_bar.value, 37.0):
		_fail("Stamina HUD did not reflect Player.current_stamina.")
		return

	player.current_stamina = 0.0
	stamina_bar.call("_process", 0.0)
	if not is_zero_approx(stamina_bar.value):
		_fail("Stamina HUD did not show an empty sprint reserve.")
		return

	print("Player stamina UI smoke test passed: HUD is present and tracks stamina.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
