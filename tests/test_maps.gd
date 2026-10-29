extends TestCase
## Map JSON parsing + validation for all 12 maps (PRD §10, §14.1).

const MAP_IDS: PackedStringArray = [
	"candy_plains", "mint_towers", "lava_lagoon", "cloud_hop", "crate_yard", "spike_factory",
	"bubblegum_bridges", "lilac_caves", "peach_pyramid", "sky_lifts", "bounce_garden", "sorbet_arena",
]


func test_twelve_maps_exist() -> void:
	var ids: Array[String] = GameMap.list_map_ids()
	assert_eq(ids.size(), 12, "12 maps ship")
	for id: String in MAP_IDS:
		assert_true(ids.has(id), "missing map " + id)


func test_all_maps_parse_and_validate() -> void:
	for id: String in MAP_IDS:
		var md: MapData = GameMap.load_map(id)
		assert_eq(md.parse_error, "", id + " parse")
		var errors: PackedStringArray = md.validate()
		assert_true(errors.is_empty(), "%s: %s" % [id, str(errors)])
		assert_eq(md.id, id)
		assert_true(md.width >= 70 and md.width <= 100, id + " width")
		assert_true(md.height >= 30 and md.height <= 45, id + " height")
		assert_true(md.count_of("S") >= 8 and md.count_of("W") >= 10 and md.count_of("I") >= 3, id + " points")
		assert_true(ResourceLoader.exists("res://data/themes/%s.tres" % md.theme), id + " theme")


func test_maps_are_roughly_mirror_symmetric() -> void:
	for id: String in MAP_IDS:
		var md: MapData = GameMap.load_map(id)
		var same: int = 0
		var total: int = 0
		for r: int in range(md.height):
			for x: int in range(md.width):
				var a: String = md.cell(x, r)
				var b: String = md.cell(md.width - 1 - x, r)
				if a == "." and b == ".":
					continue
				total += 1
				if (a == "." ) == (b == "."):
					same += 1
		assert_true(float(same) / float(maxi(total, 1)) > 0.9, "%s symmetric (%d/%d)" % [id, same, total])


func test_hazards_per_theme() -> void:
	assert_true(GameMap.load_map("lava_lagoon").count_of("L") > 0, "lava lagoon has lava")
	assert_true(GameMap.load_map("lilac_caves").count_of("L") > 0, "caves have lava at the bottom")
	assert_true(GameMap.load_map("cloud_hop").movers.size() >= 2, "cloud hop has movers")
	assert_true(GameMap.load_map("crate_yard").count_of("C") >= 10, "crate yard has many crates")
	assert_true(GameMap.load_map("spike_factory").count_of("^") > 0, "spike factory spikes")
	assert_true(GameMap.load_map("spike_factory").movers.size() >= 2, "spike factory movers")
	assert_true(GameMap.load_map("peach_pyramid").count_of("^") > 0, "pyramid base spikes")
	assert_true(GameMap.load_map("sky_lifts").movers.size() >= 2, "sky lifts")
	assert_true(GameMap.load_map("bounce_garden").count_of("J") >= 2, "bounce garden jump pads")
	var sorbet: MapData = GameMap.load_map("sorbet_arena")
	assert_true(sorbet.count_of("L") > 0 and sorbet.count_of("^") > 0 and sorbet.count_of("C") > 0
			and sorbet.count_of("J") > 0 and sorbet.movers.size() > 0 and sorbet.count_of("=") > 0, "sorbet uses all hazards")


func test_validation_catches_errors() -> void:
	var md := MapData.from_json('{"id":"x","name":"X","theme":"candy","layout":["..","...","x."]}')
	var errors: PackedStringArray = md.validate()
	assert_true(errors.size() >= 3, "row length, size, legend, counts reported")
	var bad_json := MapData.from_json("{nope")
	assert_false(bad_json.parse_error.is_empty(), "parse error reported")
	assert_false(bad_json.is_valid())


func test_every_map_builds() -> void:
	for id: String in MAP_IDS:
		var w := World.new()
		add_node(w)
		assert_true(w.load_map(id), id + " builds")
		assert_eq(w.map.player_spawns.size(), w.map.data.count_of("S"))
		assert_eq(w.map.crates.size(), w.map.data.count_of("C"))
		assert_eq(w.map.movers.size(), w.map.data.movers.size())
		w.queue_free()
