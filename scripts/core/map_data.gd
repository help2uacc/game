class_name MapData
extends RefCounted
## Parsed map JSON (§10.1). Cell (x, row) occupies world
## x in [x, x+1], y in [height-1-row, height-row]; row 0 is the top row.

const LEGEND := ".#%=L^CJMSWI"
const SOLID_CHARS := "#%"
const FLOOR_CHARS := "#%=CM"

var id: String = ""
var display_name: String = ""
var theme: String = ""
var width: int = 0
var height: int = 0
var rows: PackedStringArray = []
var movers: Array[Dictionary] = []
var parse_error: String = ""


static func load_file(path: String) -> MapData:
	var text: String = FileAccess.get_file_as_string(path)
	var md: MapData = from_json(text)
	return md


static func from_json(text: String) -> MapData:
	var md := MapData.new()
	var json := JSON.new()
	if json.parse(text) != OK:
		md.parse_error = "JSON parse error: %s (line %d)" % [json.get_error_message(), json.get_error_line()]
		return md
	if typeof(json.data) != TYPE_DICTIONARY:
		md.parse_error = "Root must be an object"
		return md
	var d: Dictionary = json.data
	md.id = str(d.get("id", ""))
	md.display_name = str(d.get("name", ""))
	md.theme = str(d.get("theme", ""))
	var layout: Variant = d.get("layout", [])
	if typeof(layout) != TYPE_ARRAY:
		md.parse_error = "layout must be an array"
		return md
	for row: Variant in layout:
		md.rows.append(str(row))
	md.height = md.rows.size()
	md.width = md.rows[0].length() if md.height > 0 else 0
	var mv: Variant = d.get("movers", [])
	if typeof(mv) == TYPE_ARRAY:
		for m: Variant in mv:
			if typeof(m) == TYPE_DICTIONARY:
				md.movers.append(m)
	return md


func is_valid() -> bool:
	return parse_error.is_empty() and validate().is_empty()


func cell(x: int, row: int) -> String:
	if row < 0 or row >= height or x < 0 or x >= rows[row].length():
		return "."
	return rows[row][x]


## World position of the bottom-centre of a cell.
func cell_bottom(x: int, row: int) -> Vector3:
	return Vector3(float(x) + 0.5, float(height - 1 - row), 0.0)


## World position of the centre of a cell.
func cell_center(x: int, row: int) -> Vector3:
	return Vector3(float(x) + 0.5, float(height - 1 - row) + 0.5, 0.0)


## Cell (x, row) containing world point (wx, wy).
func world_to_cell(wx: float, wy: float) -> Vector2i:
	return Vector2i(floori(wx), height - 1 - floori(wy))


func positions_of(ch: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r: int in range(height):
		var line: String = rows[r]
		for x: int in range(line.length()):
			if line[x] == ch:
				out.append(Vector2i(x, r))
	return out


func count_of(ch: String) -> int:
	var n: int = 0
	for line: String in rows:
		n += line.count(ch)
	return n


func kill_line_y() -> float:
	return -GameConfig.KILL_LINE_OFFSET


## Returns a list of human readable validation errors (empty = valid).
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if not parse_error.is_empty():
		errors.append(parse_error)
		return errors
	if id.is_empty():
		errors.append("missing id")
	if display_name.is_empty():
		errors.append("missing name")
	if theme.is_empty():
		errors.append("missing theme")
	if height == 0:
		errors.append("empty layout")
		return errors
	for r: int in range(height):
		if rows[r].length() != width:
			errors.append("row %d has length %d, expected %d" % [r, rows[r].length(), width])
	if width < GameConfig.MAP_MIN_WIDTH or width > GameConfig.MAP_MAX_WIDTH:
		errors.append("width %d outside %d-%d" % [width, GameConfig.MAP_MIN_WIDTH, GameConfig.MAP_MAX_WIDTH])
	if height < GameConfig.MAP_MIN_HEIGHT or height > GameConfig.MAP_MAX_HEIGHT:
		errors.append("height %d outside %d-%d" % [height, GameConfig.MAP_MIN_HEIGHT, GameConfig.MAP_MAX_HEIGHT])
	for r: int in range(height):
		var line: String = rows[r]
		for x: int in range(line.length()):
			if not LEGEND.contains(line[x]):
				errors.append("invalid char '%s' at (%d,%d)" % [line[x], x, r])
	if count_of("S") < GameConfig.MAP_MIN_SPAWNS:
		errors.append("needs >= %d S, has %d" % [GameConfig.MAP_MIN_SPAWNS, count_of("S")])
	if count_of("W") < GameConfig.MAP_MIN_WEAPON_POINTS:
		errors.append("needs >= %d W, has %d" % [GameConfig.MAP_MIN_WEAPON_POINTS, count_of("W")])
	if count_of("I") < GameConfig.MAP_MIN_ITEM_POINTS:
		errors.append("needs >= %d I, has %d" % [GameConfig.MAP_MIN_ITEM_POINTS, count_of("I")])
	for s: Vector2i in positions_of("S"):
		var has_floor: bool = false
		for dy: int in range(1, GameConfig.SPAWN_FLOOR_MAX_DROP + 1):
			if FLOOR_CHARS.contains(cell(s.x, s.y + dy)):
				has_floor = true
				break
		if not has_floor:
			errors.append("spawn at (%d,%d) has no floor within %d cells" % [s.x, s.y, GameConfig.SPAWN_FLOOR_MAX_DROP])
	# Movers must reference M cells, and every M cell must belong to a mover.
	var mover_cells: Dictionary = {}
	for m: Dictionary in movers:
		var mid: String = str(m.get("id", "?"))
		var cells: Variant = m.get("cells", [])
		if typeof(cells) != TYPE_ARRAY or (cells as Array).is_empty():
			errors.append("mover %s has no cells" % mid)
			continue
		for c: Variant in cells:
			var arr: Array = c
			var cx: int = int(arr[0])
			var cy: int = int(arr[1])
			if cell(cx, cy) != "M":
				errors.append("mover %s cell (%d,%d) is not an M cell" % [mid, cx, cy])
			mover_cells[Vector2i(cx, cy)] = true
		var path: Variant = m.get("path", [])
		if typeof(path) != TYPE_ARRAY or (path as Array).size() < 2:
			errors.append("mover %s needs a path with >= 2 points" % mid)
		if float(m.get("speed", 0.0)) <= 0.0:
			errors.append("mover %s needs speed > 0" % mid)
	for mc: Vector2i in positions_of("M"):
		if not mover_cells.has(mc):
			errors.append("M cell (%d,%d) not referenced by any mover" % [mc.x, mc.y])
	return errors
