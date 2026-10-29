extends Node
## Root scene: owns the current screen (via SceneRouter) and glues global
## network/match signals to navigation and toasts.


func _ready() -> void:
	_setup_theme()
	SceneRouter.register_main(self)
	NetManager.left_game.connect(_on_left_game)
	NetManager.join_failed.connect(_on_join_failed)
	NetManager.joined.connect(_on_joined)
	NetManager.hosted.connect(_on_hosted)
	NetManager.notice.connect(func(t: String) -> void: SceneRouter.toast(t))
	MatchManager.load_map_requested.connect(_on_load_map)
	MatchManager.match_finished.connect(_on_match_finished)
	MatchManager.returned_to_lobby.connect(_on_returned_to_lobby)
	_apply_render_scale()
	Settings.changed.connect(_apply_render_scale)
	SceneRouter.goto("main_menu")
	_debug_quit_timer()


## Debug builds: --quit-after=SECONDS (automated smoke test).
func _debug_quit_timer() -> void:
	if not OS.is_debug_build():
		return
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--quit-after="):
			var t: float = a.trim_prefix("--quit-after=").to_float()
			get_tree().create_timer(t).timeout.connect(func() -> void: get_tree().quit())


func _setup_theme() -> void:
	var t: Theme = ThemeDB.get_project_theme()
	if t != null:
		var bold := FontVariation.new()
		bold.base_font = ThemeDB.fallback_font
		bold.variation_embolden = 0.7
		t.default_font = bold


func _apply_render_scale() -> void:
	# Quality preset render scale (§9.9) for the 3D view.
	get_viewport().scaling_3d_scale = Settings.render_scale()


func _on_left_game(message: String) -> void:
	MatchManager.reset()
	SceneRouter.goto("main_menu")
	SceneRouter.toast(message)


func _on_join_failed(reason: String) -> void:
	SceneRouter.toast(reason)


func _on_joined() -> void:
	if GameState.phase == GameState.Phase.IN_MATCH:
		return  # the server sends the current map right away
	SceneRouter.goto("lobby")


func _on_hosted() -> void:
	SceneRouter.goto("lobby")


func _on_load_map(map_id: String, round_no: int) -> void:
	var screen: Node = SceneRouter.current
	if not (screen is GameScreen):
		screen = SceneRouter.goto("game")
	(screen as GameScreen).load_round(map_id, round_no)


func _on_match_finished(_data: Dictionary) -> void:
	SceneRouter.goto("match_results")


func _on_returned_to_lobby() -> void:
	SceneRouter.goto("lobby")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Closing the app as host ends the game for everyone (§5.4).
		NetManager.notify_host_closing()


func _exit_tree() -> void:
	MaterialCache.clear()
	WeaponDB.clear()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE:
			_handle_back()
			get_viewport().set_input_as_handled()


## Android Back: in-match overlay in a match, otherwise back one screen (§8).
func _handle_back() -> void:
	var screen: Node = SceneRouter.current
	if screen != null and screen.has_method("handle_back"):
		screen.call("handle_back")
