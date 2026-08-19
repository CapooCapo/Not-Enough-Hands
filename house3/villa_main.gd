extends Node3D

## Playable wiring for the Vanh Dai villa map.
##
## It plays the same role main.gd plays for House2, but the villa is roughly
## four times the floor area, so two things differ: the house authors its own
## box colliders (only loose props still need generated trimesh bodies), and
## the navmesh is baked at a coarser voxel size that Recast can actually chew
## through at 80 x 60 m.
##
## Everything downstream - player, ghosts, defense doors, power, audio - is
## driven off the same node groups House2 publishes, so nothing else changed.

@export_category("Development")
@export var development_lighting: bool = false

@onready var house: Node3D = $VillaHouse
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var moon_light: DirectionalLight3D = $DirectionalLight3D
@onready var horror_overlay: CanvasLayer = $Player/HorrorOverlay
@onready var flashlight: SpotLight3D = $Player/CameraPivot/Camera3D/Flashlight

const DEFENSE_DOOR: PackedScene = preload("res://door/defense_door.tscn")

## The stock defense door is built for House2's 3 m storey and 2.2 m opening.
## A villa entrance is two 2 m cells wide in a 3.5 m wall.
const DEFENSE_DOOR_SCALE := Vector3(1.55, 1.2, 1.0)

## Height of the leaf's centre above the door node's own origin.
const DEFENSE_DOOR_LEAF_RISE := 1.15

var _two_sided_cache: Dictionary = {}


func _ready() -> void:
	if development_lighting:
		horror_overlay.visible = false
		flashlight.visible = false
	else:
		_apply_horror_lighting()

	_place_defense_doors()
	_place_player()
	_place_ghosts()

	for node: Node in house.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			_make_mesh_two_sided(mesh_instance)
			if not _has_authored_collision(mesh_instance):
				mesh_instance.create_trimesh_collision()
				_enable_backface_collision(mesh_instance)

	_bake_navigation()


# --- map wiring --------------------------------------------------------------

## VillaHouse emits one anchor per spec entrance; the defense doors themselves
## belong to the game scene, exactly as they do in main.tscn.
func _place_defense_doors() -> void:
	var entrances := Node3D.new()
	entrances.name = "Entrances"
	add_child(entrances)

	var anchors := get_tree().get_nodes_in_group("villa_entrance_anchors")
	anchors.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get_meta("entrance_id")) < int(b.get_meta("entrance_id"))
	)
	for anchor_node: Node in anchors:
		var anchor := anchor_node as Marker3D
		var door := DEFENSE_DOOR.instantiate() as Node3D
		door.name = "Entrance%02d%s" % [
			int(anchor.get_meta("entrance_id")),
			String(anchor.get_meta("spec_id")),
		]
		door.set("entrance_id", int(anchor.get_meta("entrance_id")))
		entrances.add_child(door)
		door.scale = DEFENSE_DOOR_SCALE
		if bool(anchor.get_meta("overhead", false)):
			# Entrance 07 is a skylight. Tipping the leaf onto its back turns
			# the stock door into a boarded roof hatch in the attic ceiling,
			# instead of a slab standing in the middle of the floor. The leaf
			# is modelled upward from its origin, so it also needs shifting
			# back under the anchor once it is lying down.
			door.global_rotation = Vector3(-PI * 0.5, 0.0, 0.0)
			door.global_position = anchor.global_position + Vector3(
				0.0, 0.0, DEFENSE_DOOR_LEAF_RISE * DEFENSE_DOOR_SCALE.y
			)
		else:
			door.global_position = anchor.global_position
			door.global_rotation = anchor.global_rotation
		# Spec section 7 gives each entrance its own boarding budget; carry it
		# through so the far cellar door really is the one worth abandoning.
		door.set("max_durability", float(anchor.get_meta("layers")) * 40.0)
		door.set("repair_per_interaction", 60.0 / float(anchor.get_meta("repair_seconds")))


func _place_player() -> void:
	var spawns := get_tree().get_nodes_in_group("villa_spawn_points")
	if spawns.is_empty():
		return
	var player := get_node_or_null("Player") as Node3D
	if player:
		player.global_position = (spawns[0] as Node3D).global_position + Vector3(0, 1.0, 0)


func _place_ghosts() -> void:
	var lairs := get_tree().get_nodes_in_group("crawler_lair")
	var crawler := get_node_or_null("CrawlerGhost") as Node3D
	if crawler and not lairs.is_empty():
		crawler.global_position = (lairs[0] as Node3D).global_position

	var statue := get_node_or_null("StatueGhost") as Node3D
	var chapel := _room_marker("R_CHAPEL")
	if statue and chapel:
		# Rooms publish a furniture-free tile; the geometric centre is usually
		# where that room's own table stands.
		statue.global_position = chapel.get_meta("clear_point", chapel.global_position)

	# The huntsman starts outside and only ever gets in through a breach.
	var hunter := get_node_or_null("HunterGhost") as Node3D
	if hunter:
		hunter.global_position = Vector3(40.0, 0.0, -12.0)


func _room_marker(room_id: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("villa_rooms"):
		if String(node.get_meta("room_id", "")) == room_id:
			return node as Node3D
	return null


# --- navigation --------------------------------------------------------------

func _bake_navigation() -> void:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.agent_height = 1.75
	navigation_mesh.agent_radius = 0.4
	navigation_mesh.agent_max_climb = 0.5
	navigation_mesh.agent_max_slope = 50.0
	# House2 bakes at 10 cm. The villa covers about four times the area, and a
	# 10 cm voxel grid over 80 x 60 m of building plus garden is minutes of
	# work for detail no 40 cm agent can use. 20 cm still resolves the 2 m
	# doorways and the 4 m corridors cleanly.
	navigation_mesh.cell_size = 0.2
	navigation_mesh.cell_height = 0.125
	navigation_mesh.filter_low_hanging_obstacles = true
	navigation_mesh.filter_ledge_spans = true
	navigation_mesh.filter_walkable_low_height_spans = true
	# Same reasoning as House2: parse the collision shapes movement actually
	# uses, so the route graph and physics cannot disagree about a wall.
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS

	# A closed interior door still blocks movement through physics, but baking
	# it would freeze it into the route graph as a permanent wall and cut the
	# floor into one island per room. Lift them out for the duration of the
	# parse only.
	var door_shapes := _interior_door_shapes()
	for shape: CollisionShape3D in door_shapes:
		shape.disabled = true

	var source_geometry_data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navigation_mesh, source_geometry_data, self)

	for shape: CollisionShape3D in door_shapes:
		shape.disabled = false

	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source_geometry_data)

	var navigation_region := NavigationRegion3D.new()
	navigation_region.name = "VillaNavigationRegion"
	navigation_region.navigation_mesh = navigation_mesh
	add_child(navigation_region)
	_add_stair_navigation_links()


func _interior_door_shapes() -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	for door: Node in get_tree().get_nodes_in_group("villa_interior_doors"):
		for node: Node in door.find_children("*", "CollisionShape3D", true, false):
			shapes.append(node as CollisionShape3D)
	return shapes


## Recast erodes a walkable surface by the agent radius, so the seam where a
## 45-degree ramp meets its landing can come out as two islands. Every ramp
## therefore states its own connection, and states the extra hop onto the
## floor beyond the landing tile.
func _add_stair_navigation_links() -> void:
	for ramp_node: Node in get_tree().get_nodes_in_group("smooth_stair_ramps"):
		var ramp := ramp_node as StaticBody3D
		if not ramp:
			continue
		var rise := float(ramp.get_meta("rise", 3.5))
		var uphill := ramp.global_basis.x.normalized()
		var horizontal_uphill := Vector3(uphill.x, 0.0, uphill.z).normalized()
		if horizontal_uphill.is_zero_approx():
			continue

		var link := NavigationLink3D.new()
		link.name = ramp.name.trim_suffix("SmoothRamp") + "NavigationLink"
		link.bidirectional = true
		link.start_position = (
			ramp.global_position - horizontal_uphill * (rise * 0.5 + 0.6) - Vector3.UP * rise * 0.5
		)
		link.end_position = (
			ramp.global_position + horizontal_uphill * (rise * 0.5 + 0.9) + Vector3.UP * rise * 0.5
		)
		if ramp.has_meta("enter_cost"):
			link.enter_cost = float(ramp.get_meta("enter_cost")) * 10.0
		link.add_to_group("smooth_stair_navigation_links")
		add_child(link)

		var landing_link := NavigationLink3D.new()
		landing_link.name = ramp.name.trim_suffix("SmoothRamp") + "UpperLandingNavigationLink"
		landing_link.bidirectional = true
		landing_link.start_position = link.end_position
		landing_link.end_position = link.end_position + horizontal_uphill * 2.0
		landing_link.add_to_group("smooth_stair_landing_links")
		add_child(landing_link)


# --- rendering helpers -------------------------------------------------------

## Props keep the collider they ship with; the architecture is already boxed by
## VillaHouse, so only free-standing kit meshes need a generated trimesh body.
func _has_authored_collision(mesh_instance: MeshInstance3D) -> bool:
	var ancestor := mesh_instance.get_parent()
	while ancestor and ancestor != house:
		if ancestor is CollisionObject3D or ancestor.is_in_group("smooth_stair_visual"):
			return true
		ancestor = ancestor.get_parent()
	return false


## The kit's wall and floor panels are single-sided, and half of them are seen
## from inside. Cache by source material so 2000 panels share a few overrides
## instead of allocating one StandardMaterial3D each.
func _make_mesh_two_sided(mesh_instance: MeshInstance3D) -> void:
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		var source_material := mesh_instance.get_active_material(surface_index)
		var key: Variant = source_material if source_material else 0
		if not _two_sided_cache.has(key):
			var two_sided: BaseMaterial3D
			if source_material is BaseMaterial3D:
				two_sided = (source_material as BaseMaterial3D).duplicate() as BaseMaterial3D
			else:
				two_sided = StandardMaterial3D.new()
			two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
			_two_sided_cache[key] = two_sided
		mesh_instance.set_surface_override_material(surface_index, _two_sided_cache[key])


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
