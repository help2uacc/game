class_name GameMap
extends Node3D
## Runtime map built from MapData (PRD §10): GridMap blocks (MeshLibrary of
## pastel blocks), background decoration layer(s), hazard / mover / crate
## nodes, spawn point lists and cell queries used by the simulation.

const ITEM_BLOCK := 0
const ITEM_BLOCK_ALT := 1
const ITEM_ONE_WAY := 2
const ITEM_LAVA := 3
const ITEM_SPIKES := 4
const ITEM_DECOR_A := 5
const ITEM_DECOR_B := 6
const ITEM_ACCENT_BASE := 10

const CRATE_SCENE: PackedScene = preload("res://scenes/hazards/crate.tscn")
const PAD_SCENE: PackedScene = preload("res://scenes/hazards/jump_pad.tscn")
const LAVA_SCENE: PackedScene = preload("res://scenes/hazards/lava.tscn")
const MOVER_SCENE: PackedScene = preload("res://scenes/hazards/moving_platform.tscn")
const BASE_LIBRARY: MeshLibrary = preload("res://assets/blocks/mesh_library.tres")

var data: MapData
var theme: MapTheme
var blocks: GridMap
var decor: GridMap
var far_decor: GridMap
var crates: Array[Crate] = []
var movers: Array[MovingPlatform] = []
var jump_pads: Dictionary = {}  # Vector2i cell -> JumpPad
var player_spawns: Array[Vector3] = []
var weapon_spawns: Array[Vector3] = []
var item_spawns: Array[Vector3] = []


static func load_map(map_id: String) -> MapData:
	return MapData.load_file("res://data/maps/%s.json" % map_id)


static func list_map_ids() -> Array[String]:
	var ids: Array[String] = []
	var dir := DirAccess.open("res://data/maps")
	if dir == null:
		return ids
	for f: String in dir.get_files():
		if f.ends_with(".json"):
			ids.append(f.get_basename())
	ids.sort()
	return ids


func build(map_data: MapData, decorations: bool, parallax: bool, particle_factor: float) -> void:
	data = map_data
	name = "Map"
	var theme_path: String = "res://data/themes/%s.tres" % data.theme
	theme = load(theme_path) if ResourceLoader.exists(theme_path) else MapTheme.new()
	var lib: MeshLibrary = _themed_library()
	blocks = GridMap.new()
	blocks.name = "Blocks"
	blocks.mesh_library = lib
	blocks.cell_size = Vector3.ONE
	blocks.cell_octant_size = 16
	blocks.position = Vector3(0, 0, -0.5)
	blocks.collision_layer = 1
	blocks.collision_mask = 0
	add_child(blocks)
	var hazards := Node3D.new()
	hazards.name = "Hazards"
	add_child(hazards)
	var accents: int = theme.accents.size()
	for row: int in range(data.height):
		var line: String = data.rows[row]
		var lava_run: int = 0
		for x: int in range(data.width + 1):
			var ch: String = line[x] if x < data.width else "."
			var gp := Vector3i(x, data.height - 1 - row, 0)
			match ch:
				"#":
					blocks.set_cell_item(gp, ITEM_BLOCK)
				"%":
					var item: int = ITEM_BLOCK_ALT
					if accents > 0:
						item = ITEM_ACCENT_BASE + ((int(x / 3.0) + row) % (accents + 1))
					blocks.set_cell_item(gp, item)
				"=":
					blocks.set_cell_item(gp, ITEM_ONE_WAY)
				"L":
					blocks.set_cell_item(gp, ITEM_LAVA)
				"^":
					blocks.set_cell_item(gp, ITEM_SPIKES)
				"C":
					var crate: Crate = CRATE_SCENE.instantiate()
					crate.index = crates.size()
					crate.position = data.cell_bottom(x, row)
					hazards.add_child(crate)
					crates.append(crate)
				"J":
					var pad: JumpPad = PAD_SCENE.instantiate()
					pad.position = data.cell_bottom(x, row)
					hazards.add_child(pad)
					jump_pads[Vector2i(x, row)] = pad
				"S":
					player_spawns.append(data.cell_bottom(x, row))
				"W":
					weapon_spawns.append(data.cell_bottom(x, row))
				"I":
					item_spawns.append(data.cell_bottom(x, row))
			# Lava strips: one bubbling node per horizontal run of surface lava.
			var is_surface_lava: bool = ch == "L" and data.cell(x, row - 1) != "L"
			if is_surface_lava:
				lava_run += 1
			elif lava_run > 0:
				var lava: Lava = LAVA_SCENE.instantiate()
				lava.position = data.cell_bottom(x - lava_run, row) - Vector3(0.5, 0, 0)
				hazards.add_child(lava)
				lava.setup(lava_run, theme.lava, particle_factor)
				lava_run = 0
	var mover_mat: ShaderMaterial = MaterialCache.flat(theme.platform.darkened(0.08))
	for m: Dictionary in data.movers:
		var mover: MovingPlatform = MOVER_SCENE.instantiate()
		mover.index = movers.size()
		hazards.add_child(mover)
		mover.setup(data, m.get("cells", []), m.get("path", []), float(m.get("speed", 2.0)), float(m.get("pause", 1.0)), mover_mat)
		movers.append(mover)
	if decorations:
		_build_decor(lib)
	if parallax:
		_build_far_layer(lib)


func _themed_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	var colors: Dictionary = {
		ITEM_BLOCK: theme.primary,
		ITEM_BLOCK_ALT: theme.secondary,
		ITEM_ONE_WAY: theme.platform,
		ITEM_LAVA: theme.lava,
		ITEM_DECOR_A: theme.decor_a.lerp(theme.bg_bottom, 0.35),
		ITEM_DECOR_B: theme.decor_b.lerp(theme.bg_top, 0.35),
	}
	for id: int in BASE_LIBRARY.get_item_list():
		lib.create_item(id)
		var mesh: Mesh = BASE_LIBRARY.get_item_mesh(id)
		if colors.has(id):
			var m: Mesh = mesh.duplicate()
			m.surface_set_material(0, MaterialCache.flat(colors[id]))
			mesh = m
		lib.set_item_mesh(id, mesh)
		lib.set_item_shapes(id, BASE_LIBRARY.get_item_shapes(id))
	# Rainbow accents (sorbet theme) as extra block variants.
	var accent_colors: Array[Color] = [theme.secondary]
	accent_colors.append_array(theme.accents)
	if not theme.accents.is_empty():
		for i: int in range(accent_colors.size()):
			var id2: int = ITEM_ACCENT_BASE + i
			lib.create_item(id2)
			var m2: Mesh = BASE_LIBRARY.get_item_mesh(ITEM_BLOCK_ALT).duplicate()
			m2.surface_set_material(0, MaterialCache.flat(accent_colors[i]))
			lib.set_item_mesh(id2, m2)
			lib.set_item_shapes(id2, BASE_LIBRARY.get_item_shapes(ITEM_BLOCK_ALT))
	return lib


## Decorative background layer (Z = -3 .. -8): hills, towers and clouds in
## lighter theme colours. Deterministic per map.
func _build_decor(lib: MeshLibrary) -> void:
	decor = GridMap.new()
	decor.name = "Decor"
	decor.mesh_library = lib
	decor.cell_size = Vector3.ONE
	decor.cell_octant_size = 32
	decor.collision_layer = 0
	decor.collision_mask = 0
	decor.position = Vector3(0, 0, -0.5)
	add_child(decor)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(data.id)
	var x: int = -12
	while x < data.width + 12:
		var w: int = rng.randi_range(4, 9)
		var h: int = rng.randi_range(3, 9)
		var z: int = -rng.randi_range(4, 7)
		var item: int = ITEM_DECOR_A if rng.randf() < 0.6 else ITEM_DECOR_B
		var stepped: bool = rng.randf() < 0.5
		for i: int in range(w):
			var col_h: int = h
			if stepped:
				col_h = maxi(1, h - absi(i - int(w / 2.0)))
			for y: int in range(-6, col_h):
				decor.set_cell_item(Vector3i(x + i, y, z), item)
		x += w + rng.randi_range(1, 5)
	# Clouds.
	var clouds: int = maxi(3, int(data.width / 14.0))
	for c: int in range(clouds):
		var cx: int = rng.randi_range(-6, data.width + 6)
		var cy: int = rng.randi_range(int(data.height / 2.0), data.height + 4)
		var cw: int = rng.randi_range(4, 8)
		for i: int in range(cw):
			decor.set_cell_item(Vector3i(cx + i, cy, -8), ITEM_DECOR_B)
			if i > 0 and i < cw - 1:
				decor.set_cell_item(Vector3i(cx + i, cy + 1, -8), ITEM_DECOR_B)


## Far parallax layer (High quality): big blocks far behind the playfield.
func _build_far_layer(lib: MeshLibrary) -> void:
	far_decor = GridMap.new()
	far_decor.name = "FarDecor"
	far_decor.mesh_library = lib
	far_decor.cell_size = Vector3(4, 4, 4)
	far_decor.cell_octant_size = 32
	far_decor.collision_layer = 0
	far_decor.collision_mask = 0
	far_decor.position = Vector3(0, -8, -30)
	add_child(far_decor)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(data.id + "_far")
	for x: int in range(-8, int(data.width / 4.0) + 8):
		var h: int = rng.randi_range(1, 4)
		for y: int in range(h):
			far_decor.set_cell_item(Vector3i(x, y, 0), ITEM_DECOR_A)


# ---------------------------------------------------------------- queries
func width() -> float:
	return float(data.width)


func height() -> float:
	return float(data.height)


func kill_line_y() -> float:
	return data.kill_line_y()


func char_at_world(wx: float, wy: float) -> String:
	var c: Vector2i = data.world_to_cell(wx, wy)
	return data.cell(c.x, c.y)


## Finds a one-way platform top crossed by the feet moving from prev_y down
## to new_y within [x0, x1]. Returns the top y or NAN.
func one_way_top_crossed(x0: float, x1: float, prev_y: float, new_y: float) -> float:
	var col0: int = floori(x0)
	var col1: int = floori(x1)
	# Platform tops are at integer y (top of a cell).
	var top_hi: int = floori(prev_y + 0.001)
	var top_lo: int = ceili(new_y)
	for top: int in range(top_hi, top_lo - 1, -1):
		var row: int = data.height - top
		for col: int in range(col0, col1 + 1):
			if data.cell(col, row) == "=" and float(top) <= prev_y + 0.001 and float(top) >= new_y:
				return float(top)
	return NAN


## True if any cell overlapped by the given world rect contains `ch`,
## considering only the lower `fill` part of each cell.
func rect_touches(ch: String, x0: float, y0: float, x1: float, y1: float, fill: float = 1.0) -> Vector2i:
	var c0: int = floori(x0)
	var c1: int = floori(x1)
	var r_top: int = data.height - 1 - floori(y1)
	var r_bot: int = data.height - 1 - floori(y0)
	for row: int in range(maxi(0, r_top), mini(data.height - 1, r_bot) + 1):
		var cell_y0: float = float(data.height - 1 - row)
		var cell_y1: float = cell_y0 + fill
		if y1 < cell_y0 or y0 > cell_y1:
			continue
		for col: int in range(maxi(0, c0), mini(data.width - 1, c1) + 1):
			if data.rows[row][col] == ch:
				return Vector2i(col, row)
	return Vector2i(-1, -1)
