extends Control
## Match Results (PRD §9.8): podium with stickmen in player colours on blocky
## podium blocks (winner jumps, confetti cubes), WINNER or DRAW with tied
## names, full table (rank, colour, name, total kills, round wins),
## BACK TO LOBBY (host only) and LEAVE.

const STICKMAN_SCENE: PackedScene = preload("res://scenes/characters/stickman.tscn")
const PODIUM_HEIGHTS: Array[float] = [2.2, 1.5, 1.0]
const PODIUM_X: Array[float] = [0.0, -2.6, 2.6]

var _winner_man: Stickman = null
var _t: float = 0.0
var _confetti: CPUParticles3D


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var data: Dictionary = MatchManager.last_match_data
	var order: Array[int] = GameState.sorted_by_kills()
	_build_podium(order)
	var margin := MarginContainer.new()
	UiKit.full_rect(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var cols: HBoxContainer = UiKit.hbox(40)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(cols)
	var left: VBoxContainer = UiKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left)
	var title: Label = UiKit.label("", "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var winners: Array = data.get("winners", [])
	if bool(data.get("draw", true)):
		var names: PackedStringArray = []
		for w: Variant in winners:
			names.append(GameState.player_name(int(w)))
		title.text = "DRAW\n" + ", ".join(names)
	elif not winners.is_empty():
		var wp: int = int(winners[0])
		title.text = "WINNER: %s" % GameState.player_name(wp)
		title.add_theme_color_override("font_color", Palette.player_color(GameState.player_color(wp)).darkened(0.2))
	title.add_theme_color_override("font_outline_color", Palette.WHITE)
	title.add_theme_constant_override("outline_size", 16)
	left.add_child(title)
	var panel: PanelContainer = UiKit.panel(28)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(panel)
	var right: VBoxContainer = UiKit.vbox(10)
	panel.add_child(right)
	right.add_child(UiKit.label("RESULTS", "HeaderLabel"))
	right.add_child(_row(-1, 0))
	var rank: int = 0
	var prev_kills: int = -1
	for i: int in range(order.size()):
		var k: int = int(GameState.get_player(order[i])["kills"])
		if k != prev_kills:
			rank = i + 1
			prev_kills = k
		right.add_child(_row(order[i], rank))
	right.add_child(UiKit.spacer(10))
	var buttons: HBoxContainer = UiKit.hbox(20)
	if NetManager.is_host():
		buttons.add_child(UiKit.expand(UiKit.button("BACK TO LOBBY", MatchManager.server_back_to_lobby, "BigButton", Vector2(0, 104))))
	buttons.add_child(UiKit.expand(UiKit.button("LEAVE", func() -> void: NetManager.leave(""), "BigButton", Vector2(0, 104))))
	right.add_child(buttons)
	AudioManager.play_music("")
	AudioManager.play_ui("match_win")
	AudioManager.play_music("results_jingle")


func _row(pid: int, rank: int) -> Control:
	var row: HBoxContainer = UiKit.hbox(16)
	if pid < 0:
		for t: Array in [["#", 60], ["", 44], ["Player", 0], ["Kills", 130], ["Wins", 130]]:
			var h: Label = UiKit.label(t[0], "SmallLabel")
			if int(t[1]) > 0:
				h.custom_minimum_size = Vector2(int(t[1]), 0)
			else:
				UiKit.expand(h)
			row.add_child(h)
		return row
	var p: Dictionary = GameState.get_player(pid)
	var r: Label = UiKit.label("%d." % rank)
	r.custom_minimum_size = Vector2(60, 0)
	row.add_child(r)
	row.add_child(UiKit.swatch(Palette.player_color(int(p["color"])), 44))
	var n: Label = UiKit.label(str(p["name"]))
	if bool(p["released"]) or not bool(p["connected"]):
		n.modulate = Color(1, 1, 1, 0.45)
	row.add_child(UiKit.expand(n))
	var k: Label = UiKit.label(str(int(p["kills"])), "", HORIZONTAL_ALIGNMENT_RIGHT)
	k.custom_minimum_size = Vector2(130, 0)
	row.add_child(k)
	var w: Label = UiKit.label(str(int(p["round_wins"])), "", HORIZONTAL_ALIGNMENT_RIGHT)
	w.custom_minimum_size = Vector2(130, 0)
	row.add_child(w)
	return row


func _build_podium(order: Array[int]) -> void:
	var root3d := Node3D.new()
	add_child(root3d)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.position = Vector3(4.0, 3.4, 24)
	cam.rotation = Vector3(deg_to_rad(-6.0), 0, 0)
	cam.current = true
	root3d.add_child(cam)
	var sky := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(240, 160)
	sky.mesh = quad
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/sky_gradient.gdshader")
	sky.material_override = sm
	sky.position = Vector3(0, 0, -150)
	cam.add_child(sky)
	var colors: Array[Color] = [Palette.GOLD, Color("#DDE3F0"), Color("#E8BE8A")]
	for i: int in range(3):
		var h: float = PODIUM_HEIGHTS[i]
		var block := MeshInstance3D.new()
		block.mesh = BoxBuilder.build([[Vector3(0, h * 0.5, 0), Vector3(2.4, h, 2.0), colors[i]],
				[Vector3(0, h * 0.5, 1.01), Vector3(0.6, 0.6, 0.02), Palette.WHITE]], MaterialCache.vertex())
		block.position = Vector3(PODIUM_X[i], 0, 0)
		root3d.add_child(block)
		if i < order.size():
			var s: Stickman = STICKMAN_SCENE.instantiate()
			s.color_id = GameState.player_color(order[i])
			root3d.add_child(s)
			s.position = Vector3(PODIUM_X[i], h, 0.2)
			s.set_player_name(GameState.player_name(order[i]), order[i] == GameState.local_pid)
			s.shadow_enabled = false
			if i == 0:
				_winner_man = s
	var ground := MeshInstance3D.new()
	ground.mesh = BoxBuilder.build([[Vector3(0, -0.5, 0), Vector3(30, 1, 6), Color("#BDF0D8")]], MaterialCache.vertex())
	root3d.add_child(ground)
	_confetti = CPUParticles3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.14, 0.14, 0.14)
	_confetti.mesh = cube
	_confetti.material_override = MaterialCache.vertex()
	_confetti.amount = int(120 * Settings.particle_factor())
	_confetti.lifetime = 3.0
	_confetti.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_confetti.emission_box_extents = Vector3(7, 0.2, 1.5)
	_confetti.position = Vector3(0, 7.0, 0)
	_confetti.direction = Vector3(0, -1, 0)
	_confetti.initial_velocity_min = 0.5
	_confetti.initial_velocity_max = 2.0
	_confetti.gravity = Vector3(0, -2.5, 0)
	_confetti.angular_velocity_min = -200
	_confetti.angular_velocity_max = 200
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([Palette.PLAYER_COLORS[0], Palette.PLAYER_COLORS[2], Palette.PLAYER_COLORS[3],
			Palette.PLAYER_COLORS[5], Palette.PLAYER_COLORS[6]])
	_confetti.color_initial_ramp = grad
	root3d.add_child(_confetti)
	_confetti.emitting = true


## Winner does a jump animation (§9.8).
func _process(delta: float) -> void:
	_t += delta
	if _winner_man != null:
		var phase: float = fmod(_t, 1.1)
		var y: float = maxf(0.0, sin(phase / 0.7 * PI)) * 1.1 if phase < 0.7 else 0.0
		_winner_man.position.y = PODIUM_HEIGHTS[0] + y
		_winner_man.set_motion(phase >= 0.7, Vector2(0, 5.0 if phase < 0.35 else -5.0))
		if phase < delta:
			_winner_man.play(Stickman.Anim.LAND)


func handle_back() -> void:
	pass
