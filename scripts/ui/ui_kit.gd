class_name UiKit
extends RefCounted
## Small helpers to build the flat pastel UI in code (PRD §9).

const ICON_DIR := "res://assets/ui/icons/"


static func icon(icon_name: String) -> Texture2D:
	var path: String = ICON_DIR + icon_name + ".svg"
	return load(path) if ResourceLoader.exists(path) else null


static func label(text: String, variation: String = "", align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not variation.is_empty():
		l.theme_type_variation = variation
	return l


static func button(text: String, callback: Callable, variation: String = "", min_size: Vector2 = Vector2(0, 88)) -> BBButton:
	var b := BBButton.new()
	b.text = text
	b.custom_minimum_size = min_size
	if not variation.is_empty():
		b.theme_type_variation = variation
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


static func icon_button(icon_name: String, callback: Callable, button_size: float = 96.0) -> BBButton:
	var b := BBButton.new()
	b.icon = icon(icon_name)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(button_size, button_size)
	b.add_theme_constant_override("icon_max_width", int(button_size * 0.6))
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


static func panel(margin: int = 32) -> PanelContainer:
	var p := PanelContainer.new()
	var sb: StyleBoxFlat = (ThemeDB.get_project_theme().get_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate() \
			if ThemeDB.get_project_theme() != null else StyleBoxFlat.new()
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	p.add_theme_stylebox_override("panel", sb)
	return p


static func vbox(sep: int = 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func center(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c


static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c


static func swatch(color: Color, swatch_size: float = 48.0, radius: int = 10) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(swatch_size, swatch_size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Safe-area insets (notches) in design pixels: (left, top, right, bottom).
## Defensive (v1.2): some Android versions report an empty or portrait-oriented
## safe area for a landscape window; such values are ignored and every inset
## is clamped to 12 % of the screen so controls can never be pushed off-screen.
static func safe_insets(vp: Viewport) -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	if (safe.size.x > safe.size.y) != (win.x > win.y):
		return Vector4.ZERO
	if safe.size.x < int(win.x * 0.7) or safe.size.y < int(win.y * 0.7):
		return Vector4.ZERO
	var size: Vector2 = vp.get_visible_rect().size
	var sx: float = size.x / float(win.x)
	var sy: float = size.y / float(win.y)
	var max_x: float = size.x * 0.12
	var max_y: float = size.y * 0.12
	return Vector4(
		clampf(float(safe.position.x) * sx, 0.0, max_x),
		clampf(float(safe.position.y) * sy, 0.0, max_y),
		clampf(float(win.x - safe.end.x) * sx, 0.0, max_x),
		clampf(float(win.y - safe.end.y) * sy, 0.0, max_y))
