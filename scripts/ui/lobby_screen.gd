extends Control
## Lobby (PRD §9.5): 8 player slots, colour picker (taken colours locked with
## the owner's name), live name editing, ready toggle (clients), rounds
## stepper 4–99 (host, long-press for fast change), START (host), Leave.

var _title: Label
var _subtitle: Label
var _slots: VBoxContainer
var _swatches: GridContainer
var _name_edit: LineEdit
var _ready_btn: BBButton
var _start_btn: BBButton
var _rounds_label: Label
var _minus: BBButton
var _plus: BBButton
var _hold_dir: int = 0
var _hold_t: float = 0.0
var _repeat_t: float = 0.0
var _confirm: ConfirmationDialog


func _ready() -> void:
	UiKit.full_rect(self)
	var bg := ColorRect.new()
	bg.color = Palette.BG_SKY
	UiKit.full_rect(bg)
	add_child(bg)
	var margin := MarginContainer.new()
	UiKit.full_rect(margin)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)
	var root: VBoxContainer = UiKit.vbox(20)
	margin.add_child(root)
	# Header.
	var head: HBoxContainer = UiKit.hbox(24)
	head.add_child(UiKit.button("LEAVE", _on_leave, "", Vector2(200, 88)))
	var titles: VBoxContainer = UiKit.vbox(0)
	_title = UiKit.label("", "TitleLabel")
	_subtitle = UiKit.label("", "SmallLabel")
	titles.add_child(_title)
	titles.add_child(_subtitle)
	head.add_child(UiKit.expand(titles))
	root.add_child(head)
	# Body: slots (left) + settings (right).
	var body: HBoxContainer = UiKit.hbox(28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var slots_panel: PanelContainer = UiKit.panel(20)
	slots_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_panel.size_flags_stretch_ratio = 1.3
	body.add_child(slots_panel)
	_slots = UiKit.vbox(8)
	slots_panel.add_child(_slots)
	var side_panel: PanelContainer = UiKit.panel(24)
	side_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(side_panel)
	var side: VBoxContainer = UiKit.vbox(18)
	side_panel.add_child(side)
	side.add_child(UiKit.label("Name", "SmallLabel"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 12
	_name_edit.custom_minimum_size = Vector2(0, 84)
	_name_edit.text_changed.connect(_on_name_changed)
	side.add_child(_name_edit)
	side.add_child(UiKit.label("Colour", "SmallLabel"))
	_swatches = GridContainer.new()
	_swatches.columns = 4
	_swatches.add_theme_constant_override("h_separation", 12)
	_swatches.add_theme_constant_override("v_separation", 12)
	side.add_child(_swatches)
	side.add_child(UiKit.label("Rounds", "SmallLabel"))
	var stepper: HBoxContainer = UiKit.hbox(16)
	_minus = UiKit.button("−", Callable(), "BigButton", Vector2(110, 96))
	_plus = UiKit.button("+", Callable(), "BigButton", Vector2(110, 96))
	_minus.button_down.connect(func() -> void: _start_hold(-1))
	_plus.button_down.connect(func() -> void: _start_hold(1))
	_minus.button_up.connect(_stop_hold)
	_plus.button_up.connect(_stop_hold)
	_rounds_label = UiKit.label("12", "HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_rounds_label.custom_minimum_size = Vector2(120, 0)
	stepper.add_child(_minus)
	stepper.add_child(_rounds_label)
	stepper.add_child(_plus)
	side.add_child(stepper)
	side.add_child(UiKit.spacer(8))
	_ready_btn = UiKit.button("READY", _on_ready_toggled, "BigButton", Vector2(0, 110))
	_ready_btn.toggle_mode = true
	side.add_child(_ready_btn)
	_start_btn = UiKit.button("START", _on_start, "BigButton", Vector2(0, 110))
	side.add_child(_start_btn)
	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Leave and close the lobby for everyone?"
	_confirm.ok_button_text = "Leave"
	_confirm.confirmed.connect(func() -> void: NetManager.leave(""))
	add_child(_confirm)
	_name_edit.text = GameState.player_name(GameState.local_pid)
	GameState.changed.connect(_refresh)
	_refresh()
	AudioManager.play_music("menu_loop")


func _refresh() -> void:
	if not is_inside_tree():
		return
	var is_host: bool = NetManager.is_host()
	var host_name: String = ""
	for pid: int in GameState.active_pids():
		if GameState.is_host_pid(pid):
			host_name = GameState.player_name(pid)
	_title.text = "%s's game" % host_name
	_subtitle.text = "Host IP: %s" % (GameState.host_ip if not GameState.host_ip.is_empty() else "—")
	# Slots.
	for c: Node in _slots.get_children():
		_slots.remove_child(c)
		c.queue_free()
	var pids: Array[int] = GameState.active_pids()
	for i: int in range(GameConfig.MAX_PLAYERS):
		_slots.add_child(_slot_row(pids[i] if i < pids.size() else -1))
	# Colours.
	for c2: Node in _swatches.get_children():
		_swatches.remove_child(c2)
		c2.queue_free()
	var mine: int = GameState.player_color(GameState.local_pid)
	for color: int in range(Palette.COLOR_COUNT):
		_swatches.add_child(_color_button(color, mine))
	# Rounds.
	_rounds_label.text = str(GameState.rounds)
	_minus.visible = is_host
	_plus.visible = is_host
	_ready_btn.visible = not is_host
	var me: Dictionary = GameState.get_player(GameState.local_pid)
	_ready_btn.set_pressed_no_signal(bool(me.get("ready", false)))
	var is_ready: bool = bool(me.get("ready", false))
	_ready_btn.text = "READY!" if is_ready else "READY UP"
	_ready_btn.modulate = Color("#8FD694").lerp(Color.WHITE, 0.3) if is_ready else Color.WHITE
	_start_btn.visible = is_host
	_start_btn.disabled = not GameState.can_start()


func _slot_row(pid: int) -> Control:
	var row: HBoxContainer = UiKit.hbox(16)
	row.custom_minimum_size = Vector2(0, 72)
	if pid < 0:
		row.add_child(UiKit.swatch(Color(Palette.INK, 0.1), 48))
		var l: Label = UiKit.label("Waiting…")
		l.modulate = Color(1, 1, 1, 0.45)
		row.add_child(l)
		return row
	var p: Dictionary = GameState.get_player(pid)
	row.add_child(UiKit.swatch(Palette.player_color(int(p["color"])), 48))
	var name_l: Label = UiKit.label(str(p["name"]) + ("  (you)" if pid == GameState.local_pid else ""))
	row.add_child(UiKit.expand(name_l))
	if bool(p["host"]):
		row.add_child(_badge("HOST", Palette.GOLD))
	elif bool(p["ready"]):
		row.add_child(_badge("READY", Color("#8FD694")))
	var ping: Label = UiKit.label("%d ms" % int(p["ping"]) if not bool(p["host"]) else "", "SmallLabel")
	ping.custom_minimum_size = Vector2(110, 0)
	row.add_child(ping)
	return row


func _badge(text: String, color: Color) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(UiKit.label(text, "SmallLabel"))
	return pc


func _color_button(color: int, mine: int) -> Control:
	var owner_pid: int = GameState.color_owner(color)
	var b := BBButton.new()
	b.custom_minimum_size = Vector2(150, 92)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.player_color(color)
	sb.set_corner_radius_all(14)
	if color == mine:
		sb.set_border_width_all(6)
		sb.border_color = Palette.INK
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_font_size_override("font_size", 22)
	if owner_pid >= 0 and owner_pid != GameState.local_pid:
		b.text = GameState.player_name(owner_pid)
		b.disabled = true
		b.add_theme_color_override("font_disabled_color", Palette.INK)
	b.pressed.connect(func() -> void: GameState.request_color(color))
	return b


func _on_name_changed(text: String) -> void:
	if Rules.is_valid_name(text):
		Settings.player_name = text
		Settings.apply()
		GameState.request_name(text)


func _on_ready_toggled() -> void:
	var me: Dictionary = GameState.get_player(GameState.local_pid)
	var now_ready: bool = not bool(me.get("ready", false))
	AudioManager.play_ui("ready" if now_ready else "ui_toggle")
	GameState.request_set_ready(now_ready)


func _on_start() -> void:
	if GameState.can_start():
		MatchManager.server_start_match()


func _start_hold(dir: int) -> void:
	_hold_dir = dir
	_hold_t = 0.0
	_repeat_t = 0.0
	_step_rounds(dir)


func _stop_hold() -> void:
	_hold_dir = 0


func _step_rounds(dir: int) -> void:
	if NetManager.is_host():
		GameState.request_rounds(GameState.rounds + dir)


## Long-press for fast change (§9.5).
func _process(delta: float) -> void:
	_debug_automation()
	if _hold_dir == 0:
		return
	_hold_t += delta
	if _hold_t < 0.4:
		return
	_repeat_t += delta
	var interval: float = 0.08 if _hold_t < 1.5 else 0.03
	while _repeat_t >= interval:
		_repeat_t -= interval
		_step_rounds(_hold_dir)


func _on_leave() -> void:
	if NetManager.is_host():
		_confirm.popup_centered()
	else:
		NetManager.leave("")


func handle_back() -> void:
	_on_leave()


var _debug_ready_sent: bool = false


## Debug builds only: --autostart=N (host starts with N players),
## --rounds=N, --bot (clients ready up automatically).
func _debug_automation() -> void:
	if not OS.is_debug_build():
		return
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--autostart=") and NetManager.is_host():
			var n: int = a.trim_prefix("--autostart=").to_int()
			for b: String in OS.get_cmdline_user_args():
				if b.begins_with("--rounds=") and GameState.rounds != Rules.clamp_rounds(b.trim_prefix("--rounds=").to_int()):
					GameState.request_rounds(b.trim_prefix("--rounds=").to_int())
			if GameState.connected_pids().size() >= n and GameState.can_start():
				MatchManager.server_start_match()
		elif a == "--bot" and NetManager.is_client() and not _debug_ready_sent and GameState.local_pid >= 0:
			_debug_ready_sent = true
			GameState.request_set_ready(true)
