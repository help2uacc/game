class_name RoundResultsOverlay
extends ColorRect
## Round Results (PRD §9.7): winner in their colour or DRAW with the tied
## names, table sorted by total kills, 6 s progress bar.

var _title: Label
var _table: VBoxContainer
var _bar: ProgressBar
var _t: float = 0.0
var _running: bool = false


func _init() -> void:
	color = Color(Palette.INK, 0.35)
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel: PanelContainer = UiKit.panel(36)
	var box: VBoxContainer = UiKit.vbox(16)
	box.custom_minimum_size = Vector2(1100, 0)
	panel.add_child(box)
	_title = UiKit.label("", "TitleLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_table = UiKit.vbox(6)
	box.add_child(_table)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 20)
	_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.GOLD
	fill.set_corner_radius_all(10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(Palette.INK, 0.12)
	bg.set_corner_radius_all(10)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", bg)
	box.add_child(_bar)
	add_child(UiKit.center(panel))


func show_results(data: Dictionary) -> void:
	var winners: Array = data.get("winners", [])
	var round_no: int = int(data.get("round", 0))
	if bool(data.get("draw", true)):
		var names: PackedStringArray = []
		for w: Variant in winners:
			names.append(GameState.player_name(int(w)))
		_title.text = "DRAW\n" + ", ".join(names)
		_title.remove_theme_color_override("font_color")
	else:
		var pid: int = int(winners[0])
		_title.text = "ROUND %d WINNER: %s" % [round_no, GameState.player_name(pid)]
		_title.add_theme_color_override("font_color", Palette.player_color(GameState.player_color(pid)).darkened(0.15))
	for c: Node in _table.get_children():
		_table.remove_child(c)
		c.queue_free()
	_table.add_child(_row(-1))
	for pid2: int in GameState.sorted_by_kills():
		_table.add_child(_row(pid2))
	_t = 0.0
	_running = true


func stop() -> void:
	_running = false


func _row(pid: int) -> Control:
	var row: HBoxContainer = UiKit.hbox(20)
	if pid < 0:
		row.add_child(UiKit.spacer(0))
		row.get_child(0).custom_minimum_size = Vector2(44, 0)
		row.add_child(UiKit.expand(UiKit.label("Player", "SmallLabel")))
		var h1: Label = UiKit.label("Round", "SmallLabel", HORIZONTAL_ALIGNMENT_RIGHT)
		h1.custom_minimum_size = Vector2(140, 0)
		var h2: Label = UiKit.label("Total", "SmallLabel", HORIZONTAL_ALIGNMENT_RIGHT)
		h2.custom_minimum_size = Vector2(140, 0)
		row.add_child(h1)
		row.add_child(h2)
		return row
	var p: Dictionary = GameState.get_player(pid)
	row.add_child(UiKit.swatch(Palette.player_color(int(p["color"])), 44))
	var n: Label = UiKit.label(str(p["name"]))
	if bool(p["released"]):
		n.modulate = Color(1, 1, 1, 0.45)
	row.add_child(UiKit.expand(n))
	var rk: Label = UiKit.label(str(int(p["round_kills"])), "", HORIZONTAL_ALIGNMENT_RIGHT)
	rk.custom_minimum_size = Vector2(140, 0)
	var tk: Label = UiKit.label(str(int(p["kills"])), "", HORIZONTAL_ALIGNMENT_RIGHT)
	tk.custom_minimum_size = Vector2(140, 0)
	row.add_child(rk)
	row.add_child(tk)
	return row


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	_bar.value = clampf(_t / GameConfig.ROUND_RESULTS_TIME, 0.0, 1.0)
