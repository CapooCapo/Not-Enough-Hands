@tool
extends Node3D

const LEVEL_Y: Array[float] = [0.0, 3.5, 7.0, 10.5]
const LEVEL_NAMES: Array[String] = ["TẦNG HẦM", "TẦNG TRỆT", "LẦU TRÊN", "GÁC MÁI"]
const PLAN_SCALE := 1.4
const WALL := Color("69727d")
const FLOOR := Color("414852")
const PARTITION := Color("87919c")

func _ready() -> void:
	build_house()

func build_house() -> void:
	if has_node("Generated"):
		return
	var generated := Node3D.new()
	generated.name = "Generated"
	add_child(generated)

	# Axis-aligned architecture may safely use plan scaling. Rotated stair
	# collision is built separately at final world size to avoid non-uniform
	# inherited scale corrupting its collision surface.
	var architecture := Node3D.new()
	architecture.name = "ScaledArchitecture"
	architecture.scale = Vector3(PLAN_SCALE, 1.0, PLAN_SCALE)
	generated.add_child(architecture)
	# A broad, flat collision foundation catches the player everywhere around
	# the house. It remains below the basement as a hidden final safety catch.
	_box(generated, "MapSafetyFloor", Vector3(80, .24, 80), Vector3(0, -.13, 0), Color("28332e"))
	_add_single_ground(generated)
	_add_environment(architecture)
	for level in range(4):
		_add_level(architecture, level)
	for level in range(3):
		_add_stair(generated, level)
	_add_cellar_access(generated)
	_add_entrances(architecture)
	_add_roof(architecture)

func _add_single_ground(root: Node3D) -> void:
	# One combined ground object covers the full map. The only visible exterior
	# opening is the west cellar trench; a second hidden cut preserves the indoor stair.
	var ground := CSGCombiner3D.new()
	ground.name = "SingleMapGround"
	ground.use_collision = true
	root.add_child(ground)
	# Top surface is Y=3.61, exactly matching the ground-floor slabs.
	_box(ground, "GroundMass", Vector3(80, .25, 80), Vector3(0, 3.485, 0), Color("334438"), Vector3.ZERO, false)
	var tunnel_cut := _box(ground, "CellarTunnelCut", Vector3(9.2, 1.0, 4.2), Vector3(-18.2, 3.485, 0), Color.WHITE, Vector3.ZERO, false)
	tunnel_cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	# This cut is fully inside the house and is not an additional exterior hole.
	var stair_cut := _box(ground, "IndoorStairCut", Vector3(8.8, 1.0, 10.5), Vector3(9.8, 3.485, 0), Color.WHITE, Vector3.ZERO, false)
	stair_cut.operation = CSGShape3D.OPERATION_SUBTRACTION

func _add_environment(root: Node3D) -> void:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("18202a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9c7d8")
	env.ambient_light_energy = 0.65
	world.environment = env
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)
	# Roof and side walls turn the sunken cellar stair into a readable tunnel.
	# Sloped parallel to the exterior steps, maintaining about 2.3 m headroom.
	_box(root, "CellarTunnelRoof", Vector3(7.15, .25, 3.2), Vector3(-13.25, 4.25, 0), Color("303942"), Vector3(0, 0, -27.3), false)
	_box(root, "CellarTunnelNorthWall", Vector3(6.5, 3.0, .22), Vector3(-13.25, 1.5, -1.6), Color("424b55"))
	_box(root, "CellarTunnelSouthWall", Vector3(6.5, 3.0, .22), Vector3(-13.25, 1.5, 1.6), Color("424b55"))

func _add_cellar_access(root: Node3D) -> void:
	var access := Node3D.new()
	access.name = "WalkableCellarAccess"
	root.add_child(access)
	# Final world dimensions are baked here; this rotated collision shape never
	# inherits the architecture's non-uniform X/Z plan scale.
	var run: float = 6.0 * PLAN_SCALE
	var rise: float = 3.5
	var angle: float = -rad_to_deg(atan(rise / run))
	var slope_length: float = sqrt(run * run + rise * rise)
	var surface_offset: float = cos(deg_to_rad(angle)) * .12
	var center := Vector3(-13.0 * PLAN_SCALE, rise * .5 + .11 - surface_offset, 0)
	_box(access, "CellarWalkableRamp", Vector3(slope_length, .24, 2.5 * PLAN_SCALE), center, Color("65547d"), Vector3(0, 0, angle), true)
	# Thin visual tread lines are coplanar and never participate in collision.
	for i in range(12):
		var t: float = float(i) / 11.0
		var tread_x: float = (-10.0 - 6.0 * t) * PLAN_SCALE
		var tread_y: float = .1175 + rise * t
		_box(access, "CellarTread_%02d" % (i + 1), Vector3(.12 * PLAN_SCALE, .015, 2.55 * PLAN_SCALE), Vector3(tread_x, tread_y, 0), Color("a990c4"), Vector3.ZERO, false)

func _add_level(root: Node3D, level: int) -> void:
	var y: float = LEVEL_Y[level]
	var group := Node3D.new()
	group.name = LEVEL_NAMES[level]
	root.add_child(group)
	# Floor split around a permanent stairwell at the east side.
	_box(group, "FloorWest", Vector3(14, .22, 14), Vector3(-3, y, 0), FLOOR)
	# The inner edges sit at Z +/-3.7, exactly where the stair ramps terminate.
	_box(group, "FloorEastFront", Vector3(6, .22, 3.3), Vector3(7, y, 5.35), FLOOR)
	_box(group, "FloorEastBack", Vector3(6, .22, 3.3), Vector3(7, y, -5.35), FLOOR)

	if level == 0:
		_add_basement_shell(group, y)
	else:
		# Each facade is continuous unless this exact level owns an entrance there.
		var west_open: bool = level == 1
		var east_open: bool = level == 2
		var north_open: bool = level == 1 or level == 3
		var south_open: bool = level == 1 or level == 2
		_add_x_wall(group, "WestWall", -10, y, west_open)
		_add_x_wall(group, "EastWall", 10, y, east_open)
		_add_z_wall(group, "NorthWall", -7, y, north_open)
		_add_z_wall(group, "SouthWall", 7, y, south_open)

	# The basement remains an open circulation shell: tunnel in, internal stair out.
	# Only the ground floor loses Room 2; higher levels retain both adjacent rooms.
	if level == 1:
		_box(group, "CorridorWallNorth", Vector3(.16, 2.6, 2.5), Vector3(2, y + 1.3, -5.75), PARTITION)
		_box(group, "CorridorWallSouth", Vector3(.16, 2.6, 9.5), Vector3(2, y + 1.3, 2.25), PARTITION)
		_add_room_door(group, "RoomDoor_North", Vector3(2, y, -3.5), 90.0, level, "PHÒNG 1")
	elif level >= 2:
		_box(group, "RoomDivider", Vector3(12, 2.6, .16), Vector3(-4, y + 1.3, 0), PARTITION)
		_box(group, "CorridorWallNorth", Vector3(.16, 2.6, 2.5), Vector3(2, y + 1.3, -5.75), PARTITION)
		_box(group, "CorridorWallMiddle", Vector3(.16, 2.6, 5.0), Vector3(2, y + 1.3, 0), PARTITION)
		_box(group, "CorridorWallSouth", Vector3(.16, 2.6, 2.5), Vector3(2, y + 1.3, 5.75), PARTITION)
		_add_room_door(group, "RoomDoor_North", Vector3(2, y, -3.5), 90.0, level, "PHÒNG 1")
		_add_room_door(group, "RoomDoor_South", Vector3(2, y, 3.5), 90.0, level, "PHÒNG 2")
	if level > 0:
		_label(group, LEVEL_NAMES[level], Vector3(-8.7, y + 2.6, 0), Color.WHITE, 46)

func _add_basement_shell(parent: Node, y: float) -> void:
	# One CSG object produces a continuous basement shell and one collision mesh.
	# The only exterior opening is the 2.8 m west tunnel entrance.
	var shell := CSGCombiner3D.new()
	shell.name = "BasementSeamlessShell"
	shell.use_collision = true
	parent.add_child(shell)
	_box(shell, "North", Vector3(20.25, 3.3, .25), Vector3(0, y + 1.65, -7), WALL, Vector3.ZERO, false)
	_box(shell, "South", Vector3(20.25, 3.3, .25), Vector3(0, y + 1.65, 7), WALL, Vector3.ZERO, false)
	_box(shell, "East", Vector3(.25, 3.3, 14), Vector3(10, y + 1.65, 0), WALL, Vector3.ZERO, false)
	_box(shell, "WestNorth", Vector3(.25, 3.3, 5.6), Vector3(-10, y + 1.65, -4.2), WALL, Vector3.ZERO, false)
	_box(shell, "WestSouth", Vector3(.25, 3.3, 5.6), Vector3(-10, y + 1.65, 4.2), WALL, Vector3.ZERO, false)

func _add_x_wall(parent: Node, wall_name: String, x: float, y: float, has_opening: bool) -> void:
	if has_opening:
		# A 2.8 m opening matches the colored entrance frame exactly.
		_box(parent, wall_name + "North", Vector3(.25, 3.3, 5.6), Vector3(x, y + 1.65, -4.2), WALL)
		_box(parent, wall_name + "South", Vector3(.25, 3.3, 5.6), Vector3(x, y + 1.65, 4.2), WALL)
		_box(parent, wall_name + "Lintel", Vector3(.25, .6, 2.8), Vector3(x, y + 3.0, 0), WALL)
	else:
		_box(parent, wall_name, Vector3(.25, 3.3, 14), Vector3(x, y + 1.65, 0), WALL)

func _add_z_wall(parent: Node, wall_name: String, z: float, y: float, has_opening: bool) -> void:
	if has_opening:
		# A 2.8 m opening matches the colored entrance frame exactly.
		_box(parent, wall_name + "West", Vector3(8.6, 3.3, .25), Vector3(-5.7, y + 1.65, z), WALL)
		_box(parent, wall_name + "East", Vector3(8.6, 3.3, .25), Vector3(5.7, y + 1.65, z), WALL)
		_box(parent, wall_name + "Lintel", Vector3(2.8, .6, .25), Vector3(0, y + 3.0, z), WALL)
	else:
		_box(parent, wall_name, Vector3(20, 3.3, .25), Vector3(0, y + 1.65, z), WALL)

func _add_room_door(parent: Node, door_name: String, pos: Vector3, yaw: float, level: int, room_name: String) -> void:
	var door := Node3D.new()
	door.name = door_name
	door.position = pos
	door.rotation_degrees.y = yaw
	parent.add_child(door)
	var door_colors: Array[Color] = [Color("8067b7"), Color("4f8fcb"), Color("bb7651"), Color("8b9651")]
	var color: Color = door_colors[level]
	_box(door, "FrameLeft", Vector3(.14, 2.45, .18), Vector3(-1.05, 1.225, 0), color, Vector3.ZERO, false)
	_box(door, "FrameRight", Vector3(.14, 2.45, .18), Vector3(1.05, 1.225, 0), color, Vector3.ZERO, false)
	_box(door, "FrameTop", Vector3(2.24, .14, .18), Vector3(0, 2.38, 0), color, Vector3.ZERO, false)
	# Display the leaf in its closed position. It remains visual-only, preserving
	# current traversal until hinge interaction and door collision are implemented.
	_box(door, "DoorLeaf_StaticClosed", Vector3(1.9, 2.25, .12), Vector3(0, 1.125, 0), color.darkened(.18), Vector3.ZERO, false)
	_box(door, "Handle", Vector3(.09, .09, .18), Vector3(.72, 1.15, .1), Color("e7c969"), Vector3.ZERO, false)
	_label(door, room_name, Vector3(0, 2.72, 0), color.lightened(.2), 22)

func _add_stair(root: Node3D, level: int) -> void:
	var y0: float = LEVEL_Y[level]
	var stair := Node3D.new()
	stair.name = "Stair_%s_to_%s" % [LEVEL_NAMES[level], LEVEL_NAMES[level + 1]]
	root.add_child(stair)
	# One continuous collision ramp avoids snagging the CharacterBody on step edges.
	# Each flight meets both floor openings with a generous overlap.
	var run: float = 7.4 * PLAN_SCALE
	var rise: float = 3.5
	# Alternate direction on each level, creating a switchback stair instead of
	# stacking the next flight directly above the player's head at the exit.
	var direction: float = 1.0 if level % 2 == 0 else -1.0
	# Flights also alternate between the left and right lanes of the stairwell.
	var stair_x: float = (5.55 if level % 2 == 0 else 8.45) * PLAN_SCALE
	var angle: float = rad_to_deg(atan(rise / run)) * direction
	var slope_length: float = sqrt(run * run + rise * rise)
	# Compensate for the ramp thickness: its walkable top surface, rather than
	# the box centerline, now ends exactly at the adjacent floor height.
	var ramp_surface_offset: float = cos(deg_to_rad(angle)) * .12
	_box(stair, "WalkableRamp", Vector3(2.55 * PLAN_SCALE, .24, slope_length), Vector3(stair_x, y0 + rise * .5 + .11 - ramp_surface_offset, 0), Color("b4a68a"), Vector3(angle, 0, 0), true)

	# Shallow tread lines communicate "stairs" but carry no collision.
	# Stop before the upper edge; a raised final tread would behave like a curb.
	for i in range(14):
		var t: float = float(i) / 14.0
		# The ramp surface is y0 + 0.11 at its lower end. Keep each visual
		# strip nearly coplanar so the player no longer appears to sink into it.
		var tread_pos := Vector3(stair_x, y0 + .1175 + rise * t, direction * (run * .5 - run * t))
		_box(stair, "Tread_%02d" % (i + 1), Vector3(2.6 * PLAN_SCALE, .015, .12 * PLAN_SCALE), tread_pos, Color("d8ccb1"), Vector3.ZERO, false)

	# Rails are visual-only so they cannot pinch the player capsule at transitions.
	_box(stair, "RailLeft", Vector3(.12, .12, slope_length), Vector3(stair_x - 1.38 * PLAN_SCALE, y0 + 2.55, 0), Color("d9cdb5"), Vector3(angle, 0, 0), false)
	_box(stair, "RailRight", Vector3(.12, .12, slope_length), Vector3(stair_x + 1.38 * PLAN_SCALE, y0 + 2.55, 0), Color("d9cdb5"), Vector3(angle, 0, 0), false)
	# Landings are visual markers only. Collision is provided by the ramp and
	# adjacent floor; avoiding overlapping collision shapes removes the hidden curb.
	_box(stair, "LowerLanding", Vector3(2.9 * PLAN_SCALE, .18, 1.2 * PLAN_SCALE), Vector3(stair_x, y0 + .03, direction * 4.15 * PLAN_SCALE), Color("a89b81"), Vector3.ZERO, false)
	# Its visible top is exactly flush with the next floor (floor top = level + 0.11).
	_box(stair, "UpperLanding", Vector3(2.9 * PLAN_SCALE, .22, 2.0 * PLAN_SCALE), Vector3(stair_x, y0 + 3.5, direction * -4.15 * PLAN_SCALE), Color("a89b81"), Vector3.ZERO, false)
	_label(stair, "↑ %s" % LEVEL_NAMES[level + 1], Vector3(stair_x, y0 + 1.9, 0), Color("f4e7c2"), 30)

func _add_entrances(root: Node3D) -> void:
	var entrances := Node3D.new()
	entrances.name = "7_LOI_XAM_NHAP"
	root.add_child(entrances)
	# 1 basement, 3 ground, 2 upper, 1 attic; every point has a unique silhouette/color/prop.
	_entrance(entrances, 1, "CỬA HẦM / kho", Vector3(-10.05, .05, 0), Vector3(0, 90, 0), Color("8b5cf6"), "diamond")
	_entrance(entrances, 2, "CỬA CHÍNH / sảnh", Vector3(0, 3.55, 7.05), Vector3.ZERO, Color("36d96b"), "pillars")
	_entrance(entrances, 3, "CỬA SAU / bếp", Vector3(0, 3.55, -7.05), Vector3(0, 180, 0), Color("ff8a2b"), "awning")
	_entrance(entrances, 4, "CỬA SỔ / phòng phụ", Vector3(-10.05, 3.55, 0), Vector3(0, 90, 0), Color("20d7e8"), "wide")
	_entrance(entrances, 5, "CỬA BAN CÔNG / phòng ngủ", Vector3(0, 7.05, 7.05), Vector3.ZERO, Color("ff4fa3"), "balcony")
	_entrance(entrances, 6, "CỬA SỔ CAO / hành lang", Vector3(10.05, 7.05, 0), Vector3(0, -90, 0), Color("ffd43b"), "ladder")
	_entrance(entrances, 7, "CỬA GÁC MÁI / catwalk", Vector3(0, 10.55, -7.05), Vector3(0, 180, 0), Color("ff3b30"), "triangle")

func _entrance(root: Node3D, number: int, title: String, pos: Vector3, rot: Vector3, color: Color, kind: String) -> void:
	var marker := Node3D.new()
	marker.name = "Entrance_%02d_%s" % [number, kind]
	marker.position = pos
	marker.rotation_degrees = rot
	root.add_child(marker)
	# Doorway frame leaves its center physically open.
	_box(marker, "FrameLeft", Vector3(.28, 2.7, .28), Vector3(-1.25, 1.35, 0), color)
	_box(marker, "FrameRight", Vector3(.28, 2.7, .28), Vector3(1.25, 1.35, 0), color)
	_box(marker, "FrameTop", Vector3(2.78, .28, .28), Vector3(0, 2.7, 0), color)
	if kind == "pillars":
		# Keep the front entrance flush with the yard; no collision step here.
		pass
	elif kind == "awning":
		_box(marker, "Awning", Vector3(3.8, .18, 1.8), Vector3(0, 3.05, .7), color, Vector3(-12, 0, 0), false)
	elif kind == "wide":
		_box(marker, "WindowSill", Vector3(3.7, .32, .5), Vector3(0, .25, 0), color)
	elif kind == "balcony":
		_box(marker, "Balcony", Vector3(5, .22, 2.5), Vector3(0, -.05, 1.3), color)
	elif kind == "ladder":
		for i in range(5):
			_box(marker, "Rung%d" % i, Vector3(2.8, .12, .18), Vector3(0, .35 + i * .48, .5), color)
	elif kind == "triangle":
		_box(marker, "PeakLeft", Vector3(.22, 2.4, .22), Vector3(-.62, 3.25, 0), color, Vector3(0, 0, -32), false)
		_box(marker, "PeakRight", Vector3(.22, 2.4, .22), Vector3(.62, 3.25, 0), color, Vector3(0, 0, 32), false)
	elif kind == "diamond":
		_box(marker, "BeaconA", Vector3(.18, 1.3, .18), Vector3(0, 3.65, 0), color, Vector3(0, 0, 45), false)
		_box(marker, "BeaconB", Vector3(.18, 1.3, .18), Vector3(0, 3.65, 0), color, Vector3(0, 0, -45), false)
	var light := OmniLight3D.new()
	light.name = "RouteLight"
	light.position = Vector3(0, 2.0, .8)
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 5.0
	marker.add_child(light)
	_label(marker, "%02d  %s" % [number, title], Vector3(0, 3.25, .15), color, 32)

func _add_roof(root: Node3D) -> void:
	var roof := Node3D.new()
	roof.name = "Roof"
	root.add_child(roof)
	# Correct pitched-roof orientation: both halves rise toward the center ridge.
	# The eaves sit above the attic walls, keeping the entire attic sightline clear.
	_box(roof, "SlopeWest", Vector3(11.5, .22, 15.5), Vector3(-5.1, 16.15, 0), Color("343942"), Vector3(0, 0, 25), false)
	_box(roof, "SlopeEast", Vector3(11.5, .22, 15.5), Vector3(5.1, 16.15, 0), Color("343942"), Vector3(0, 0, -25), false)

func _box(parent: Node, node_name: String, size: Vector3, pos: Vector3, color: Color, rotation := Vector3.ZERO, collision := true) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = node_name
	box.size = size
	box.position = pos
	box.rotation_degrees = rotation
	box.use_collision = collision
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .82
	box.material = material
	parent.add_child(box)
	return box

func _label(parent: Node, value: String, pos: Vector3, color: Color, size: int) -> void:
	var label := Label3D.new()
	label.name = "Label_" + value.replace(" ", "_").replace("/", "_")
	label.text = value
	label.position = pos
	label.font_size = size
	label.modulate = color
	label.outline_size = 8
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
