extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_scene := load("res://door/defense_door.tscn") as PackedScene
	var door := packed_scene.instantiate() as DefenseDoor
	root.add_child(door)
	door.set_physics_process(false)
	door.get_node("WarningAudio").stream = null
	door.get_node("StrongAttackAudio").stream = null
	door.set_random_seed(42)

	var damaged := door.take_damage(10.0)
	if not is_equal_approx(damaged, 10.0):
		_fail("Defense door did not accept ten damage.")
		return
	if not is_equal_approx(door.current_durability, 90.0):
		_fail("Defense door durability was not reduced to 90.")
		return
	if not is_equal_approx(door.repair_cap, 97.0):
		_fail("Ten damage must leave exactly seven repairable HP.")
		return
	door.repair(100.0)
	if not is_equal_approx(door.current_durability, 97.0):
		_fail("Repair exceeded the permanent 70 percent repair ceiling.")
		return

	door.reset_door()
	if not door.begin_targeting(false, 0.1):
		_fail("Defense door could not begin a false target event.")
		return
	door._physics_process(0.1)
	if door.attack_phase != DefenseDoor.AttackPhase.IDLE:
		_fail("False target event did not leave without attacking.")
		return
	if not is_equal_approx(door.current_durability, 100.0):
		_fail("False target event damaged the door.")
		return

	if not door.begin_targeting(true, 0.1):
		_fail("Defense door could not begin a real target event.")
		return
	door._physics_process(0.1)
	if door.attack_phase != DefenseDoor.AttackPhase.WEAK_ATTACK:
		_fail("Real target event did not enter the weak attack phase.")
		return

	for _second: int in 8:
		door._physics_process(1.0)
	if door.attack_phase != DefenseDoor.AttackPhase.STRONG_ATTACK:
		_fail("Door did not switch to strong attacks after eight seconds.")
		return
	var durability_after_weak := door.current_durability
	if durability_after_weak < 60.0 or durability_after_weak > 76.0:
		_fail("Weak attacks did not deal 3-5 HP once per second.")
		return

	door._physics_process(1.0)
	var strong_damage := durability_after_weak - door.current_durability
	if strong_damage < 7.0 or strong_damage > 10.0:
		_fail("Strong attack did not deal 7-10 HP per second.")
		return
	if not door.drive_ghost_away():
		_fail("Active outside ghost could not be driven away.")
		return
	if door.attack_phase != DefenseDoor.AttackPhase.IDLE:
		_fail("Door did not return to idle after the ghost was driven away.")
		return

	door.reset_door()
	door.take_damage(100.0, true)
	await physics_frame
	if door.attack_phase != DefenseDoor.AttackPhase.BREACHED:
		_fail("Zero durability did not breach the defense door.")
		return
	if not (door.get_node("DoorCollision") as CollisionShape3D).disabled:
		_fail("Breached door still blocked the entrance.")
		return
	if not is_equal_approx(door.repair_cap, 70.0):
		_fail("A fully breached door must only rebuild to 70 durability.")
		return
	door.repair(7.0)
	await physics_frame
	if door.attack_phase != DefenseDoor.AttackPhase.IDLE:
		_fail("Repairing a breach did not rebuild the door.")
		return
	if (door.get_node("DoorCollision") as CollisionShape3D).disabled:
		_fail("Rebuilt door did not block the entrance again.")
		return

	print("Defense door smoke test passed.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
