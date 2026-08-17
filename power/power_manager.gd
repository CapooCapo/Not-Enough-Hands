class_name PowerManager
extends Node

signal blackout
signal power_restored

@export_category("Power Configuration")
@export_range(1.0, 100000.0, 1.0)
var max_power: float = 1000.0

@export_range(0.0, 100000.0, 1.0)
var current_power: float = 1000.0

@export_category("Debug")
@export var enable_power_drain: bool = true

var devices: Array[Node] = []
var is_blackout: bool = false


func _enter_tree() -> void:
	add_to_group("power_manager")


func _ready() -> void:
	current_power = clamp(current_power, 0.0, max_power)

	print("PowerManager ready")
	print("Max power: ", max_power)
	print("Current power: ", current_power)


func _process(delta: float) -> void:
	if is_blackout:
		return

	if not enable_power_drain:
		return

	var total_load := get_total_load()

	print("Load: ", total_load, " | Power: ", current_power)

	if total_load <= 0.0:
		return

	current_power -= total_load * delta
	current_power = clamp(current_power, 0.0, max_power)

	if current_power <= 0.0:
		_enter_blackout()


func register_device(device: Node) -> void:
	if device == null:
		return

	if device not in devices:
		devices.append(device)
		print("Registered device: ", device.name)
		print("Total devices: ", devices.size())


func unregister_device(device: Node) -> void:
	devices.erase(device)


func get_total_load() -> float:
	var total_load := 0.0

	for device in devices:
		if not is_instance_valid(device):
			continue

		if device.has_method("get_power_consumption"):
			total_load += device.get_power_consumption()

	return total_load


func get_power_percentage() -> float:
	if max_power <= 0.0:
		return 0.0

	return current_power / max_power


func restore_power(amount: float = -1.0) -> void:
	if amount < 0.0:
		current_power = max_power
	else:
		current_power = clamp(
			current_power + amount,
			0.0,
			max_power
		)

	if is_blackout and current_power > 0.0:
		is_blackout = false
		power_restored.emit()


func _enter_blackout() -> void:
	if is_blackout:
		return

	print("=== ENTERING BLACKOUT ===")

	is_blackout = true

	print("Emitting blackout signal...")
	blackout.emit()

	print("=== BLACKOUT DONE ===")
