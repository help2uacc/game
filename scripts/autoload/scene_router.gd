extends Node
## Screen transitions (0.2 s fade, PRD §9) and toasts (§9.10).

signal screen_changed(screen_name: String)

const SCREENS: Dictionary = {
	"main_menu": "res://scenes/ui/main_menu.tscn",
	"join": "res://scenes/ui/join.tscn",
	"lobby": "res://scenes/ui/lobby.tscn",
	"game": "res://scenes/ui/game.tscn",
	"match_results": "res://scenes/ui/match_results.tscn",
	"settings": "res://scenes/ui/settings.tscn",
}
const FADE_TIME := 0.2

var current_name: String = ""
var current: Node = null
var _main: Node = null
var _fade: ColorRect
var _toast_box: VBoxContainer
var _layer: CanvasLayer
var _tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Palette.BG_SKY
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_layer.add_child(_fade)
	var toast_root := MarginContainer.new()
	toast_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_root.add_theme_constant_override("margin_top", 120)
	_layer.add_child(toast_root)
	_toast_box = VBoxContainer.new()
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_box.add_theme_constant_override("separation", 10)
	toast_root.add_child(_toast_box)


func register_main(main: Node) -> void:
	_main = main


## Switches screens immediately (logic) with a 0.2 s visual fade.
func goto(screen: String) -> Node:
	if _main == null or not SCREENS.has(screen):
		return null
	if current != null and is_instance_valid(current):
		current.queue_free()
	var scene: PackedScene = load(SCREENS[screen])
	current = scene.instantiate()
	current_name = screen
	_main.add_child(current)
	_flash_fade()
	screen_changed.emit(screen)
	return current


## Switches to an arbitrary scene (debug sandbox).
func goto_scene(path: String) -> Node:
	if _main == null:
		return null
	if current != null and is_instance_valid(current):
		current.queue_free()
	var scene: PackedScene = load(path)
	current = scene.instantiate()
	current_name = path
	_main.add_child(current)
	_flash_fade()
	return current


func _flash_fade() -> void:
	if _tween != null:
		_tween.kill()
	_fade.modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_property(_fade, "modulate:a", 0.0, FADE_TIME)


func toast(text: String, duration: float = 2.5) -> void:
	if text.is_empty():
		return
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.INK, 0.88)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.WHITE)
	l.add_theme_font_size_override("font_size", 34)
	panel.add_child(l)
	_toast_box.add_child(panel)
	while _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).queue_free()
		_toast_box.remove_child(_toast_box.get_child(0))
	var tw: Tween = panel.create_tween()
	tw.tween_interval(duration)
	tw.tween_property(panel, "modulate:a", 0.0, 0.3)
	tw.tween_callback(panel.queue_free)
