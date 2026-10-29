class_name TouchButton
extends Control
## Round touch button (PRD §8, restyled in v1.2): soft drop shadow, white
## rim, pastel accent fill with a top highlight, icon and optional caption.
## Pressed: deeper fill, glow ring and scale 0.92.

signal pressed_changed(is_pressed: bool)

var icon: Texture2D = null:
	set(v):
		icon = v
		queue_redraw()
var accent: Color = Palette.WHITE
var caption: String = ""
var is_pressed: bool = false
var touch_index: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(button_size: float, tex: Texture2D, accent_color: Color = Palette.WHITE, text: String = "") -> void:
	size = Vector2(button_size, button_size)
	pivot_offset = size * 0.5
	icon = tex
	accent = accent_color
	caption = text


func set_pressed(p: bool) -> void:
	if p == is_pressed:
		return
	is_pressed = p
	scale = Vector2.ONE * (0.92 if p else 1.0)
	queue_redraw()
	pressed_changed.emit(p)


## Circular hit area with a little slack for thumbs.
func hit(pos: Vector2) -> bool:
	if not visible:
		return false
	var c: Vector2 = global_position + size * 0.5
	return pos.distance_to(c) <= size.x * 0.5 + 18.0


func _draw() -> void:
	var r: float = size.x * 0.5
	var c: Vector2 = size * 0.5
	# Soft shadow.
	draw_circle(c + Vector2(0, r * 0.07), r * 1.02, Color(Palette.INK, 0.28), true, -1.0, true)
	# Glow ring when pressed.
	if is_pressed:
		draw_circle(c, r * 1.12, Color(accent.lightened(0.3), 0.45), true, -1.0, true)
	# Rim + fill.
	draw_circle(c, r, Color(Palette.WHITE, 0.92), true, -1.0, true)
	var fill: Color = accent.darkened(0.12) if is_pressed else accent
	draw_circle(c, r * 0.88, Color(fill, 0.9), true, -1.0, true)
	# Top highlight for a soft, glossy look.
	draw_circle(c - Vector2(0, r * 0.3), r * 0.55, Color(1, 1, 1, 0.16 if not is_pressed else 0.08), true, -1.0, true)
	# Icon (ink with white outline) and caption.
	var icon_size: float = r * (1.0 if caption.is_empty() else 0.86)
	var icon_center: Vector2 = c - Vector2(0, r * (0.0 if caption.is_empty() else 0.14))
	if icon != null:
		draw_texture_rect(icon, Rect2(icon_center - Vector2(icon_size, icon_size) * 0.5, Vector2(icon_size, icon_size)), false)
	if not caption.is_empty():
		var font: Font = get_theme_default_font()
		var fs: int = int(r * 0.24)
		var w: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p: Vector2 = Vector2(c.x - w * 0.5, c.y + r * 0.62)
		draw_string_outline(font, p, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Palette.INK)
		draw_string(font, p, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.WHITE)
