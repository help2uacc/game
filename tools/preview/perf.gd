extends SceneTree
## Measures draw calls / primitives for every map with 8 players in the
## sandbox (rendering required): xvfb-run -a godot --rendering-driver opengl3 \
##   --resolution 1920x1080 -s tools/preview/perf.gd -- [--quality=0|1|2]

const MAPS: PackedStringArray = [
	"candy_plains", "mint_towers", "lava_lagoon", "cloud_hop", "crate_yard", "spike_factory",
	"bubblegum_bridges", "lilac_caves", "peach_pyramid", "sky_lifts", "bounce_garden", "sorbet_arena",
]

var _i: int = -1
var _frames: int = 0
var _screen: Node = null
var _max_dc: int = 0
var _max_prim: int = 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _i == -1 or _frames > 150:
		if _screen != null:
			print("%-20s draw_calls=%d primitives=%d (max over frames)" % [MAPS[_i], _max_dc, _max_prim])
			_screen.queue_free()
			_screen = null
		_i += 1
		_frames = 0
		_max_dc = 0
		_max_prim = 0
		if _i >= MAPS.size():
			quit()
			return false
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--quality="):
				root.get_node("Settings").set("quality", a.trim_prefix("--quality=").to_int())
		var scene: PackedScene = load("res://scenes/main/sandbox.tscn")
		_screen = scene.instantiate()
		_screen.set("sandbox_map", MAPS[_i])
		root.add_child(_screen)
		return false
	if _frames > 30:
		_max_dc = maxi(_max_dc, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_max_prim = maxi(_max_prim, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	return false
