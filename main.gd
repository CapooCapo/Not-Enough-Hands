extends Node3D

@export_category("Development")
@export var development_lighting: bool = false

@onready var house: Node3D = $House2
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var moon_light: DirectionalLight3D = $DirectionalLight3D
@onready var horror_overlay: CanvasLayer = $Player/HorrorOverlay
@onready var flashlight: SpotLight3D = $Player/CameraPivot/Camera3D/Flashlight

func _ready() -> void:
	if development_lighting:
		horror_overlay.visible = false
		flashlight.visible = false
	else:
		_apply_horror_lighting()

	# The modular source pack contains render meshes only. Generate static
	# trimesh colliders and make its surfaces visible from both sides. Stair
	# visuals are excluded because House2 gives them authored smooth ramps.
	for node: Node in house.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh and not _should_skip_generated_collision(mesh_instance):
			_make_mesh_two_sided(mesh_instance)
			mesh_instance.create_trimesh_collision()
			_enable_backface_collision(mesh_instance)

	_bake_house_navigation()


## Bakes a walkable navmesh from the house geometry at runtime, same reason
## as the collision loop above: the GLB has no pre-authored navmesh. Doors
## are AnimatableBody3D nodes, so the static-collider parser ignores them: a
## closed door still blocks movement via physics, but it is not baked as a
## permanent wall in the route graph.
func _bake_house_navigation() -> void:
	var navigation_mesh := NavigationMesh.new()
	# Both moving capsules are 1.75 m tall. Baking for the statue's old visual
	# height rejected/skimmed valid low-clearance stair space the player uses.
	navigation_mesh.agent_height = 1.75
	navigation_mesh.agent_radius = 0.4
	navigation_mesh.agent_max_climb = 0.6
	# The authored smooth stair ramps are 45 degrees. Give Recast a small
	# tolerance above that exact angle so voxel rounding cannot split a landing.
	navigation_mesh.agent_max_slope = 50.0
	# Match the 40 cm agent radius and the short stair risers without Recast
	# rounding either measurement up to a coarse voxel boundary.
	navigation_mesh.cell_size = 0.1
	navigation_mesh.cell_height = 0.05
	navigation_mesh.filter_low_hanging_obstacles = true
	navigation_mesh.filter_ledge_spans = true
	navigation_mesh.filter_walkable_low_height_spans = true
	# Parse the generated trimesh colliders (created above), not the raw
	# visual meshes: some house walls are thin, axis-aligned slabs that
	# Recast's voxelizer can misread as passable when parsed straight from
	# render geometry (confirmed - a fully solid, floor-to-ceiling wall was
	# still baked as walkable space, letting a computed path cut straight
	# through it). Baking from the same collision shapes move_and_slide()
	# actually collides with keeps the navmesh and physics in agreement by
	# construction, and also avoids the CPU readback cost of parsing
	# RenderingServer meshes at runtime.
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS

	var source_geometry_data := NavigationMeshSourceGeometryData3D.new()
	# Parse from this identity-transformed scene root. Parsing from `house`
	# produces vertices in House-local coordinates; attaching that mesh to an
	# identity NavigationRegion3D then offsets and scales every route away from
	# the visible building. The static-collider filter still limits the actual
	# geometry to the generated colliders under House.
	NavigationServer3D.parse_source_geometry_data(navigation_mesh, source_geometry_data, self)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source_geometry_data)

	# Parsed geometry is now in this node's local/world coordinates, so the
	# region must remain an identity-transformed sibling of House.
	var navigation_region := NavigationRegion3D.new()
	navigation_region.name = "HouseNavigationRegion"
	navigation_region.navigation_mesh = navigation_mesh
	add_child(navigation_region)
	_add_stair_navigation_links()


## Recast erodes walkable surfaces by the agent radius. At the exact line
## where a 45-degree ramp meets a flat landing this can leave two nav islands
## even though physics has one continuous floor. These links run along the
## same ramp centerline and make that authored connection explicit for AI.
func _add_stair_navigation_links() -> void:
	for ramp_node: Node in get_tree().get_nodes_in_group("smooth_stair_ramps"):
		var ramp := ramp_node as StaticBody3D
		if not ramp or not house.is_ancestor_of(ramp):
			continue
		var uphill := ramp.global_basis.x.normalized()
		var horizontal_uphill := Vector3(uphill.x, 0.0, uphill.z).normalized()
		var link := NavigationLink3D.new()
		link.name = ramp.name.trim_suffix("SmoothRamp") + "NavigationLink"
		link.bidirectional = true
		link.start_position = (
			ramp.global_position
			- horizontal_uphill * 1.7
			- Vector3.UP * 1.4
		)
		link.end_position = (
			ramp.global_position
			+ horizontal_uphill * 2.25
			+ Vector3.UP * 1.6
		)
		link.add_to_group("smooth_stair_navigation_links")
		add_child(link)

		# Recast erodes both edges of the narrow 2 m landing tile. The longitudinal
		# link above can therefore finish on a tiny valid island at the stair head
		# which is not connected laterally to the floor around the stairwell. A
		# navigation-driven body then receives no path, falls back to a straight
		# line across the opening, and wedges on the bannister. Bridge that final
		# turn explicitly for each of the three internal staircases.
		if ramp.name in [
			"StairBasementToGroundSmoothRamp",
			"StairGroundToSecondSmoothRamp",
			"StairSecondToAtticSmoothRamp",
		]:
			_add_upper_landing_navigation_link(
				ramp,
				horizontal_uphill,
				link.end_position
			)


func _add_upper_landing_navigation_link(
	ramp: StaticBody3D,
	horizontal_uphill: Vector3,
	upper_stair_end: Vector3
) -> void:
	var into_floor := Vector3.UP.cross(horizontal_uphill).normalized()
	var landing_link := NavigationLink3D.new()
	landing_link.name = ramp.name.trim_suffix("SmoothRamp") + "UpperLandingNavigationLink"
	landing_link.bidirectional = true
	landing_link.start_position = upper_stair_end
	landing_link.end_position = upper_stair_end + into_floor * 1.55
	landing_link.add_to_group("smooth_stair_landing_links")
	add_child(landing_link)


func _make_mesh_two_sided(mesh_instance: MeshInstance3D) -> void:
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var source_material := mesh_instance.get_active_material(surface_index)
		var two_sided_material: BaseMaterial3D

		if source_material is BaseMaterial3D:
			two_sided_material = source_material.duplicate() as BaseMaterial3D
		else:
			two_sided_material = StandardMaterial3D.new()

		two_sided_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.set_surface_override_material(surface_index, two_sided_material)


## Interactive props own their collision shape and must not receive a second,
## static trimesh body from the architecture pass.
func _should_skip_generated_collision(mesh_instance: MeshInstance3D) -> bool:
	var ancestor := mesh_instance.get_parent()
	while ancestor and ancestor != house:
		if ancestor is CollisionObject3D or ancestor.is_in_group("smooth_stair_visual"):
			return true
		ancestor = ancestor.get_parent()
	return false


func _enable_backface_collision(mesh_instance: MeshInstance3D) -> void:
	for node: Node in mesh_instance.find_children("*", "CollisionShape3D", true, false):
		var collision_shape := node as CollisionShape3D
		var concave_shape := collision_shape.shape as ConcavePolygonShape3D
		if concave_shape:
			concave_shape.backface_collision = true


func _apply_horror_lighting() -> void:
	var environment := world_environment.environment
	environment.ambient_light_color = Color(0.075, 0.105, 0.15)
	environment.ambient_light_energy = 0.22
	environment.tonemap_exposure = 0.84
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.86
	environment.adjustment_contrast = 1.14
	environment.adjustment_saturation = 0.68
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.075, 0.105, 0.13)
	environment.fog_light_energy = 0.42
	environment.fog_density = 0.042
	environment.fog_height = 2.0
	environment.fog_height_density = 0.08
	environment.fog_aerial_perspective = 0.8
	environment.fog_sky_affect = 1.0
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.038
	environment.volumetric_fog_albedo = Color(0.38, 0.46, 0.5)
	environment.volumetric_fog_emission = Color(0.008, 0.012, 0.016)
	environment.volumetric_fog_emission_energy = 0.48
	environment.volumetric_fog_length = 42.0
	environment.volumetric_fog_detail_spread = 1.8
	environment.volumetric_fog_ambient_inject = 0.35
	environment.volumetric_fog_sky_affect = 0.15

	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	if sky_material:
		sky_material.sky_top_color = Color(0.004, 0.008, 0.018)
		sky_material.sky_horizon_color = Color(0.025, 0.04, 0.055)
		sky_material.ground_bottom_color = Color(0.002, 0.003, 0.006)
		sky_material.ground_horizon_color = Color(0.012, 0.018, 0.024)

	moon_light.light_color = Color(0.34, 0.43, 0.62)
	moon_light.light_energy = 0.3
