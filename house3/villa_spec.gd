class_name VillaSpec
extends RefCounted

## Reader and rasteriser for NEH_map_spec_v2 ("Biet thu Vanh Dai").
##
## Per spec section 10.2 the ASCII plans in section 3 are documentation only:
## the single source of truth is the JSON in section 9 plus the tables in
## sections 5-8, which this project keeps verbatim in neh_map_spec_v2.json.
## Nothing in this file parses a diagram.

const SPEC_PATH := "res://house3/neh_map_spec_v2.json"

## Cell tags produced by build_level(). Anything at or above ROOM is walkable.
const VOID := 0
const WALL := 1
const ROOM := 2
const CORRIDOR := 3
const JUNCTION := 4
const DOORWAY := 5
const BREACH := 6

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

var data: Dictionary = {}
var cell_size: float = 2.0
var floor_height: float = 3.5
var grid_width: int = 40
var grid_height: int = 30


static func load_default() -> VillaSpec:
	var spec := VillaSpec.new()
	spec.data = _read_spec_json()
	var grid: Dictionary = spec.data.get("grid", {})
	spec.cell_size = float(grid.get("cell_size", 2.0))
	spec.floor_height = float(grid.get("floor_height", 3.5))
	spec.grid_width = int(grid.get("width", 40))
	spec.grid_height = int(grid.get("height", 30))
	return spec


## Exported projects ship the JSON as an imported resource rather than a loose
## file, so fall back from FileAccess to the imported JSON resource.
static func _read_spec_json() -> Dictionary:
	if FileAccess.file_exists(SPEC_PATH):
		var text := FileAccess.get_file_as_string(SPEC_PATH)
		if not text.is_empty():
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary:
				return parsed
	var resource: Variant = load(SPEC_PATH)
	if resource is JSON and (resource as JSON).data is Dictionary:
		return (resource as JSON).data
	push_error("VillaSpec could not read %s." % SPEC_PATH)
	return {}


# --- coordinate helpers (spec section 1) -------------------------------------

func grid_to_world(col: int, row: int, level: int) -> Vector3:
	return Vector3(
		col * cell_size + cell_size * 0.5,
		level * floor_height,
		row * cell_size + cell_size * 0.5
	)


## Centre of a [c0, r0, c1, r1] cell rectangle, inclusive at both ends.
func rect_to_world(rect: Rect2i, level: int) -> Vector3:
	return Vector3(
		(rect.position.x + rect.size.x * 0.5) * cell_size,
		level * floor_height,
		(rect.position.y + rect.size.y * 0.5) * cell_size
	)


func rect_world_size(rect: Rect2i) -> Vector2:
	return Vector2(rect.size.x * cell_size, rect.size.y * cell_size)


static func to_rect(bounds: Array) -> Rect2i:
	var c0 := int(bounds[0])
	var r0 := int(bounds[1])
	var c1 := int(bounds[2])
	var r1 := int(bounds[3])
	return Rect2i(c0, r0, c1 - c0 + 1, r1 - r0 + 1)


static func to_cell(pair: Variant) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))


# --- table access ------------------------------------------------------------

func levels() -> Array:
	return data.get("levels", [])


func level_ids() -> Array[int]:
	var ids: Array[int] = []
	for level: Dictionary in levels():
		ids.append(int(level["level"]))
	return ids


func level_extent(level: int) -> Rect2i:
	for entry: Dictionary in levels():
		if int(entry["level"]) == level:
			return to_rect(entry["extent"])
	return Rect2i()


func level_id(level: int) -> String:
	for entry: Dictionary in levels():
		if int(entry["level"]) == level:
			return String(entry["id"])
	return "F_%d" % level


func rooms_on(level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room: Dictionary in data.get("rooms", []):
		if int(room["level"]) == level:
			result.append(room)
	return result


func room(room_id: String) -> Dictionary:
	for entry: Dictionary in data.get("rooms", []):
		if String(entry["id"]) == room_id:
			return entry
	return {}


func corridors_on(level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for corridor: Dictionary in data.get("corridors", []):
		for corridor_level: float in corridor["levels"]:
			if int(corridor_level) == level:
				result.append(corridor)
				break
	return result


func junctions_on(level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for junction: Dictionary in data.get("junctions", []):
		if int(junction["level"]) == level:
			result.append(junction)
	return result


func junction(junction_id: String) -> Dictionary:
	for entry: Dictionary in data.get("junctions", []):
		if String(entry["id"]) == junction_id:
			return entry
	return {}


func entrances() -> Array:
	return data.get("entrances", [])


func vertical_links() -> Array:
	return data.get("vertical_links", [])


func spawn_points() -> Array:
	return data.get("spawn_points", [])


## Rooms allowed by spec section 10.6 rule 5 to have a single connection.
func single_door_rooms() -> PackedStringArray:
	var allowed := PackedStringArray()
	for room_id: String in data.get("single_door_rooms", []):
		allowed.append(room_id)
	return allowed


# --- rasteriser (spec section 10.2) ------------------------------------------

## Builds one level's cell grid. Returns a dictionary with:
##   extent    : Rect2i of the level footprint
##   cells     : Dictionary[Vector2i, int] tag per cell inside the extent
##   walkable  : Dictionary[Vector2i, true] for the subset that can be walked
##   doors     : Array[Dictionary] {cell, axis} for every internal door
##   breaches  : Array[Dictionary] {entrance, cell, outward} for every entrance
##   rooms     : Array[Dictionary] solid rooms authored on this level
func build_level(level: int) -> Dictionary:
	var extent := level_extent(level)
	var cells: Dictionary = {}

	# 1. Fill the whole extent with wall.
	for col: int in range(extent.position.x, extent.position.x + extent.size.x):
		for row: int in range(extent.position.y, extent.position.y + extent.size.y):
			cells[Vector2i(col, row)] = WALL

	# 2. Carve rooms. Voids (the atrium shaft on F_01) stay solid.
	var solid_rooms: Array[Dictionary] = []
	for entry: Dictionary in rooms_on(level):
		if bool(entry.get("void", false)):
			continue
		solid_rooms.append(entry)
		_paint(cells, to_rect(entry["rect"]), ROOM)

	# 3. Carve corridors, then 4. tag junctions on top of them.
	for corridor: Dictionary in corridors_on(level):
		_paint(cells, to_rect(corridor["rect"]), CORRIDOR)
	for junction_entry: Dictionary in junctions_on(level):
		_paint(cells, to_rect(junction_entry["rect"]), JUNCTION)

	# 5. Internal doors occupy a whole wall cell, so the cell itself becomes
	# walkable floor: the wall-face pass below then turns the two cells beside
	# it into the door jambs on its own.
	var doors: Array[Dictionary] = []
	var seen_doors: Dictionary = {}
	for entry: Dictionary in solid_rooms:
		for door_cell: Variant in entry.get("doors", []):
			var cell := to_cell(door_cell)
			if not cells.has(cell) or seen_doors.has(cell):
				continue
			seen_doors[cell] = true
			cells[cell] = DOORWAY

	# 7. The shaft is repainted solid on its upper level (spec section 10.2).
	for link: Dictionary in vertical_links():
		if String(link["type"]) != "shaft" or int(link["to"]) != level:
			continue
		_paint(cells, to_rect(link["rect"]), WALL)

	# 6. Entrances replace a border wall cell with a breach point.
	var breaches: Array[Dictionary] = []
	for entrance: Dictionary in entrances():
		if int(entrance["level"]) != level:
			continue
		for cell_pair: Variant in entrance["cells"]:
			var cell := to_cell(cell_pair)
			if not cells.has(cell):
				continue
			if not bool(entrance.get("overhead", false)):
				cells[cell] = BREACH
			breaches.append({
				"entrance": entrance,
				"cell": cell,
				"outward": _outward_direction(cell, extent),
			})

	var walkable: Dictionary = {}
	for cell: Vector2i in cells:
		if cells[cell] >= ROOM:
			walkable[cell] = true

	# Door orientation (spec section 10.3) is read off the finished grid.
	for cell: Vector2i in seen_doors:
		if cells.get(cell, WALL) != DOORWAY:
			continue
		doors.append({"cell": cell, "axis": _door_axis(walkable, cell)})

	return {
		"level": level,
		"extent": extent,
		"cells": cells,
		"walkable": walkable,
		"doors": doors,
		"breaches": breaches,
		"rooms": solid_rooms,
	}


func _paint(cells: Dictionary, rect: Rect2i, tag: int) -> void:
	for col: int in range(rect.position.x, rect.position.x + rect.size.x):
		for row: int in range(rect.position.y, rect.position.y + rect.size.y):
			var cell := Vector2i(col, row)
			if cells.has(cell):
				cells[cell] = tag


## "x" means the leaf swings in a wall that runs east-west, "z" north-south.
func _door_axis(walkable: Dictionary, cell: Vector2i) -> String:
	var open_east_west := (
		walkable.has(cell + Vector2i(1, 0)) or walkable.has(cell + Vector2i(-1, 0))
	)
	return "x" if open_east_west else "z"


func _outward_direction(cell: Vector2i, extent: Rect2i) -> Vector2i:
	if cell.x == extent.position.x:
		return Vector2i(-1, 0)
	if cell.x == extent.position.x + extent.size.x - 1:
		return Vector2i(1, 0)
	if cell.y == extent.position.y:
		return Vector2i(0, -1)
	if cell.y == extent.position.y + extent.size.y - 1:
		return Vector2i(0, 1)
	return Vector2i.ZERO


# --- geometry decomposition --------------------------------------------------

## Greedily covers a cell set with as few axis-aligned rectangles as possible.
## Long slabs keep the collider and navmesh source count low on an 80x60 m map.
static func decompose_rects(cells: Dictionary) -> Array[Rect2i]:
	var remaining: Dictionary = cells.duplicate()
	var ordered: Array[Vector2i] = []
	for cell: Vector2i in remaining:
		ordered.append(cell)
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)

	var rects: Array[Rect2i] = []
	for origin: Vector2i in ordered:
		if not remaining.has(origin):
			continue
		var width := 1
		while remaining.has(origin + Vector2i(width, 0)):
			width += 1
		var height := 1
		while true:
			var row_complete := true
			for offset: int in width:
				if not remaining.has(origin + Vector2i(offset, height)):
					row_complete = false
					break
			if not row_complete:
				break
			height += 1
		for offset_x: int in width:
			for offset_y: int in height:
				remaining.erase(origin + Vector2i(offset_x, offset_y))
		rects.append(Rect2i(origin.x, origin.y, width, height))
	return rects


## Every boundary between a walkable cell and a non-walkable one, merged into
## the longest possible straight runs. Each run is
## {dir: Vector2i, fixed: int, from: int, to: int} where `fixed`/`from`/`to` are
## cell indices of the walkable side and `dir` points out of the walkable cell.
static func wall_runs(walkable: Dictionary) -> Array[Dictionary]:
	var faces: Dictionary = {}
	for cell: Vector2i in walkable:
		for direction: Vector2i in DIRECTIONS:
			if walkable.has(cell + direction):
				continue
			var fixed := cell.x if direction.x != 0 else cell.y
			var varying := cell.y if direction.x != 0 else cell.x
			var key := "%d,%d,%d" % [direction.x, direction.y, fixed]
			if not faces.has(key):
				faces[key] = {"dir": direction, "fixed": fixed, "values": []}
			(faces[key]["values"] as Array).append(varying)

	var runs: Array[Dictionary] = []
	for key: String in faces:
		var face: Dictionary = faces[key]
		var values: Array = face["values"]
		values.sort()
		var run_start: int = values[0]
		var run_end: int = values[0]
		for index: int in range(1, values.size()):
			var value: int = values[index]
			if value == run_end + 1:
				run_end = value
				continue
			runs.append({
				"dir": face["dir"], "fixed": face["fixed"],
				"from": run_start, "to": run_end,
			})
			run_start = value
			run_end = value
		runs.append({
			"dir": face["dir"], "fixed": face["fixed"],
			"from": run_start, "to": run_end,
		})
	return runs
