extends Node
## Server-side match/round flow (PRD §3, §4, §7.5) and the RPC hub for all
## in-match traffic: map load sync, countdown, inputs, snapshots, events,
## round/match results. Lives at a fixed node path on every peer.

signal load_map_requested(map_id: String, round_no: int)
signal countdown_started(seconds: float)
signal fight_started
signal round_finished(data: Dictionary)
signal match_finished(data: Dictionary)
signal returned_to_lobby

enum State { IDLE = 0, LOADING = 1, COUNTDOWN = 2, FIGHT = 3, ROUND_RESULTS = 4, MATCH_RESULTS = 5, WAITING = 6 }

var state: int = State.IDLE
var round_no: int = 0
var map_id: String = ""
var time_left: float = GameConfig.ROUND_TIME
var countdown_left: float = 0.0
var results_left: float = 0.0
var world: World = null
var last_round_data: Dictionary = {}
var last_match_data: Dictionary = {}
## Server: last input seq processed per pid (acknowledged in snapshots).
var acks: Dictionary = {}

var _rotation: MapRotation = null
var _rng := RandomNumberGenerator.new()
var _ready_pids: Dictionary = {}
var _load_t: float = 0.0
var _tick: int = 0
var _pending_events: Array = []
var _participants: Array[int] = []
var _wait_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()


## Debug log for the automated smoke test (user arg --log).
func dlog(text: String) -> void:
	if OS.is_debug_build() and OS.get_cmdline_user_args().has("--log"):
		print("[%s pid=%d] %s" % ["HOST" if NetManager.is_host() else "CLIENT", GameState.local_pid, text])


func is_server() -> bool:
	return NetManager.is_host()


func reset() -> void:
	state = State.IDLE
	round_no = 0
	map_id = ""
	world = null
	acks.clear()
	_pending_events.clear()
	_ready_pids.clear()


# ================================================================ server flow
func server_start_match() -> void:
	if not is_server() or not GameState.can_start():
		return
	GameState.phase = GameState.Phase.IN_MATCH
	GameState.server_reset_scores()
	var ids: Array[String] = GameMap.list_map_ids()
	_rotation = MapRotation.new(ids, _rng)
	round_no = 0
	GameState.broadcast()
	_next_round()


func _next_round() -> void:
	if not _enough_players_or_wait():
		return
	round_no += 1
	GameState.current_round = round_no
	GameState.server_reset_round_kills()
	map_id = _rotation.next()
	state = State.LOADING
	_ready_pids.clear()
	_load_t = 0.0
	acks.clear()
	GameState.broadcast()
	_rpc_load_map.rpc(map_id, round_no)
	dlog("round %d load %s" % [round_no, map_id])
	load_map_requested.emit(map_id, round_no)


## §5.5: with < 2 connected players, wait for reconnect windows; if still
## < 2 when they expire, end the match early. Returns true to continue.
func _enough_players_or_wait() -> bool:
	if GameState.connected_pids().size() >= GameConfig.MIN_PLAYERS:
		return true
	if GameState.in_reconnect_window_count() > 0:
		state = State.WAITING
		_wait_t = 0.0
		return false
	_finish_match()
	return false


func server_check_enough_players() -> void:
	if not is_server() or GameState.phase != GameState.Phase.IN_MATCH:
		return
	if state == State.MATCH_RESULTS or state == State.IDLE:
		return
	if GameState.connected_pids().size() < GameConfig.MIN_PLAYERS and GameState.in_reconnect_window_count() == 0:
		_finish_match()


## Host or client finished building the world for the current map.
func local_map_ready() -> void:
	if is_server():
		_ready_pids[GameState.local_pid] = true
	elif NetManager.is_connected_to_host():
		_c_map_ready.rpc_id(1, round_no)


func _all_ready() -> bool:
	for pid: int in GameState.connected_pids():
		if not _ready_pids.has(pid):
			return false
	return true


func _begin_countdown() -> void:
	state = State.COUNTDOWN
	countdown_left = GameConfig.COUNTDOWN_TIME
	_participants.clear()
	for pid: int in GameState.connected_pids():
		if _ready_pids.has(pid):
			_participants.append(pid)
	if world != null:
		world.frozen = true
		world.fighting = false
		world.kill_credit.reset()
		world.place_players_at_spawns(_participants)
		for pid2: int in world.players.keys():
			if not _participants.has(pid2):
				_set_spectator(world.get_player(pid2))
	_rpc_countdown.rpc(GameConfig.COUNTDOWN_TIME)
	dlog("countdown participants=%s" % str(_participants))
	countdown_started.emit(GameConfig.COUNTDOWN_TIME)


func _set_spectator(p: Player) -> void:
	if p == null:
		return
	p.alive = false
	p.visible = false
	p.collision_layer = 0
	p.global_position = Vector3(-50, -50, 0)


func _begin_fight() -> void:
	state = State.FIGHT
	time_left = GameConfig.ROUND_TIME
	if world != null:
		world.start_fight()
	_rpc_fight.rpc()
	fight_started.emit()


func _end_round() -> void:
	state = State.ROUND_RESULTS
	results_left = GameConfig.ROUND_RESULTS_TIME
	if world != null:
		world.fighting = false
		world.frozen = true
	var winners: Array[int] = Rules.top_scorers(GameState.round_kills())
	if winners.size() == 1:
		GameState.server_add_round_win(winners[0])
	var data: Dictionary = {
		"round": round_no,
		"rounds": GameState.rounds,
		"winners": winners,
		"draw": Rules.is_draw(winners),
	}
	GameState.broadcast()
	dlog("round %d end winners=%s draw=%s kills=%s" % [round_no, str(winners), str(data["draw"]), str(GameState.total_kills())])
	_rpc_round_results.rpc(data)
	_show_round_results(data)


func _finish_match() -> void:
	state = State.MATCH_RESULTS
	if world != null:
		world.fighting = false
		world.frozen = true
	var winners: Array[int] = Rules.top_scorers(GameState.total_kills())
	var data: Dictionary = {"winners": winners, "draw": Rules.is_draw(winners), "rounds_played": round_no}
	GameState.broadcast()
	dlog("match end winners=%s kills=%s" % [str(winners), str(GameState.total_kills())])
	_rpc_match_results.rpc(data)
	_show_match_results(data)


## Host: BACK TO LOBBY (§9.8) — same players and colours, kills reset.
func server_back_to_lobby() -> void:
	if not is_server():
		return
	GameState.phase = GameState.Phase.LOBBY
	GameState.server_drop_released()
	GameState.server_reset_scores()
	reset()
	GameState.broadcast()
	_rpc_to_lobby.rpc()
	returned_to_lobby.emit()


func server_on_player_disconnected(pid: int) -> void:
	if world != null and world.authority:
		var p: Player = world.get_player(pid)
		if p != null and p.alive:
			# Treated as dead for this round; normal kill-credit rule (§5.5).
			world.kill_player(p, KillCredit.NONE, GameConfig.Cause.DISCONNECT)
	server_check_enough_players()


func server_on_player_reconnected(pid: int, peer_id: int) -> void:
	acks.erase(pid)
	match state:
		State.LOADING, State.COUNTDOWN, State.FIGHT, State.ROUND_RESULTS:
			_rpc_load_map.rpc_id(peer_id, map_id, round_no)
			if state == State.ROUND_RESULTS:
				_rpc_round_results.rpc_id(peer_id, last_round_data)
		State.MATCH_RESULTS:
			_rpc_match_results.rpc_id(peer_id, last_match_data)
		State.WAITING:
			if GameState.connected_pids().size() >= GameConfig.MIN_PLAYERS:
				_next_round()


func _on_world_player_died(victim: int, killer: int, cause: int) -> void:
	if not is_server():
		return
	dlog("death victim=%d killer=%d cause=%d" % [victim, killer, cause])
	if killer >= 0 and killer != victim:
		GameState.server_add_kill(killer)
		GameState.broadcast()


func _on_world_event(ev: Array) -> void:
	if is_server():
		_pending_events.append(ev)


## Called by GameScreen when its World is created.
func attach_world(w: World) -> void:
	world = w
	if is_server():
		w.player_died.connect(_on_world_player_died)
		w.event_emitted.connect(_on_world_event)


func _process(delta: float) -> void:
	if not is_server():
		if state == State.COUNTDOWN:
			countdown_left = maxf(0.0, countdown_left - delta)
		elif state == State.ROUND_RESULTS:
			results_left = maxf(0.0, results_left - delta)
		return
	match state:
		State.LOADING:
			_load_t += delta
			if (_all_ready() and _ready_pids.has(GameState.local_pid)) or _load_t >= GameConfig.MAP_LOAD_TIMEOUT:
				_begin_countdown()
		State.COUNTDOWN:
			countdown_left -= delta
			if countdown_left <= 0.0:
				_begin_fight()
		State.FIGHT:
			time_left = maxf(0.0, time_left - delta)
			if world != null and Rules.should_round_end(world.alive_count(), time_left):
				_end_round()
		State.ROUND_RESULTS:
			results_left -= delta
			if results_left <= 0.0:
				if round_no >= GameState.rounds:
					_finish_match()
				else:
					_next_round()
		State.WAITING:
			_wait_t += delta
			if _wait_t >= 1.0:
				_wait_t = 0.0
				if GameState.connected_pids().size() >= GameConfig.MIN_PLAYERS:
					_next_round()
				elif GameState.in_reconnect_window_count() == 0:
					_finish_match()


func _physics_process(_delta: float) -> void:
	if not is_server() or world == null:
		return
	_tick += 1
	if not _pending_events.is_empty():
		_rpc_events.rpc(_pending_events)
		_pending_events = []
	# Snapshots at 30 Hz (every 2nd physics tick at 60 Hz).
	if _tick % 2 == 0 and state != State.IDLE and world.map != null:
		var bytes: PackedByteArray = NetSnapshot.pack(world, acks, _tick, time_left)
		_rpc_snapshot.rpc(bytes)


# ================================================================ client input
func send_input(inp: PlayerInput) -> void:
	if NetManager.is_connected_to_host():
		_c_input.rpc_id(1, inp.pack())


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _c_input(bytes: PackedByteArray) -> void:
	if not is_server() or world == null:
		return
	var pid: int = NetManager.pid_for_peer(multiplayer.get_remote_sender_id())
	if pid < 0:
		return
	var inp: PlayerInput = PlayerInput.unpack(bytes)
	if inp.seq <= int(acks.get(pid, 0)):
		return
	acks[pid] = inp.seq
	world.set_input(pid, inp)


@rpc("any_peer", "call_remote", "reliable")
func _c_map_ready(for_round: int) -> void:
	if not is_server() or for_round != round_no:
		return
	var pid: int = NetManager.pid_for_peer(multiplayer.get_remote_sender_id())
	if pid >= 0:
		_ready_pids[pid] = true


# ================================================================ client side RPCs
@rpc("authority", "call_remote", "reliable")
func _rpc_load_map(new_map_id: String, new_round: int) -> void:
	dlog("load map %s round %d" % [new_map_id, new_round])
	map_id = new_map_id
	round_no = new_round
	state = State.LOADING
	load_map_requested.emit(new_map_id, new_round)


@rpc("authority", "call_remote", "reliable")
func _rpc_countdown(seconds: float) -> void:
	state = State.COUNTDOWN
	countdown_left = seconds
	countdown_started.emit(seconds)


@rpc("authority", "call_remote", "reliable")
func _rpc_fight() -> void:
	state = State.FIGHT
	time_left = GameConfig.ROUND_TIME
	fight_started.emit()


@rpc("authority", "call_remote", "unreliable")
func _rpc_snapshot(bytes: PackedByteArray) -> void:
	if world == null or world.authority or world.map == null:
		return
	var s: Dictionary = NetSnapshot.unpack(bytes)
	time_left = float(s["time_left"])
	world.push_snapshot(s, bytes.size())


@rpc("authority", "call_remote", "reliable")
func _rpc_events(events: Array) -> void:
	if world == null or world.authority or world.map == null:
		return
	for ev: Variant in events:
		world.apply_event(ev as Array)


@rpc("authority", "call_remote", "reliable")
func _rpc_round_results(data: Dictionary) -> void:
	state = State.ROUND_RESULTS
	results_left = GameConfig.ROUND_RESULTS_TIME
	_show_round_results(data)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_results(data: Dictionary) -> void:
	dlog("match results %s" % str(data))
	state = State.MATCH_RESULTS
	_show_match_results(data)


@rpc("authority", "call_remote", "reliable")
func _rpc_to_lobby() -> void:
	reset()
	returned_to_lobby.emit()


func _show_round_results(data: Dictionary) -> void:
	last_round_data = data
	round_finished.emit(data)


func _show_match_results(data: Dictionary) -> void:
	last_match_data = data
	NetManager.clear_session()
	match_finished.emit(data)
