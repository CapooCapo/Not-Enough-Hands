extends Node


@onready var power_manager: PowerManager = $PowerManager


var blackout_count: int = 0
var power_restored_count: int = 0


func _ready() -> void:
	power_manager.blackout.connect(_on_blackout)
	power_manager.power_restored.connect(_on_power_restored)

	print("========== POWER TEST ==========")
	print("Max Power: ", power_manager.max_power)
	print("Current Power: ", power_manager.current_power)
	print("Total Load: ", power_manager.get_total_load())

	test_initial_blackout()
	test_power_drain()
	test_blackout_transition()
	test_restore_power()
	test_restore_does_not_exceed_max_power()

	print("========== POWER TEST PASSED ==========")


func test_initial_blackout() -> void:
	power_manager.current_power = 0.0
	power_manager.is_blackout = false

	power_manager._ready()

	assert(
		power_manager.is_blackout,
		"PowerManager should be in blackout when current_power starts at 0"
	)


func test_power_drain() -> void:
	power_manager.is_blackout = false
	power_manager.current_power = 100.0

	power_manager._process(0.1)

	assert(
		power_manager.current_power < 100.0,
		"Power should decrease when devices consume power"
	)

	assert(
		power_manager.current_power >= 0.0,
		"Power must not go below 0"
	)


func test_blackout_transition() -> void:
	power_manager.is_blackout = false
	power_manager.current_power = 100.0

	var old_count := blackout_count

	power_manager._process(1.0)

	assert(
		power_manager.current_power == 0.0,
		"Power should reach 0"
	)

	assert(
		power_manager.is_blackout,
		"PowerManager should enter blackout"
	)

	assert(
		blackout_count == old_count + 1,
		"blackout should emit when entering blackout"
	)

	power_manager._process(1.0)

	assert(
		blackout_count == old_count + 1,
		"blackout should not emit more than once"
	)


func test_restore_power() -> void:
	power_manager.current_power = 0.0
	power_manager.is_blackout = true

	var old_count := power_restored_count

	power_manager.restore_power()

	assert(
		power_manager.current_power == power_manager.max_power,
		"Restore should restore power to max_power"
	)

	assert(
		not power_manager.is_blackout,
		"Restore should exit blackout state"
	)

	assert(
		power_restored_count == old_count + 1,
		"power_restored should emit when leaving blackout"
	)


func test_restore_does_not_exceed_max_power() -> void:
	power_manager.current_power = power_manager.max_power
	power_manager.is_blackout = false

	var old_count := power_restored_count

	power_manager.restore_power(500.0)

	assert(
		power_manager.current_power <= power_manager.max_power,
		"Power must not exceed max_power"
	)

	assert(
		power_restored_count == old_count,
		"power_restored should not emit when not in blackout"
	)


func _on_blackout() -> void:
	blackout_count += 1


func _on_power_restored() -> void:
	power_restored_count += 1
