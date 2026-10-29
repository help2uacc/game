extends Control
## Settings (PRD §9.9), persisted to user://settings.cfg. Usable as a screen
## (from the main menu) or as an overlay (from the in-match menu).

@export var as_overlay: bool = false

var _name_edit: LineEdit
var _content: VBoxContainer


func _ready() -> void:
	UiKit.full_rect(self)
	var bg := ColorRect.new()
	bg.color = Color(Palette.INK, 0.5) if as_overlay else Palette.BG_SKY
	UiKit.full_rect(bg)
	add_child(bg)
	var margin := MarginContainer.new()
	UiKit.full_rect(margin)
	margin.add_theme_constant_override("margin_left", 160)
	margin.add_theme_constant_override("margin_right", 160)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var root: VBoxContainer = UiKit.vbox(20)
	margin.add_child(root)
	var top: HBoxContainer = UiKit.hbox(24)
	top.add_child(UiKit.icon_button("back", handle_back, 96))
	top.add_child(UiKit.expand(UiKit.label("SETTINGS", "TitleLabel")))
	top.add_child(UiKit.button("RESET TO DEFAULTS", _reset, "", Vector2(0, 88)))
	root.add_child(top)
	var panel: PanelContainer = UiKit.panel(32)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_content = UiKit.vbox(18)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_build()


func _build() -> void:
	for c: Node in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_section("Player")
	_name_edit = LineEdit.new()
	_name_edit.max_length = 12
	_name_edit.text = Settings.player_name
	_name_edit.custom_minimum_size = Vector2(520, 84)
	_name_edit.text_changed.connect(_on_name)
	_row("Name", _name_edit)
	_section("Audio")
	_row("Master", _slider(0.0, 1.0, 0.01, Settings.master_volume, func(v: float) -> void: Settings.master_volume = v, true))
	_row("Music", _slider(0.0, 1.0, 0.01, Settings.music_volume, func(v: float) -> void: Settings.music_volume = v, true))
	_row("SFX", _slider(0.0, 1.0, 0.01, Settings.sfx_volume, func(v: float) -> void: Settings.sfx_volume = v, true))
	_section("Controls")
	_row("Joystick sensitivity", _slider(0.5, 1.5, 0.05, Settings.joystick_sensitivity,
			func(v: float) -> void: Settings.joystick_sensitivity = v, false))
	_row("Vibration", _toggle(Settings.vibration, func(on: bool) -> void: Settings.vibration = on))
	_section("Graphics")
	var q := OptionButton.new()
	for item: String in ["Low", "Medium", "High"]:
		q.add_item(item)
	q.selected = Settings.quality
	q.custom_minimum_size = Vector2(320, 84)
	q.item_selected.connect(func(i: int) -> void:
		Settings.quality = i
		Settings.apply())
	_row("Quality", q)
	_section("HUD")
	_row("HUD scale", _slider(0.8, 1.2, 0.05, Settings.hud_scale, func(v: float) -> void: Settings.hud_scale = v, true))
	for e: String in Settings.HUD_ELEMENTS:
		var key: String = e
		_row(str(Settings.HUD_LABELS[e]), _toggle(Settings.hud_enabled(e), func(on: bool) -> void: Settings.hud[key] = on))


func _section(title: String) -> void:
	_content.add_child(UiKit.spacer(6))
	_content.add_child(UiKit.label(title, "HeaderLabel"))


func _row(title: String, control: Control) -> void:
	var row: HBoxContainer = UiKit.hbox(24)
	var l: Label = UiKit.label(title)
	l.custom_minimum_size = Vector2(520, 0)
	row.add_child(l)
	row.add_child(control)
	_content.add_child(row)


func _slider(min_v: float, max_v: float, step: float, value: float, setter: Callable, percent: bool) -> Control:
	var box: HBoxContainer = UiKit.hbox(16)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(560, 64)
	var val: Label = UiKit.label("")
	val.custom_minimum_size = Vector2(140, 0)
	var fmt: Callable = func(v: float) -> String: return ("%d %%" % int(round(v * 100.0))) if percent else ("%.2f×" % v)
	val.text = fmt.call(value)
	s.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		val.text = fmt.call(v)
		Settings.apply())
	box.add_child(s)
	box.add_child(val)
	return box


func _toggle(value: bool, setter: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool) -> void:
		AudioManager.play_ui("ui_toggle")
		setter.call(on)
		Settings.apply())
	return c


func _on_name(text: String) -> void:
	if Rules.is_valid_name(text):
		Settings.player_name = text
		Settings.apply()
		if GameState.phase == GameState.Phase.LOBBY:
			GameState.request_name(text)


func _reset() -> void:
	Settings.reset_to_defaults(true)
	Settings.apply()
	_build()


func handle_back() -> void:
	AudioManager.play_ui("ui_back")
	if as_overlay:
		queue_free()
	else:
		SceneRouter.goto("main_menu")
