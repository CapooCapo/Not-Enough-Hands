extends Node3D

@export_category("Development")
@export var development_lighting: bool = false

@onready var house: Node3D = $House
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

	# The imported GLB contains render meshes only. Generate static trimesh
	# colliders and make its surfaces visible from both sides.
	for node: Node in house.find_children("*", "MeshInstance3D"):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			_make_mesh_two_sided(mesh_instance)
			mesh_instance.create_trimesh_collision()
			_enable_backface_collision(mesh_instance)


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


func _enable_backface_collision(mesh_instance: MeshInstance3D) -> void:
	for node: Node in mesh_instance.find_children("*", "CollisionShape3D"):
		var collision_shape := node as CollisionShape3D
		var concave_shape := collision_shape.shape as ConcavePolygonShape3D
		if concave_shape:
			concave_shape.backface_collision = true


func _apply_horror_lighting() -> void:
	var environment := world_environment.environment
	environment.ambient_light_color = Color(0.12, 0.17, 0.23)
	environment.ambient_light_energy = 0.36
	environment.tonemap_exposure = 0.96
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.94
	environment.adjustment_contrast = 1.1
	environment.adjustment_saturation = 0.75
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.075, 0.105, 0.13)
	environment.fog_light_energy = 0.62
	environment.fog_density = 0.035
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
	moon_light.light_energy = 0.48
