extends SceneTree
## Renders the round results overlay and the match results screen with a
## fake roster: build/round_results.png, build/match_results.png.

var _frames: int = 0
var _overlay: Control


func _setup() -> void:
	var gs: Node = root.get_node("GameState")
	gs.call("reset")
	var names: PackedStringArray = ["Joe", "Ann", "Max", "Lia", "Kim", "Bo"]
	for i: int in range(names.size()):
		var pid: int = gs.call("server_add_player", names[i], i == 0)
		gs.get("players")[pid]["kills"] = [7, 9, 9, 3, 1, 0][i]
		gs.get("players")[pid]["round_kills"] = [1, 2, 2, 0, 0, 0][i]
		gs.get("players")[pid]["round_wins"] = [2, 3, 2, 1, 0, 0][i]
	gs.set("local_pid", 1)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_overlay = (load("res://scripts/ui/round_results_overlay.gd") as GDScript).new()
	layer.add_child(_overlay)
	_overlay.call("show_results", {"round": 3, "winners": [2, 3], "draw": true})


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_setup()
	if _frames == 20:
		root.get_texture().get_image().save_png("res://build/round_results.png")
		_overlay.get_parent().queue_free()
		var mm: Node = root.get_node("MatchManager")
		mm.set("last_match_data", {"winners": [2, 3], "draw": false})
		mm.set("last_match_data", {"winners": [2], "draw": false})
		var scene: PackedScene = load("res://scenes/ui/match_results.tscn")
		root.add_child(scene.instantiate())
	if _frames == 80:
		root.get_texture().get_image().save_png("res://build/match_results.png")
		print("saved")
		quit()
	return false
