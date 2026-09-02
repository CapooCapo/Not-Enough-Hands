extends SceneTree

## The torch is now a resource. This pins the three things that makes true: it
## drains while it is on, the focused beam costs far more than the ordinary
## one, and an empty tank is dark no matter what the switch says. It also pins
## the seam the Darkness Ghost reads - is_flashlight_focused() - and the
## battery pickup that refills it.

const PLAYER_SCENE := preload("res://player/player.tscn")
const BATTERY_SCENE := preload("res://items/flashlight_battery.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	world.add_child(player)
	await physics_frame

	if not is_equal_approx(player.flashlight_battery, player.flashlight_battery_max):
		_fail("A fresh player did not start on a full torch battery.")
		return
	if not player.is_flashlight_on() or player.is_flashlight_focused():
		_fail("The torch should start on and unfocused.")
		return

	var flashlight := player.get_node_or_null(^"CameraPivot/Camera3D/Flashlight") as SpotLight3D
	if flashlight == null:
		_fail("The player has no flashlight to test.")
		return
	var base_angle: float = player._flashlight_base_angle

	# Ordinary beam: drains at flashlight_drain_per_second and nothing else.
	player._update_flashlight(10.0)
	var expected: float = player.flashlight_battery_max - player.flashlight_drain_per_second * 10.0
	if not is_equal_approx(player.flashlight_battery, expected):
		_fail("An unfocused torch did not drain at flashlight_drain_per_second.")
		return
	if not is_equal_approx(flashlight.spot_angle, base_angle):
		_fail("An unfocused torch changed its beam angle.")
		return

	# Focused: the beam narrows and brightens, and the tank pays for it. Driven
	# through the real action rather than the field behind it - the body you
	# steer reads the keyboard every tick, so a field poked from outside would
	# be overwritten before the drain ever saw it.
	Input.action_press(&"flashlight_focus")
	player._update_flashlight(0.0)
	if not player.is_flashlight_focused():
		_fail("Holding the focus on a lit torch did not report a focused beam.")
		return
	if not is_equal_approx(flashlight.spot_angle, player.flashlight_focus_angle):
		_fail("The focused beam did not narrow to flashlight_focus_angle.")
		return
	if flashlight.light_energy <= player._flashlight_base_energy:
		_fail("The focused beam is not brighter than the ordinary one.")
		return
	var before: float = player.flashlight_battery
	player._update_flashlight(1.0)
	var spent: float = before - player.flashlight_battery
	if not is_equal_approx(spent, player.flashlight_focus_drain_per_second):
		_fail("A focused second did not cost flashlight_focus_drain_per_second.")
		return
	if spent <= player.flashlight_drain_per_second:
		_fail("Focusing must cost more than an ordinary beam, or it is free.")
		return

	# Switched off: no light, no drain, and the ghost reads no beam.
	player._flashlight_on = false
	player._update_flashlight(5.0)
	if flashlight.visible or player.is_flashlight_on() or player.is_flashlight_focused():
		_fail("A torch switched off still reported itself lit.")
		return
	var parked: float = player.flashlight_battery
	player._update_flashlight(5.0)
	if not is_equal_approx(player.flashlight_battery, parked):
		_fail("A torch that is switched off still spent charge.")
		return

	# Empty: the switch stops mattering. This is the case the ghost's kill hangs
	# on - a dead battery must not report a focused beam to it.
	player._flashlight_on = true
	Input.action_press(&"flashlight_focus")
	player.flashlight_battery = 0.0
	player._update_flashlight(1.0)
	if flashlight.visible or player.is_flashlight_on() or player.is_flashlight_focused():
		_fail("An empty battery still lit the torch.")
		return
	if player.flashlight_battery < 0.0:
		_fail("An empty battery drained past zero.")
		return

	# A battery on the floor is a refill, not a hand-slot item, and it leaves the
	# world when it is spent.
	var battery := BATTERY_SCENE.instantiate() as RigidBody3D
	world.add_child(battery)
	await physics_frame
	battery._on_interacted(player)
	if not is_equal_approx(player.flashlight_battery, minf(battery.charge_amount, player.flashlight_battery_max)):
		_fail("Interacting with a battery did not refill the torch.")
		return
	if not battery.is_queued_for_deletion():
		_fail("A spent battery stayed in the world.")
		return
	if not player.is_flashlight_on():
		_fail("A refilled torch did not come back on by itself.")
		return

	# A full torch refuses the charge, so the cell stays for somebody who needs
	# it rather than being walked over and wasted. Switched off and topped up
	# first: a torch left burning is never exactly full for two frames running,
	# which is a fact about the drain, not about the refusal under test.
	Input.action_release(&"flashlight_focus")
	player._flashlight_on = false
	player.flashlight_battery = player.flashlight_battery_max
	var spare := BATTERY_SCENE.instantiate() as RigidBody3D
	world.add_child(spare)
	await physics_frame
	spare._on_interacted(player)
	if spare.is_queued_for_deletion():
		_fail("A battery was consumed by a player whose torch was already full.")
		return

	print("Flashlight battery smoke test passed: drain, focus cost, off/empty states, and pickup refill.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
