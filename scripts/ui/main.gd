extends Node
## Root scene: hosts the current screen.

var _screen: Node = null


func _ready() -> void:
	SceneRouter.register_main(self)
	SceneRouter.goto("main_menu")


func show_screen(scene: PackedScene) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = scene.instantiate()
	add_child(_screen)
