extends SceneTree
## Renders a scene to a PNG for visual checks:
## xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 -s tools/preview/screenshot.gd -- <scene> <out.png> [frames]

var _frames: int = 0
var _target: int = 90
var _out: String = "res://build/screenshot.png"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://scenes/main/sandbox.tscn"
	if args.size() > 1:
		_out = args[1]
	if args.size() > 2:
		_target = args[2].to_int()
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
