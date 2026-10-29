class_name TouchButton
extends Control
## Semi-transparent rounded touch button (PRD §8): white rounded square at
## 35 % opacity with an icon; pressed state 70 % opacity + scale 0.92.

signal pressed_changed(is_pressed: bool)

var icon: Texture2D = null:
	set(v):
		icon = v
		queue_redraw()
var is_pressed: bool = false
var touch_index: int = -1
var _style := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.bg_color = Color(1, 1, 1, 1)
	_style.set_corner_radius_all(28)


func setup(button_size: float, tex: Texture2D) -> void:
	size = Vector2(button_size, button_size)
	pivot_offset = size * 0.5
	icon = tex


func set_pressed(p: bool) -> void:
	if p == is_pressed:
		return
	is_pressed = p
	scale = Vector2.ONE * (0.92 if p else 1.0)
	queue_redraw()
	pressed_changed.emit(p)


func hit(pos: Vector2) -> bool:
	return visible and get_global_rect().grow(12).has_point(pos)


func _draw() -> void:
	var a: float = 0.7 if is_pressed else 0.35
	_style.bg_color = Color(1, 1, 1, a)
	_style.set_corner_radius_all(int(size.x * 0.22))
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	if icon != null:
		var s: float = size.x * 0.6
		draw_texture_rect(icon, Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, 0.9))
