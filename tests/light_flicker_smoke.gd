extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var house_scene := load("res://house2/house2.tscn") as PackedScene
	if not house_scene:
		_fail("House2 scene could not be loaded.")
		return
	var house := house_scene.instantiate() as Node3D
	root.add_child(house)
	await process_frame
	await process_frame

	var controller := house.get_node_or_null("LightFlicker") as Node3D
	if not controller:
		_fail("House2 has no light-flicker controller.")
		return
	if controller.get_light_count() != 10:
		_fail("Expected 10 authored flickering lights, found %d." % controller.get_light_count())
		return

	controller.set_process(false)
	controller.set_random_seed(27)
	var light := get_nodes_in_group("flickering_house_lights")[0] as Light3D
	var authored_energy := light.light_energy
	if not controller.debug_start_flicker(light, 2):
		_fail("Could not force a deterministic light-flicker burst.")
		return
	if light.light_energy > authored_energy * 0.05:
		_fail("The selected light did not switch off during its first pulse.")
		return
	if controller.get_active_light() != light:
		_fail("The controller lost its selected flickering light.")
		return

	var snap_a := controller.get_node("ElectricSnap1") as AudioStreamPlayer3D
	var snap_b := controller.get_node("ElectricSnap2") as AudioStreamPlayer3D
	if not snap_a.stream or snap_a.stream.get_length() <= 0.0:
		_fail("The flicker has no generated electrical snap audio.")
		return
	if not snap_a.playing and not snap_b.playing:
		_fail("Switching the light off did not play its positional audio.")
		return
	if snap_a.global_position.distance_to(light.global_position) > 0.01:
		_fail("The electrical snap did not originate at the selected bulb.")
		return

	controller.call("_process", controller.state_time + 0.01)
	if light.light_energy < authored_energy * 0.8:
		_fail("The light did not recover between flicker pulses.")
		return
	controller.call("_process", controller.state_time + 0.01)
	if light.light_energy > authored_energy * 0.05:
		_fail("The configured second flicker pulse did not occur.")
		return
	controller.call("_process", controller.state_time + 0.01)
	controller.call("_process", controller.state_time + 0.01)
	if controller.is_flickering() or not is_equal_approx(light.light_energy, authored_energy):
		_fail("The burst did not restore the light's exact authored energy.")
		return

	print("Light flicker smoke test passed: 10 lights, multi-pulse blackout, local 3D electric audio, full recovery.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
