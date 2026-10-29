extends Control
## Main Menu (PRD §9.2): animated pastel block landscape with idle stickmen,
## blocky logo, HOST GAME / JOIN GAME / SETTINGS / QUIT, REJOIN when a
## recent session exists, first-launch name prompt.

const STICKMAN_SCENE: PackedScene = preload("res://scenes/characters/stickman.tscn")
const SCROLL_SPEED := 1.2
const STRIP_WIDTH := 64

var _bg3d: Node3D
var _strip: Node3D
var _rejoin_btn: BBButton
var _name_dialog: Control
var _name_edit: LineEdit
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7
	_build_background()
	var root: VBoxContainer = UiKit.vbox(22)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/logo.png")
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.custom_minimum_size = Vector2(1080, 170)
	root.add_child(logo)
	root.add_child(UiKit.spacer(20))
	_rejoin_btn = UiKit.button("REJOIN", _on_rejoin, "BigButton", Vector2(560, 110))
	root.add_child(_rejoin_btn)
	root.add_child(UiKit.button("HOST GAME", _on_host, "BigButton", Vector2(560, 110)))
	root.add_child(UiKit.button("JOIN GAME", _on_join, "BigButton", Vector2(560, 110)))
	var row: HBoxContainer = UiKit.hbox(20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiKit.button("SETTINGS", _on_settings, "", Vector2(270, 96)))
	row.add_child(UiKit.button("QUIT", _on_quit, "", Vector2(270, 96)))
	root.add_child(row)
	if OS.is_debug_build():
		root.add_child(UiKit.button("SANDBOX (debug)", _on_sandbox, "", Vector2(560, 80)))
	var center: CenterContainer = UiKit.center(root)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_build_name_dialog()
	_update_rejoin()
	AudioManager.play_music("menu_loop")
	if not Settings.has_player_name():
		_show_name_prompt()
	_handle_debug_args()


func _update_rejoin() -> void:
	_rejoin_btn.visible = not NetManager.saved_session().is_empty()


# ---------------------------------------------------------------- background
func _build_background() -> void:
	_bg3d = Node3D.new()
	_bg3d.name = "Background"
	add_child(_bg3d)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.position = Vector3(0, 4.5, 20)
	cam.rotation = Vector3(deg_to_rad(-4.0), 0, 0)
	cam.current = true
	_bg3d.add_child(cam)
	var sky := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(240, 160)
	sky.mesh = quad
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/sky_gradient.gdshader")
	sky.material_override = sm
	sky.position = Vector3(0, 0, -150)
	cam.add_child(sky)
	_strip = Node3D.new()
	_bg3d.add_child(_strip)
	var colors: Array[Color] = [Color("#F7A8C4"), Color("#A9E5A0"), Color("#A7D3FF"), Color("#FFE39A"), Color("#C7B8F5")]
	var st: SurfaceTool = BoxBuilder.begin()
	for x: int in range(STRIP_WIDTH):
		var c: Color = colors[int(x / 6.0) % colors.size()]
		# Flat ground row (top at y = 0).
		for y: int in range(-4, 0):
			BoxBuilder.add_box(st, Vector3(float(x) + 0.5, float(y) + 0.5, 0), Vector3.ONE, c if y == -1 else c.darkened(0.06))
		# Rolling hills behind, lighter.
		var hh: int = 2 + int(round(sin(float(x) * 0.21 + 1.0) * 1.6 + sin(float(x) * 0.07) * 1.2))
		for y2: int in range(-4, hh):
			BoxBuilder.add_box(st, Vector3(float(x) + 0.5, float(y2) + 0.5, -7), Vector3.ONE, c.lerp(Color.WHITE, 0.5))
		# Clouds.
		if x % 13 < 5:
			BoxBuilder.add_box(st, Vector3(float(x) + 0.5, 9.5 + float(x % 3) * 0.5, -14), Vector3(1, 1, 1), Color("#FFFFFF"))
	var mesh: ArrayMesh = BoxBuilder.finish(st, MaterialCache.vertex())
	for copy: int in range(2):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(float(copy * STRIP_WIDTH) - float(STRIP_WIDTH) * 0.5, 0.0, 0)
		_strip.add_child(mi)
	# Idle stickmen in different colours.
	for i: int in range(6):
		var s: Stickman = STICKMAN_SCENE.instantiate()
		s.color_id = (i * 3) % Palette.COLOR_COUNT
		_bg3d.add_child(s)
		s.position = Vector3(-8.5 + float(i) * 3.4, 0.0, 1.0)
		s.set_facing(1 if i % 2 == 0 else -1)
		s.set_name_visible(false)
		s.shadow_enabled = false


func _process(delta: float) -> void:
	_strip.position.x -= SCROLL_SPEED * delta
	if _strip.position.x <= -float(STRIP_WIDTH):
		_strip.position.x += float(STRIP_WIDTH)


# ---------------------------------------------------------------- name prompt
func _build_name_dialog() -> void:
	_name_dialog = ColorRect.new()
	(_name_dialog as ColorRect).color = Color(Palette.INK, 0.5)
	UiKit.full_rect(_name_dialog)
	_name_dialog.visible = false
	add_child(_name_dialog)
	var panel: PanelContainer = UiKit.panel(40)
	var box: VBoxContainer = UiKit.vbox(20)
	box.custom_minimum_size = Vector2(760, 0)
	panel.add_child(box)
	box.add_child(UiKit.label("What's your name?", "HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.label("1–12 characters: letters, digits, space, _ or -", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 12
	_name_edit.custom_minimum_size = Vector2(0, 90)
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.text_submitted.connect(func(_t: String) -> void: _confirm_name())
	box.add_child(_name_edit)
	box.add_child(UiKit.button("OK", _confirm_name, "BigButton"))
	_name_dialog.add_child(UiKit.center(panel))


func _show_name_prompt() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_name_edit.text = Rules.default_player_name(rng)
	_name_dialog.visible = true


func _confirm_name() -> void:
	var n: String = _name_edit.text.strip_edges()
	if not Rules.is_valid_name(n):
		SceneRouter.toast("Use 1–12 letters, digits, space, _ or -")
		return
	Settings.player_name = n
	Settings.apply()
	_name_dialog.visible = false


# ---------------------------------------------------------------- actions
func _ensure_name() -> bool:
	if Settings.has_player_name():
		return true
	_show_name_prompt()
	return false


func _on_host() -> void:
	if not _ensure_name():
		return
	if NetManager.host() != OK:
		SceneRouter.toast("Could not start host. Check your network.")


func _on_join() -> void:
	if _ensure_name():
		SceneRouter.goto("join")


func _on_rejoin() -> void:
	if not _ensure_name():
		return
	if NetManager.rejoin_saved() != OK:
		_update_rejoin()
		SceneRouter.toast("Could not connect")
	else:
		SceneRouter.toast("Reconnecting…", 1.5)


func _on_settings() -> void:
	SceneRouter.goto("settings")


func _on_quit() -> void:
	get_tree().quit()


func _on_sandbox() -> void:
	SceneRouter.goto_scene("res://scenes/main/sandbox.tscn")


func handle_back() -> void:
	if _name_dialog.visible and Settings.has_player_name():
		_name_dialog.visible = false


## Debug-build automation for the multi-instance smoke test:
## --name=X --host | --join=IP [--autostart=N] [--rounds=N] [--bot]
func _handle_debug_args() -> void:
	if not OS.is_debug_build():
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("--name="):
			Settings.player_name = a.trim_prefix("--name=")
			_name_dialog.visible = false
	for a2: String in args:
		if a2 == "--host":
			_on_host.call_deferred()
		elif a2.begins_with("--join="):
			NetManager.join.call_deferred(a2.trim_prefix("--join="))
