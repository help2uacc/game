extends Control
## Join Game (PRD §9.4): live host list (broadcast + subnet sweep), manual
## IP field with JOIN, Back.

var _list: VBoxContainer
var _searching: Label
var _ip_edit: LineEdit
var _dots_t: float = 0.0


func _ready() -> void:
	UiKit.full_rect(self)
	var bg := ColorRect.new()
	bg.color = Palette.BG_SKY
	UiKit.full_rect(bg)
	add_child(bg)
	var margin := MarginContainer.new()
	UiKit.full_rect(margin)
	for side: String in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 140)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	var root: VBoxContainer = UiKit.vbox(24)
	margin.add_child(root)
	var top: HBoxContainer = UiKit.hbox(24)
	top.add_child(UiKit.icon_button("back", handle_back, 96))
	top.add_child(UiKit.label("JOIN GAME", "TitleLabel"))
	root.add_child(top)
	var panel: PanelContainer = UiKit.panel(28)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_list = UiKit.vbox(12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_searching = UiKit.label("Searching", "HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_searching.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_searching.modulate = Color(1, 1, 1, 0.7)
	var manual: HBoxContainer = UiKit.hbox(20)
	manual.add_child(UiKit.label("Host IP:"))
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.20"
	_ip_edit.custom_minimum_size = Vector2(480, 88)
	_ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _join_manual())
	manual.add_child(_ip_edit)
	manual.add_child(UiKit.button("JOIN", _join_manual, "", Vector2(220, 88)))
	root.add_child(manual)
	LanDiscovery.hosts_changed.connect(_rebuild)
	LanDiscovery.start_search()
	_rebuild()


func _exit_tree() -> void:
	LanDiscovery.stop_search()


func _process(delta: float) -> void:
	_dots_t += delta
	_searching.text = "Searching" + ".".repeat(int(_dots_t * 2.0) % 4)


func _rebuild() -> void:
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var hosts: Array = LanDiscovery.hosts.values()
	if hosts.is_empty():
		_list.add_child(UiKit.spacer(120))
		_list.add_child(_searching)
		return
	var session: Dictionary = NetManager.saved_session()
	for h: Variant in hosts:
		var d: Dictionary = h
		_list.add_child(_host_row(d, session))


func _host_row(d: Dictionary, session: Dictionary) -> Control:
	var ip: String = str(d["ip"])
	var in_match: bool = str(d["state"]) == "in_match"
	var can_rejoin: bool = in_match and not session.is_empty() and str(session["host_ip"]) == ip
	var row := BBButton.new()
	row.custom_minimum_size = Vector2(0, 100)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var state_text: String = "IN MATCH" if in_match else "LOBBY"
	row.text = "  %s     %d/%d     %s     %s" % [str(d["name"]), int(d["players"]), int(d["max"]), state_text, ip]
	row.disabled = in_match and not can_rejoin
	if in_match:
		row.modulate = Color(1, 1, 1, 0.55) if not can_rejoin else Color(1, 1, 1, 0.85)
	row.pressed.connect(func() -> void: _join(ip, can_rejoin))
	return row


func _join(ip: String, rejoin: bool) -> void:
	if rejoin:
		NetManager.rejoin_saved()
	else:
		NetManager.join(ip)
	SceneRouter.toast("Connecting to %s…" % ip, 1.5)


func _join_manual() -> void:
	var ip: String = _ip_edit.text.strip_edges()
	if not DiscoveryProtocol.is_valid_ipv4(ip):
		SceneRouter.toast("Enter a valid IPv4 address")
		return
	var session: Dictionary = NetManager.saved_session()
	_join(ip, not session.is_empty() and str(session["host_ip"]) == ip)


func handle_back() -> void:
	AudioManager.play_ui("ui_back")
	NetManager.close()
	SceneRouter.goto("main_menu")
