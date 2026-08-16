extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://door/defense_door.tscn") as PackedScene
	var doors: Array[DefenseDoor] = []
	for index: int in 4:
		var door := packed_scene.instantiate() as DefenseDoor
		door.entrance_id = index + 1
		root.add_child(door)
		door.set_physics_process(false)
		door.get_node("WarningAudio").stream = null
		door.get_node("StrongAttackAudio").stream = null
		doors.append(door)

	var director := DoorAttackDirector.new()
	director.false_alarm_chance = 0.0
	root.add_child(director)
	director.set_process(false)
	director.set_random_seed(12)

	var selected := director.start_attack_wave(3)
	if selected.size() != 3:
		_fail("Director did not select exactly three defense doors.")
		return
	var active_count := 0
	for door: DefenseDoor in doors:
		if door.attack_phase == DefenseDoor.AttackPhase.STALKING:
			active_count += 1
	if active_count != 3:
		_fail("Director did not activate three doors simultaneously.")
		return
	if not director.start_attack_wave(9).is_empty():
		_fail("Director exceeded the three-door global attack limit.")
		return

	print("Door attack director smoke test passed.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
