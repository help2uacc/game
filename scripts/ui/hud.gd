class_name Hud
extends Control
## In-round HUD (PRD §9.6). Every element can be toggled in Settings → HUD;
## HUD scale 80–120 %. Also: auto-aim target marker (§7.2), spectate bar
## (§4.4) and the debug overlay (§12).

signal menu_pressed
signal spectate_cycle(dir: int)

const KILL_FEED_MAX := 4
const KILL_FEED_TIME := 5.0
const BAR_W := 420.0
const BAR_H := 34.0

var world: World = null
var sandbox: bool = false

var _top_left: Control
var _top_center: Control
var _top_right: Control
var _menu_btn: BBButton
var _weapon_icon: TextureRect
var _ammo_label: Label
var _round_label: Label
var _timer_label: Label
var _alive_box: HBoxContainer
var _alive_label: Label
var _score_box: VBoxContainer
var _feed_box: VBoxContainer
var _ping_label: Label
var _fps_label: Label
var _countdown_label: Label
var _spectate_bar: HBoxContainer
var _spectate_label: Label
var _debug_label: Label
var _feed: Array[Dictionary] = []
var _countdown_t: float = -1.0
var _last_count: int = -1
var _fight_t: float = -1.0
var _debug_visible: bool = false
var _marker_t: float = 0.0
var _last_low_tick: int = -1
var _weapon_key: String = ""
var _score_dirty: bool = true
var _swipe_start: Vector2 = Vector2.ZERO
var _swipe_index: int = -1
var _bottom_center: Control


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_left()
	_build_top_center()
	_build_top_right()
	_countdown_label = Label.new()
	_countdown_label.theme_type_variation = "HudLabel"
	_countdown_label.add_theme_font_size_override("font_size", 200)
	_countdown_label.add_theme_constant_override("outline_size", 28)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiKit.full_rect(_countdown_label)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.visible = false
	add_child(_countdown_label)
	_build_spectate_bar()
	_debug_label = Label.new()
	_debug_label.theme_type_variation = "HudLabel"
	_debug_label.add_theme_font_size_override("font_size", 26)
	_debug_label.position = Vector2(24, 300)
	_debug_label.visible = false
	add_child(_debug_label)
	Settings.changed.connect(_apply_settings)
	GameState.changed.connect(func() -> void: _score_dirty = true)
	_apply_settings()


func attach(w: World, is_sandbox: bool) -> void:
	world = w
	sandbox = is_sandbox
	_feed.clear()
	_rebuild_feed()
	world.kill_feed.connect(_on_kill_feed)
	_score_dirty = true


# ---------------------------------------------------------------- building
func _corner(preset: int) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(preset)
	add_child(c)
	return c


func _hud_label(text: String, font_size: int = 34) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "HudLabel"
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_top_left() -> void:
	_top_left = _corner(Control.PRESET_TOP_LEFT)
	_menu_btn = UiKit.icon_button("menu", func() -> void: menu_pressed.emit(), 96)
	_menu_btn.position = Vector2(24, 24)
	_menu_btn.modulate = Color(1, 1, 1, 0.85)
	_top_left.add_child(_menu_btn)
	var weapon_row: HBoxContainer = UiKit.hbox(12)
	weapon_row.position = Vector2(140, 84)
	weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_icon = TextureRect.new()
	_weapon_icon.custom_minimum_size = Vector2(64, 64)
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_row.add_child(_weapon_icon)
	_ammo_label = _hud_label("", 38)
	weapon_row.add_child(_ammo_label)
	weapon_row.name = "WeaponRow"
	_top_left.add_child(weapon_row)


func _build_top_center() -> void:
	_top_center = _corner(Control.PRESET_CENTER_TOP)
	var box: VBoxContainer = UiKit.vbox(0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.position = Vector2(-200, 16)
	box.custom_minimum_size = Vector2(400, 0)
	_round_label = _hud_label("ROUND 1 / 12", 34)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_round_label)
	var row: HBoxContainer = UiKit.hbox(28)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_label = _hud_label("5:00", 56)
	row.add_child(_timer_label)
	_alive_box = UiKit.hbox(4)
	_alive_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = UiKit.icon("alive")
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_alive_box.add_child(icon)
	_alive_label = _hud_label("× 0", 38)
	_alive_box.add_child(_alive_label)
	row.add_child(_alive_box)
	box.add_child(row)
	_top_center.add_child(box)


func _build_top_right() -> void:
	_top_right = _corner(Control.PRESET_TOP_RIGHT)
	var col: VBoxContainer = UiKit.vbox(6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.position = Vector2(-460, 16)
	col.custom_minimum_size = Vector2(436, 0)
	var stats: HBoxContainer = UiKit.hbox(18)
	stats.alignment = BoxContainer.ALIGNMENT_END
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label = _hud_label("", 24)
	_ping_label = _hud_label("", 24)
	stats.add_child(_fps_label)
	stats.add_child(_ping_label)
	col.add_child(stats)
	_score_box = UiKit.vbox(2)
	_score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_score_box)
	col.add_child(UiKit.spacer(10))
	_feed_box = UiKit.vbox(4)
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_feed_box)
	_top_right.add_child(col)


func _build_spectate_bar() -> void:
	var bottom: Control = _corner(Control.PRESET_CENTER_BOTTOM)
	_bottom_center = bottom
	_spectate_bar = UiKit.hbox(24)
	_spectate_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_spectate_bar.position = Vector2(-450, -150)
	_spectate_bar.custom_minimum_size = Vector2(900, 120)
	_spectate_bar.add_child(UiKit.icon_button("arrow_left", func() -> void: spectate_cycle.emit(-1), 110))
	_spectate_label = _hud_label("SPECTATING", 40)
	_spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectate_label.custom_minimum_size = Vector2(560, 0)
	_spectate_bar.add_child(_spectate_label)
	_spectate_bar.add_child(UiKit.icon_button("arrow_right", func() -> void: spectate_cycle.emit(1), 110))
	_spectate_bar.visible = false
	bottom.add_child(_spectate_bar)


func _apply_settings() -> void:
	var s: float = Settings.hud_scale
	for c: Control in [_top_left, _top_center, _top_right]:
		c.scale = Vector2(s, s)
	_top_left.get_node("WeaponRow").visible = Settings.hud_enabled("weapon")
	_round_label.visible = Settings.hud_enabled("round")
	_timer_label.visible = Settings.hud_enabled("timer")
	_alive_box.visible = Settings.hud_enabled("alive")
	_score_box.visible = Settings.hud_enabled("scoreboard")
	_feed_box.visible = Settings.hud_enabled("kill_feed")
	_ping_label.visible = Settings.hud_enabled("ping")
	_fps_label.visible = Settings.hud_enabled("fps")
	if world != null:
		world.effects.damage_numbers_enabled = Settings.hud_enabled("damage_numbers")
	queue_redraw()


# ---------------------------------------------------------------- countdown
func start_countdown(seconds: float) -> void:
	_countdown_t = seconds
	_last_count = -1
	_fight_t = -1.0


func show_fight() -> void:
	_countdown_t = -1.0
	_fight_t = 0.8
	if Settings.hud_enabled("countdown"):
		_countdown_label.visible = true
		_countdown_label.text = "FIGHT!"
		_countdown_label.add_theme_color_override("font_color", Palette.GOLD)
	AudioManager.play_ui("round_start")


func set_spectating(pid: int) -> void:
	var on: bool = pid >= 0 and not sandbox
	_spectate_bar.visible = on
	if on:
		_spectate_label.text = "SPECTATING: %s" % GameState.player_name(pid)
		_spectate_label.add_theme_color_override("font_color", Palette.player_color(GameState.player_color(pid)))


# ---------------------------------------------------------------- kill feed
func _on_kill_feed(killer: int, victim: int, cause: int) -> void:
	_feed.append({"killer": killer, "victim": victim, "cause": cause, "t": KILL_FEED_TIME})
	while _feed.size() > KILL_FEED_MAX:
		_feed.pop_front()
	_rebuild_feed()


func _cause_icon(cause: int) -> String:
	if GameConfig.is_environmental(cause):
		return "hazard"
	match cause:
		GameConfig.Cause.PUNCH:
			return "punch"
		GameConfig.Cause.THROWN:
			return "thrown"
	if cause >= 1 and cause <= 6:
		return GameConfig.WEAPON_KEYS[cause]
	return "skull"


func _rebuild_feed() -> void:
	if _feed_box == null:
		return
	for c: Node in _feed_box.get_children():
		_feed_box.remove_child(c)
		c.queue_free()
	for e: Dictionary in _feed:
		var row: HBoxContainer = UiKit.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_END
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var killer: int = int(e["killer"])
		var victim: int = int(e["victim"])
		if killer >= 0:
			row.add_child(_name_label(killer))
		var icon := TextureRect.new()
		icon.texture = UiKit.icon(_cause_icon(int(e["cause"])))
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		row.add_child(_name_label(victim))
		_feed_box.add_child(row)


func _name_label(pid: int) -> Label:
	var p: Player = world.get_player(pid) if world != null else null
	var n: String = GameState.player_name(pid) if GameState.players.has(pid) else (p.display_name if p != null else "?")
	var c: int = p.color_id if p != null else GameState.player_color(pid)
	var l: Label = _hud_label(n, 30)
	l.add_theme_color_override("font_color", Palette.player_color(c))
	return l


# ---------------------------------------------------------------- scoreboard
## Top 3 by total kills plus the local player if not in the top 3.
func _rebuild_scoreboard() -> void:
	_score_dirty = false
	for c: Node in _score_box.get_children():
		_score_box.remove_child(c)
		c.queue_free()
	if sandbox:
		return
	var order: Array[int] = GameState.sorted_by_kills()
	var shown: Array[int] = []
	for i: int in range(mini(3, order.size())):
		shown.append(order[i])
	if GameState.local_pid >= 0 and not shown.has(GameState.local_pid) and order.has(GameState.local_pid):
		shown.append(GameState.local_pid)
	for pid: int in shown:
		var p: Dictionary = GameState.get_player(pid)
		var row: HBoxContainer = UiKit.hbox(12)
		row.alignment = BoxContainer.ALIGNMENT_END
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rank: int = order.find(pid) + 1
		var name_l: Label = _hud_label("%d. %s" % [rank, str(p["name"])], 30)
		var col: Color = Palette.player_color(int(p["color"]))
		if bool(p["released"]):
			col = Color(col, 0.45)
		name_l.add_theme_color_override("font_color", col)
		row.add_child(name_l)
		row.add_child(_hud_label(str(int(p["kills"])), 30))
		_score_box.add_child(row)


# ---------------------------------------------------------------- per frame
func _layout_corners() -> void:
	var vp: Vector2 = get_viewport_rect().size
	_top_left.position = Vector2.ZERO
	_top_center.position = Vector2(vp.x * 0.5, 0)
	_top_right.position = Vector2(vp.x, 0)
	_bottom_center.position = Vector2(vp.x * 0.5, vp.y)


func _process(delta: float) -> void:
	_layout_corners()
	if world == null:
		return
	if _score_dirty:
		_rebuild_scoreboard()
	_marker_t += delta
	# Countdown 3, 2, 1, FIGHT!
	if _countdown_t >= 0.0:
		_countdown_t -= delta
		var n: int = int(ceil(_countdown_t))
		if n != _last_count and n > 0:
			_last_count = n
			AudioManager.play_ui("countdown_tick")
		_countdown_label.visible = Settings.hud_enabled("countdown") and n > 0
		_countdown_label.text = str(maxi(n, 1))
		_countdown_label.remove_theme_color_override("font_color")
	elif _fight_t >= 0.0:
		_fight_t -= delta
		if _fight_t < 0.0:
			_countdown_label.visible = false
	# Round / timer / alive.
	_round_label.text = "ROUND %d / %d" % [maxi(1, MatchManager.round_no), GameState.rounds] if not sandbox else "SANDBOX"
	var tl: float = MatchManager.time_left if not sandbox else GameConfig.ROUND_TIME - world.fight_time
	tl = maxf(0.0, tl)
	var secs: int = int(ceil(tl))
	_timer_label.text = "%d:%02d" % [int(secs / 60.0), secs % 60]
	var low: bool = tl <= GameConfig.LOW_TIME_WARNING and MatchManager.state == MatchManager.State.FIGHT
	if low:
		_timer_label.add_theme_color_override("font_color", Palette.DANGER)
		if secs != _last_low_tick and secs <= 10 and secs > 0:
			_last_low_tick = secs
			AudioManager.play_ui("low_time_tick")
	else:
		_timer_label.remove_theme_color_override("font_color")
	_alive_label.text = "× %d" % world.alive_count()
	# Weapon + ammo.
	var lp: Player = world.local_player()
	if lp != null:
		var key: String = GameConfig.WEAPON_KEYS[lp.weapon_id] if lp.weapon_id != 0 else "punch"
		if key != _weapon_key:
			_weapon_key = key
			_weapon_icon.texture = UiKit.icon(key)
		_ammo_label.text = str(lp.ammo) if lp.weapon_id != 0 else ""
	# Ping / FPS.
	_ping_label.text = "%d ms" % NetManager.ping_ms if NetManager.is_client() else ("HOST" if NetManager.is_host() else "")
	_fps_label.text = "%d FPS" % int(Engine.get_frames_per_second())
	# Kill feed expiry.
	var expired: bool = false
	for e: Dictionary in _feed:
		e["t"] = float(e["t"]) - delta
		if float(e["t"]) <= 0.0:
			expired = true
	if expired:
		_feed = _feed.filter(func(e2: Dictionary) -> bool: return float(e2["t"]) > 0.0)
		_rebuild_feed()
	if _debug_visible:
		_debug_label.text = "FPS %d\nDraw calls %d\nPrimitives %d\nPing %d ms\nSnapshot %d B" % [
			int(Engine.get_frames_per_second()),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			NetManager.ping_ms, world.last_snapshot_bytes]
	queue_redraw()


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if world == null:
		return
	var lp: Player = world.local_player()
	var s: float = Settings.hud_scale
	if lp != null and Settings.hud_enabled("health"):
		_draw_bars(lp, Vector2(140, 34) * s, s)
	if lp != null and lp.alive:
		_draw_target_marker(lp)
	if Settings.hud_enabled("offscreen"):
		_draw_offscreen(lp)


## HP bar with the armor drawn as a light-blue segment over it (§9.6).
func _draw_bars(lp: Player, pos: Vector2, s: float) -> void:
	var w: float = BAR_W * s
	var h: float = BAR_H * s
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(Palette.INK, 0.55)
	bg.set_corner_radius_all(int(10 * s))
	draw_style_box(bg, Rect2(pos - Vector2(4, 4) * s, Vector2(w, h) + Vector2(8, 8) * s))
	var hp_frac: float = clampf(float(lp.hp) / float(GameConfig.MAX_HP), 0.0, 1.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.HEAL if hp_frac > 0.3 else Palette.DANGER
	fill.set_corner_radius_all(int(8 * s))
	if hp_frac > 0.0:
		draw_style_box(fill, Rect2(pos, Vector2(w * hp_frac, h)))
	if lp.armor > 0:
		var a_frac: float = clampf(float(lp.armor) / float(GameConfig.MAX_HP), 0.0, 1.0)
		var arm := StyleBoxFlat.new()
		arm.bg_color = Color(Palette.ARMOR, 0.95)
		arm.set_corner_radius_all(int(8 * s))
		draw_style_box(arm, Rect2(pos + Vector2(0, h * 0.45), Vector2(w * a_frac, h * 0.55)))
	var font: Font = get_theme_default_font()
	var txt: String = "%d" % lp.hp + ("  +%d" % lp.armor if lp.armor > 0 else "")
	draw_string_outline(font, pos + Vector2(12, h - 7) * Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * s), int(8 * s), Palette.INK)
	draw_string(font, pos + Vector2(12, h - 7), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * s), Palette.WHITE)


## Pulsing corner brackets around the enemy the local player auto-aims at.
func _draw_target_marker(lp: Player) -> void:
	if lp.weapon_id == 0:
		return
	var w: WeaponData = WeaponDB.weapon(lp.weapon_id)
	var target: Player = world.find_auto_aim_target(lp, w.weapon_range)
	if target == null:
		return
	var cam: CameraRig = world.camera
	if cam.is_position_behind(target.center()):
		return
	var top: Vector2 = cam.unproject_position(target.global_position + Vector3(0, 1.9, 0))
	var bot: Vector2 = cam.unproject_position(target.global_position)
	var hgt: float = absf(bot.y - top.y)
	var center: Vector2 = (top + bot) * 0.5
	var pulse: float = 1.0 + 0.12 * sin(_marker_t * 8.0)
	var half := Vector2(hgt * 0.42, hgt * 0.62) * pulse
	var col: Color = Palette.player_color(lp.color_id)
	var l: float = hgt * 0.22
	var t: float = 6.0
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var c: Vector2 = center + Vector2(half.x * sx, half.y * sy)
			draw_line(c, c + Vector2(-sx * l, 0), Palette.INK, t + 4.0)
			draw_line(c, c + Vector2(0, -sy * l), Palette.INK, t + 4.0)
			draw_line(c, c + Vector2(-sx * l, 0), col, t)
			draw_line(c, c + Vector2(0, -sy * l), col, t)


## Small coloured arrows at the screen edge pointing at off-screen enemies.
func _draw_offscreen(lp: Player) -> void:
	var cam: CameraRig = world.camera
	var rect: Rect2 = get_viewport_rect()
	var inner: Rect2 = rect.grow(-60)
	var center: Vector2 = rect.get_center()
	for p: Player in world.alive_players():
		if p == lp or not p.visible:
			continue
		var wp: Vector3 = p.center()
		var sp: Vector2 = cam.unproject_position(wp)
		if rect.has_point(sp) and not cam.is_position_behind(wp):
			continue
		var dir: Vector2 = (sp - center)
		if dir.length() < 1.0:
			continue
		dir = dir.normalized()
		# Intersect the ray from the centre with the inner rect.
		var tx: float = (inner.size.x * 0.5) / maxf(absf(dir.x), 0.0001)
		var ty: float = (inner.size.y * 0.5) / maxf(absf(dir.y), 0.0001)
		var pos: Vector2 = center + dir * minf(tx, ty)
		var col: Color = Palette.player_color(p.color_id)
		var tip: Vector2 = pos + dir * 26.0
		var side := Vector2(-dir.y, dir.x) * 20.0
		var pts := PackedVector2Array([tip, pos - dir * 10.0 + side, pos - dir * 10.0 - side])
		var outline := PackedVector2Array([tip + dir * 5.0, pos - dir * 14.0 + side * 1.3, pos - dir * 14.0 - side * 1.3])
		draw_colored_polygon(outline, Palette.INK)
		draw_colored_polygon(pts, col)


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.physical_keycode == KEY_F3 and OS.is_debug_build():
			_toggle_debug()
	elif event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		# 4-finger tap toggles the debug overlay (debug builds).
		if t.pressed and t.index == 3 and OS.is_debug_build():
			_toggle_debug()
		# Swipe to cycle spectated players (§4.4).
		if _spectate_bar.visible:
			if t.pressed and _swipe_index == -1:
				_swipe_index = t.index
				_swipe_start = t.position
			elif not t.pressed and t.index == _swipe_index:
				_swipe_index = -1
				var dx: float = t.position.x - _swipe_start.x
				if absf(dx) > 200.0:
					spectate_cycle.emit(-1 if dx > 0.0 else 1)


func _toggle_debug() -> void:
	_debug_visible = not _debug_visible
	_debug_label.visible = _debug_visible
