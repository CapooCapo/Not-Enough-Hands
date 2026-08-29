extends SceneTree

## Verifies the villa's Classic64 suburban exterior without booting gameplay or
## baking navigation. The full villa tests cover the combined scene.
##
##   godot --headless --script tests/villa_exterior_smoke.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _main_scene_has_exterior():
		_fail("VillaMain does not contain the VillaExterior module.")
		return

	var stage := Node3D.new()
	root.add_child(stage)
	var exterior := (load("res://house3/villa_exterior.gd") as Script).new() as Node3D
	exterior.name = "VillaExterior"
	stage.add_child(exterior)
	await process_frame

	var generated := exterior.get_node_or_null("Generated") as Node3D
	if not generated or not generated.is_in_group("villa_exterior"):
		_fail("VillaExterior generated no grouped output.")
		return

	for section: String in [
		"Terrain", "RingRoad", "Boundary", "FrontCourt", "ServiceYard",
		"CellarTrench", "BackGarden", "Backdrop", "Atmosphere",
	]:
		if not generated.has_node(section):
			_fail("Exterior section %s was not generated." % section)
			return

	var meshes := generated.find_children("*", "MeshInstance3D", true, false)
	var static_bodies := generated.find_children("*", "StaticBody3D", true, false)
	var lights := generated.find_children("*", "Light3D", true, false)
	var fog := generated.find_children("*", "FogVolume", true, false)
	if meshes.size() < 300:
		_fail("Exterior detail is unexpectedly sparse: %d meshes." % meshes.size())
		return
	if static_bodies.size() < 80:
		_fail("Exterior collision is unexpectedly sparse: %d bodies." % static_bodies.size())
		return
	if lights.size() < 7 or fog.size() != 4:
		_fail("Exterior atmosphere is incomplete: %d lights, %d fog volumes." % [lights.size(), fog.size()])
		return

	for pattern: String in ["LeafLitter_*", "DeadGrass_*", "FallenBranch_*", "GardenRock_*"]:
		if generated.find_children(pattern, "MeshInstance3D", true, false).is_empty():
			_fail("Exterior is missing ground detail %s." % pattern)
			return
	if generated.find_children("SicklyLeaves_*", "MeshInstance3D", true, false).is_empty():
		_fail("Exterior treeline has no remaining foliage.")
		return
	if generated.find_children("LeafyShrub_*", "MeshInstance3D", true, false).size() < 16:
		_fail("Exterior garden has too few leafy shrub cards.")
		return

	var texture_paths: Dictionary = {}
	for node: Node in meshes:
		var mesh_instance := node as MeshInstance3D
		var material := mesh_instance.mesh.material as StandardMaterial3D if mesh_instance.mesh else null
		if not material or not material.albedo_texture:
			continue
		texture_paths[material.albedo_texture.resource_path] = true
	if texture_paths.size() < 15:
		_fail("Exterior uses only %d Classic64 textures; expected a dressed environment." % texture_paths.size())
		return

	for node: Node in static_bodies:
		var at := (node as Node3D).global_position
		if at.x < -24.01 or at.x > 104.01 or at.z < -24.01 or at.z > 84.01:
			_fail("Collider %s escaped the navigation apron at %s." % [node.name, at])
			return

	var barriers := generated.find_children("RoadEdgeBarrier_*", "StaticBody3D", true, false)
	if barriers.size() != 14:
		_fail("Far road edge needs 14 barriers, found %d." % barriers.size())
		return

	print(
		"Villa exterior smoke test passed: %d meshes, %d colliders, %d Classic64 textures."
		% [meshes.size(), static_bodies.size(), texture_paths.size()]
	)
	stage.queue_free()
	await process_frame
	quit(0)


func _main_scene_has_exterior() -> bool:
	var packed := load("res://house3/villa_main.tscn") as PackedScene
	if not packed:
		return false
	var state := packed.get_state()
	for index: int in state.get_node_count():
		if state.get_node_name(index) == &"VillaExterior":
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
