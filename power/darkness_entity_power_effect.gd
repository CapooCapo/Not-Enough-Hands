class_name DarknessEntityPowerEffect
extends Node

## Attach this component below the darkness entity. The entity can call
## cause_random_outage() whenever its attack should darken part of the house.

@export_range(0.1, 300.0, 0.5) var outage_duration: float = 10.0


func cause_random_outage() -> bool:
	var manager := get_tree().get_first_node_in_group("power_manager") as PowerManager
	if not manager:
		push_warning("Darkness entity could not find a PowerManager")
		return false
	return manager.trigger_random_regional_blackout(outage_duration) > 0


func clear_outage() -> void:
	var manager := get_tree().get_first_node_in_group("power_manager") as PowerManager
	if manager:
		manager.end_regional_blackout()
