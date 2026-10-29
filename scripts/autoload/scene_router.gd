extends Node
## Screen transitions (0.2 s fade, §9) and toasts.

const SCREENS: Dictionary = {
	"main_menu": "res://scenes/ui/main_menu.tscn",
}

var _main: Node = null


func register_main(main: Node) -> void:
	_main = main


func goto(screen: String) -> void:
	if _main == null or not SCREENS.has(screen):
		return
	_main.call("show_screen", load(SCREENS[screen]) as PackedScene)


func toast(text: String) -> void:
	print("[toast] ", text)
