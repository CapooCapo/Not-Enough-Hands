extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var villa_scene := load("res://house3/villa_main.tscn") as PackedScene
	_assert(villa_scene != null, "Could not load villa_main.tscn")
	var villa := villa_scene.instantiate() as Node3D
	root.add_child(villa)
	await process_frame
	await process_frame
	await process_frame

	var manager := villa.get_node_or_null("PowerManager") as PowerManager
	var zones := villa.get_node_or_null("ElectricalZones") as Node
	var dev_tools := villa.get_node_or_null("DevTools") as DevTools
	_assert(manager != null, "villa_main is missing PowerManager")
	_assert(zones != null and zones.get_child_count() == 13, "villa_main must define 13 electrical zones")
	_assert(dev_tools != null, "villa_main is missing DevTools")
	_assert(manager.get_house_light_count() == 56, "Expected 56 Villa room/junction lights")
	_assert(manager.devices.size() == 56, "Expected 56 registered Villa electrical devices")
	_assert(dev_tools.zone_controls.get_child_count() == 13, "DevTools must expose one control per electrical zone")
	dev_tools.set_all_zones_powered(false)
	await process_frame
	_assert(manager.is_blackout, "DevTools all-zones-off must cause full blackout")
	dev_tools.toggle_electrical_zone(zones.get_node("Z07_F00_EAST") as ElectricalZone)
	await process_frame
	_assert(not manager.is_blackout, "DevTools individual zone toggle must restore only that zone")
	_assert(not (zones.get_node("Z03_F00_NORTH") as ElectricalZone).is_powered, "DevTools toggle affected another zone")
	dev_tools.set_all_zones_powered(true)
	await process_frame
	var fixtures := villa.get_node_or_null("VillaElectrical/RoomLights")
	var switches := villa.get_node_or_null("VillaElectrical/RoomSwitches")
	_assert(fixtures != null and fixtures.get_child_count() == 56, "Expected 56 physical ceiling-lamp fixtures")
	_assert(switches != null and switches.get_child_count() == 56, "Expected one interactive switch per room/junction")
	_assert(
		fixtures.get_node_or_null("R_KITCHENFixture/CeilingLamp2") != null,
		"Kitchen fixture is missing the Ceiling Lamp 2 model"
	)
	_assert(
		fixtures.get_node_or_null("R_KITCHENFixture/BulbGlow") == null,
		"Villa fixtures must not show a separate glowing sphere"
	)
	var kitchen_switch := switches.get_node_or_null("R_KITCHENLightSwitch") as StaticBody3D
	_assert(kitchen_switch != null, "Kitchen interactive switch is missing")
	_assert(kitchen_switch.controlled_device_id == &"R_KITCHEN", "Kitchen switch controls the wrong device")
	_assert(kitchen_switch.get_node_or_null("Visual") != null, "Kitchen switch model is missing")
	_assert(kitchen_switch.get_node_or_null("CollisionShape3D") != null, "Kitchen switch needs a raycast collider")
	var kitchen_interactable := kitchen_switch.get_node_or_null("Interactable") as Interactable
	_assert(kitchen_interactable != null, "Kitchen switch is not using the shared Interactable contract")
	kitchen_interactable.interact(villa)
	await process_frame
	_assert(not manager.get_device_by_id(&"R_KITCHEN").is_on, "Kitchen switch did not turn its room light off")
	kitchen_interactable.unlock()
	kitchen_interactable.interact(villa)
	await process_frame
	_assert(manager.get_device_by_id(&"R_KITCHEN").is_on, "Kitchen switch did not restore its room light")

	var mapped_ids: Dictionary = {}
	for zone_node: Node in zones.get_children():
		var zone := zone_node as ElectricalZone
		_assert(zone != null, "ElectricalZones contains a non-zone node")
		for device_id: String in zone.device_ids:
			_assert(not mapped_ids.has(device_id), "Device %s belongs to more than one zone" % device_id)
			mapped_ids[device_id] = true
	_assert(mapped_ids.size() == 56, "All 56 devices must be assigned to a zone")

	var central_north := zones.get_node("Z05_F00_CENTRAL_NORTH") as ElectricalZone
	var east := zones.get_node("Z07_F00_EAST") as ElectricalZone
	_assert(central_north.contains_device_id(&"R_GALLERY"), "Z05 must contain Gallery")
	_assert(central_north.contains_device_id(&"R_ATRIUM"), "Z05 must contain Atrium")
	_assert(not central_north.contains_device_id(&"R_BILLIARD"), "Z05 must not contain Billiard")

	central_north.set_powered(false)
	await process_frame
	_assert(not manager.get_device_by_id(&"R_GALLERY").powered_light.visible, "Z05 did not turn off Gallery")
	_assert(not manager.get_device_by_id(&"R_ATRIUM").powered_light.visible, "Z05 did not turn off Atrium")
	_assert(manager.get_device_by_id(&"R_KITCHEN").powered_light.visible, "Z05 outage affected Z07 Kitchen")
	_assert(east.is_powered, "Z07 lost state when Z05 turned off")

	for zone_node: Node in zones.get_children():
		(zone_node as ElectricalZone).set_powered(false)
	await process_frame
	_assert(manager.is_blackout, "All zones OFF must cause a full house blackout")
	_assert(is_zero_approx(manager.get_total_load()), "Full zone blackout must remove all load")

	central_north.set_powered(true)
	await process_frame
	_assert(not manager.is_blackout, "Restoring one zone must leave all-zone blackout")
	_assert(manager.get_device_by_id(&"R_GALLERY").powered_light.visible, "Restored zone did not recover Gallery")
	_assert(not manager.get_device_by_id(&"R_KITCHEN").powered_light.visible, "Unrestored zone recovered during blackout exit")

	print("Villa zone smoke test passed: 56 fixtures, 13 zones, independent outage and full blackout.")
	villa.queue_free()
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
