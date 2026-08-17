class_name ElectricalDevice
extends Node

@export_category("Power Configuration")
@export_range(0.0, 100000.0, 1.0)
var power_consumption: float = 100.0

@export_category("Device State")
@export var is_on: bool = true


func _enter_tree() -> void:
	add_to_group("electrical_device")


func _ready() -> void:
	var power_manager := get_tree().get_first_node_in_group("power_manager")

	if power_manager:
		print(name, " registered to PowerManager")
		power_manager.register_device(self)
	else:
		print(name, " ERROR: PowerManager not found")


func _exit_tree() -> void:
	var power_manager := get_tree().get_first_node_in_group("power_manager")

	if power_manager:
		power_manager.unregister_device(self)


func get_power_consumption() -> float:
	if not is_on:
		return 0.0

	return power_consumption


func turn_on() -> void:
	is_on = true


func turn_off() -> void:
	is_on = false


func toggle() -> void:
	is_on = not is_on
