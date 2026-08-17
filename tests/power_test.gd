extends Node


@onready var power_manager: PowerManager = $PowerManager


func _ready() -> void:
	power_manager.blackout.connect(_on_blackout)
	power_manager.power_restored.connect(_on_power_restored)

	print("========== POWER TEST ==========")
	print("Max Power: ", power_manager.max_power)
	print("Current Power: ", power_manager.current_power)
	print("Total Load: ", power_manager.get_total_load())


func _process(_delta: float) -> void:
	print(
		"Current Power: ",
		round(power_manager.current_power),
		" | Total Load: ",
		round(power_manager.get_total_load())
	)


func _on_blackout() -> void:
	print("!!! BLACKOUT !!!")


func _on_power_restored() -> void:
	print("!!! POWER RESTORED !!!")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			power_manager.restore_power()
			print("Power restored manually.")

		elif event.keycode == KEY_SPACE:
			print("Total Load: ", power_manager.get_total_load())
