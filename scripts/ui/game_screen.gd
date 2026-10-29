class_name GameScreen
extends Node
## In-round screen: World + HUD + touch controls + overlays (in-match menu,
## reconnecting, round results). Also hosts the offline sandbox.

@export var sandbox: bool = false
@export var sandbox_map: String = "candy_plains"

var world: World
var controls: TouchControls
var hud: Hud
var hud_layer: CanvasLayer
var overlay_layer: CanvasLayer
var spectate_pid: int = -1

var _local_input := PlayerInput.new()
var _seq: int = 0
var _jump_seq: int = -1
var _pickup_seq: int = -1
var _throw_seq: int = -1
var _menu: Control
var _reconnect: Control
var _reconnect_label: Label
var _round_results: RoundResultsOverlay
var _settings_overlay: Node = null
var _bot: DebugBot = null


func _ready() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 1
	add_child(hud_layer)
	hud = Hud.new()
	hud.name = "Hud"
	hud_layer.add_child(hud)
	hud.menu_pressed.connect(open_menu)
	hud.spectate_cycle.connect(cycle_spectate)
	controls = TouchControls.new()
	controls.name = "Controls"
	hud_layer.add_child(controls)
	overlay_layer = CanvasLayer.new()
	overlay_layer.name = "Overlays"
	overlay_layer.layer = 5
	add_child(overlay_layer)
	_build_menu()
	_build_reconnect()
	_round_results = RoundResultsOverlay.new()
	_round_results.visible = false
	overlay_layer.add_child(_round_results)
	MatchManager.countdown_started.connect(_on_countdown)
	MatchManager.fight_started.connect(_on_fight)
	MatchManager.round_finished.connect(_on_round_finished)
	NetManager.reconnect_status.connect(_on_reconnect_status)
	NetManager.reconnected.connect(_on_reconnected)
	# Keep the screen on while in a match (§2).
	DisplayServer.screen_set_keep_on(true)
	if DebugBot.enabled():
		_bot = DebugBot.new()
	if sandbox:
		_start_sandbox()


func _start_sandbox() -> void:
	_new_world(true)
	if OS.is_debug_build():
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--map="):
				sandbox_map = a.trim_prefix("--map=")
	world.load_map(sandbox_map)
	world.add_player(1, 0, Settings.player_name if Settings.has_player_name() else "Player", true)
	# Idle training dummies to test weapons on (debug arg --dummies=N).
	var dummies: int = 2
	if OS.is_debug_build():
		for a2: String in OS.get_cmdline_user_args():
			if a2.begins_with("--dummies="):
				dummies = clampi(a2.trim_prefix("--dummies=").to_int(), 0, 7)
	var pids: Array[int] = [1]
	for i: int in range(dummies):
		world.add_player(2 + i, (i + 1) % Palette.COLOR_COUNT, "Dummy", false)
		pids.append(2 + i)
	world.place_players_at_spawns(pids)
	world.camera.snap_to_target()
	world.start_fight()
	hud.attach(world, true)
	AudioManager.play_music("battle_loop_a")


func _exit_tree() -> void:
	DisplayServer.screen_set_keep_on(false)


func _new_world(is_authority: bool) -> void:
	if world != null:
		remove_child(world)
		world.queue_free()
	world = World.new()
	world.name = "World"
	world.authority = is_authority
	add_child(world)
	move_child(world, 0)
	spectate_pid = -1


## Builds the world for a new round (all peers), then reports map_ready.
func load_round(map_id: String, _round_no: int) -> void:
	_round_results.visible = false
	_round_results.stop()
	_new_world(not NetManager.is_client())
	if not world.load_map(map_id):
		push_error("Could not load map " + map_id)
	for pid: int in GameState.active_pids():
		world.add_player(pid, GameState.player_color(pid), GameState.player_name(pid), pid == GameState.local_pid)
	MatchManager.attach_world(world)
	hud.attach(world, false)
	var tracks: PackedStringArray = ["battle_loop_a", "battle_loop_b", "battle_loop_c"]
	AudioManager.play_music(tracks[randi() % tracks.size()])
	MatchManager.local_map_ready()


func _on_countdown(seconds: float) -> void:
	if world != null:
		world.frozen = true
		world.camera.snap_to_target()
	hud.start_countdown(seconds)


func _on_fight() -> void:
	if world != null and not world.authority:
		world.frozen = false
	hud.show_fight()


func _on_round_finished(data: Dictionary) -> void:
	_round_results.show_results(data)
	_round_results.visible = true
	AudioManager.play_ui("round_end")


# ================================================================ input
func _physics_process(_delta: float) -> void:
	if world == null or world.local_pid == -1:
		return
	var lp: Player = world.local_player()
	if lp == null:
		return
	if _bot != null:
		_bot.read_input(_local_input, world)
	else:
		controls.read_input(_local_input)
		_mouse_aim(lp)
	hud.local_aim = Vector2(_local_input.aim_x, _local_input.aim_y)
	_seq += 1
	_local_input.seq = _seq
	if world.authority:
		world.set_input(world.local_pid, _local_input)
		controls.ack_presses(true, true, true)
	else:
		# Latched presses stay set until the server acknowledges them (§5.6).
		if _local_input.jump_pressed and _jump_seq < 0:
			_jump_seq = _seq
		if _local_input.pickup_pressed and _pickup_seq < 0:
			_pickup_seq = _seq
		if _local_input.throw_pressed and _throw_seq < 0:
			_throw_seq = _seq
		MatchManager.send_input(_local_input)
		var ack: int = world.local_ack
		var aj: bool = _jump_seq >= 0 and ack >= _jump_seq
		var ap: bool = _pickup_seq >= 0 and ack >= _pickup_seq
		var at: bool = _throw_seq >= 0 and ack >= _throw_seq
		controls.ack_presses(aj, ap, at)
		if aj:
			_jump_seq = -1
		if ap:
			_pickup_seq = -1
		if at:
			_throw_seq = -1
	controls.update_context(lp.alive and world.nearest_weapon_pickup(lp) != null, lp.weapon_id if lp.alive else 0)


## Desktop: the mouse pointer aims (relative to the player's chest) when the
## touch aim stick is not in use.
func _mouse_aim(lp: Player) -> void:
	if OS.has_feature("mobile") or controls.has_touch_aim() or not lp.alive:
		return
	var sp: Vector2 = world.camera.unproject_position(lp.chest())
	var d: Vector2 = get_viewport().get_mouse_position() - sp
	if d.length() < 40.0:
		return
	d = d.normalized()
	_local_input.aim_x = d.x
	_local_input.aim_y = -d.y


func _process(_delta: float) -> void:
	if world == null:
		return
	var lp: Player = world.local_player()
	var spectating: bool = lp == null or not lp.alive
	controls.set_enabled(not spectating and not _menu.visible)
	if spectating and not sandbox:
		_update_spectate()
	elif lp != null:
		world.camera.target = lp
		spectate_pid = -1
	hud.set_spectating(spectate_pid if spectating else -1)


# ================================================================ spectate (§4.4)
func _living_pids() -> Array[int]:
	var out: Array[int] = []
	for p: Player in world.alive_players():
		if p.pid != world.local_pid and p.visible:
			out.append(p.pid)
	out.sort()
	return out


func _update_spectate() -> void:
	var alive: Array[int] = _living_pids()
	if alive.is_empty():
		return
	if not alive.has(spectate_pid):
		spectate_pid = alive[0]
	world.camera.target = world.get_player(spectate_pid)


func cycle_spectate(dir: int) -> void:
	var alive: Array[int] = _living_pids()
	if alive.is_empty():
		return
	var i: int = alive.find(spectate_pid)
	spectate_pid = alive[(i + dir + alive.size()) % alive.size()]
	AudioManager.play_ui("ui_toggle")


# ================================================================ overlays
func _build_menu() -> void:
	_menu = ColorRect.new()
	(_menu as ColorRect).color = Color(Palette.INK, 0.45)
	UiKit.full_rect(_menu)
	_menu.visible = false
	overlay_layer.add_child(_menu)
	var panel: PanelContainer = UiKit.panel(40)
	var box: VBoxContainer = UiKit.vbox(20)
	box.custom_minimum_size = Vector2(520, 0)
	panel.add_child(box)
	box.add_child(UiKit.label("MENU", "HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiKit.button("RESUME", close_menu, "BigButton"))
	box.add_child(UiKit.button("SETTINGS", _open_settings, "BigButton"))
	box.add_child(UiKit.button("LEAVE", _confirm_leave, "BigButton"))
	_menu.add_child(UiKit.center(panel))


## The game is not paused while the menu is open (multiplayer, §8).
func open_menu() -> void:
	_menu.visible = true
	AudioManager.play_ui("ui_click")


func close_menu() -> void:
	_menu.visible = false


func _open_settings() -> void:
	if _settings_overlay != null:
		return
	var scene: PackedScene = load("res://scenes/ui/settings.tscn")
	_settings_overlay = scene.instantiate()
	_settings_overlay.set("as_overlay", true)
	overlay_layer.add_child(_settings_overlay)
	_settings_overlay.tree_exited.connect(func() -> void: _settings_overlay = null)


func _confirm_leave() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Leave the match?" if not NetManager.is_host() else "Leave and end the match for everyone?"
	dlg.ok_button_text = "Leave"
	dlg.confirmed.connect(_leave)
	overlay_layer.add_child(dlg)
	dlg.popup_centered()


func _leave() -> void:
	if sandbox:
		SceneRouter.goto("main_menu")
		return
	NetManager.leave("")


func _build_reconnect() -> void:
	_reconnect = ColorRect.new()
	(_reconnect as ColorRect).color = Color(Palette.INK, 0.55)
	UiKit.full_rect(_reconnect)
	_reconnect.visible = false
	overlay_layer.add_child(_reconnect)
	var panel: PanelContainer = UiKit.panel(40)
	var box: VBoxContainer = UiKit.vbox(24)
	box.custom_minimum_size = Vector2(620, 0)
	panel.add_child(box)
	_reconnect_label = UiKit.label("Reconnecting…", "HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_reconnect_label)
	box.add_child(UiKit.button("LEAVE", func() -> void: NetManager.cancel_reconnect(), "BigButton"))
	_reconnect.add_child(UiKit.center(panel))


func _on_reconnect_status(seconds_left: float) -> void:
	_reconnect.visible = true
	_reconnect_label.text = "Reconnecting… (%ds)" % int(ceil(seconds_left))


func _on_reconnected() -> void:
	_reconnect.visible = false


func handle_back() -> void:
	if _settings_overlay != null:
		_settings_overlay.queue_free()
	elif _menu.visible:
		close_menu()
	else:
		open_menu()
