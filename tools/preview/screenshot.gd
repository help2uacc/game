extends SceneTree
## Renders a scene to a PNG for visual checks:
## xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 -s tools/preview/screenshot.gd -- \
##     --scene=res://scenes/main/main.tscn --out=res://build/shot.png --frames=90 [game args]

var _frames: int = 0
var _target: int = 90
var _out: String = "res://build/screenshot.png"


func _initialize() -> void:
	var scene_path: String = "res://scenes/main/main.tscn"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.trim_prefix("--scene=")
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--frames="):
			_target = a.trim_prefix("--frames=").to_int()
	var scene: PackedScene = load(scene_path)
	root.add_child.call_deferred(scene.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == _target:
		var img: Image = root.get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		quit()
	return false
