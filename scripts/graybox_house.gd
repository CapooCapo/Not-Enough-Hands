@tool
extends Node3D

const LEVEL_Y: Array[float] = [0.0, 3.5, 7.0, 10.5]
const LEVEL_NAMES: Array[String] = ["TẦNG HẦM", "TẦNG TRỆT", "LẦU TRÊN", "GÁC MÁI"]
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

	_add_environment(generated)
	for level in range(4):
		_add_level(generated, level)
	for level in range(3):
		_add_stair(generated, level)
	_add_entrances(generated)
	_add_roof(generated)

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
	# Four yard strips leave the house/basement volume open instead of burying it.
	_box(root, "YardNorth", Vector3(32, .25, 6), Vector3(0, 3.1, -10), Color("334438"))
	_box(root, "YardSouth", Vector3(32, .25, 6), Vector3(0, 3.1, 10), Color("334438"))
	_box(root, "YardEast", Vector3(6, .25, 14), Vector3(13, 3.1, 0), Color("334438"))
	_box(root, "YardWestA", Vector3(6, .25, 5), Vector3(-13, 3.1, -4.5), Color("334438"))
	_box(root, "YardWestB", Vector3(6, .25, 5), Vector3(-13, 3.1, 4.5), Color("334438"))
	# Sunken exterior steps make basement entrance 01 independently testable.
	for i in range(12):
		var rise := 3.1 / 12.0
		var run := 6.0 / 12.0
		var height := rise * (i + 1)
		_box(root, "CellarStep_%02d" % (i + 1), Vector3(run + .03, height, 2.5), Vector3(-10.25 - run * (i + .5), height * .5, 0), Color("65547d"))

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

	# Perimeter is deliberately segmented: openings are playable doors/windows.
	_box(group, "WestWallA", Vector3(.25, 3.3, 5), Vector3(-10, y + 1.65, -4.5), WALL)
	_box(group, "WestWallB", Vector3(.25, 3.3, 5), Vector3(-10, y + 1.65, 4.5), WALL)
	_box(group, "EastWallA", Vector3(.25, 3.3, 5), Vector3(10, y + 1.65, -4.5), WALL)
	_box(group, "EastWallB", Vector3(.25, 3.3, 5), Vector3(10, y + 1.65, 4.5), WALL)
	_box(group, "NorthWallLeft", Vector3(8, 3.3, .25), Vector3(-6, y + 1.65, -7), WALL)
	_box(group, "NorthWallRight", Vector3(8, 3.3, .25), Vector3(6, y + 1.65, -7), WALL)
	_box(group, "SouthWallLeft", Vector3(8, 3.3, .25), Vector3(-6, y + 1.65, 7), WALL)
	_box(group, "SouthWallRight", Vector3(8, 3.3, .25), Vector3(6, y + 1.65, 7), WALL)

	# Readable room plan with wide 2 m connections to the central hall.
	_box(group, "PartitionNorthA", Vector3(7, 2.6, .16), Vector3(-5.5, y + 1.3, -2.3), PARTITION)
	_box(group, "PartitionNorthB", Vector3(2, 2.6, .16), Vector3(3, y + 1.3, -2.3), PARTITION)
	_box(group, "PartitionSouthA", Vector3(4, 2.6, .16), Vector3(-7, y + 1.3, 2.3), PARTITION)
	_box(group, "PartitionSouthB", Vector3(5, 2.6, .16), Vector3(2.5, y + 1.3, 2.3), PARTITION)
	_label(group, LEVEL_NAMES[level], Vector3(-8.7, y + 2.6, 0), Color.WHITE, 46)

func _add_stair(root: Node3D, level: int) -> void:
	var y0: float = LEVEL_Y[level]
	var stair := Node3D.new()
	stair.name = "Stair_%s_to_%s" % [LEVEL_NAMES[level], LEVEL_NAMES[level + 1]]
	root.add_child(stair)
	# One continuous collision ramp avoids snagging the CharacterBody on step edges.
	# Each flight meets both floor openings with a generous overlap.
	var run: float = 7.4
	var rise: float = 3.5
	# Alternate direction on each level, creating a switchback stair instead of
	# stacking the next flight directly above the player's head at the exit.
	var direction: float = 1.0 if level % 2 == 0 else -1.0
	# Flights also alternate between the left and right lanes of the stairwell.
	var stair_x: float = 5.55 if level % 2 == 0 else 8.45
	var angle: float = rad_to_deg(atan(rise / run)) * direction
	var slope_length: float = sqrt(run * run + rise * rise)
	# Compensate for the ramp thickness: its walkable top surface, rather than
	# the box centerline, now ends exactly at the adjacent floor height.
	var ramp_surface_offset: float = cos(deg_to_rad(angle)) * .12
	_box(stair, "WalkableRamp", Vector3(2.55, .24, slope_length), Vector3(stair_x, y0 + rise * .5 + .11 - ramp_surface_offset, 0), Color("b4a68a"), Vector3(angle, 0, 0), true)

	# Shallow tread lines communicate "stairs" but carry no collision.
	# Stop before the upper edge; a raised final tread would behave like a curb.
	for i in range(14):
		var t: float = float(i) / 14.0
		var tread_pos := Vector3(stair_x, y0 + rise * t + .12, direction * (run * .5 - run * t))
		_box(stair, "Tread_%02d" % (i + 1), Vector3(2.6, .055, .12), tread_pos, Color("d8ccb1"), Vector3.ZERO, false)

	# Rails are visual-only so they cannot pinch the player capsule at transitions.
	_box(stair, "RailLeft", Vector3(.12, .12, slope_length), Vector3(stair_x - 1.38, y0 + 2.55, 0), Color("d9cdb5"), Vector3(angle, 0, 0), false)
	_box(stair, "RailRight", Vector3(.12, .12, slope_length), Vector3(stair_x + 1.38, y0 + 2.55, 0), Color("d9cdb5"), Vector3(angle, 0, 0), false)
	# Landings are visual markers only. Collision is provided by the ramp and
	# adjacent floor; avoiding overlapping collision shapes removes the hidden curb.
	_box(stair, "LowerLanding", Vector3(2.9, .18, 1.2), Vector3(stair_x, y0 + .03, direction * 4.15), Color("a89b81"), Vector3.ZERO, false)
	# Its visible top is exactly flush with the next floor (floor top = level + 0.11).
	_box(stair, "UpperLanding", Vector3(2.9, .22, 2.0), Vector3(stair_x, y0 + 3.5, direction * -4.15), Color("a89b81"), Vector3.ZERO, false)
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
		_box(marker, "FrontStep", Vector3(4.2, .25, 1.8), Vector3(0, -.05, 1), color)
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
