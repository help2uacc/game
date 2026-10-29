extends Node
## Replicated roster and scores (PRD §4, §5, §6.2, §9.5). The server owns
## the truth and broadcasts a full copy to every client whenever it changes.

signal changed
signal player_joined(pid: int)
signal player_left(pid: int)

enum Phase { NONE = 0, LOBBY = 1, IN_MATCH = 2 }

## pid -> Dictionary (see `_new_player`)
var players: Dictionary = {}
var rounds: int = GameConfig.DEFAULT_ROUNDS
var phase: int = Phase.NONE
var local_pid: int = -1
var current_round: int = 0
var host_ip: String = ""

var _next_pid: int = 1


func reset() -> void:
	players.clear()
	rounds = GameConfig.DEFAULT_ROUNDS
	phase = Phase.NONE
	local_pid = -1
	current_round = 0
	_next_pid = 1
	changed.emit()


func _new_player(pid: int, display_name: String, color: int, is_host: bool) -> Dictionary:
	return {
		"pid": pid,
		"name": display_name,
		"color": color,
		"ready": false,
		"host": is_host,
		"connected": true,
		"released": false,
		"kills": 0,
		"round_kills": 0,
		"round_wins": 0,
		"ping": 0,
		"disconnect_time": 0.0,
	}


# ---------------------------------------------------------------- queries
func get_player(pid: int) -> Dictionary:
	return players.get(pid, {})


func player_name(pid: int) -> String:
	return str(get_player(pid).get("name", "?"))


func player_color(pid: int) -> int:
	return int(get_player(pid).get("color", 0))


func is_host_pid(pid: int) -> bool:
	return bool(get_player(pid).get("host", false))


## Players holding a slot (connected or inside their reconnect window).
func active_pids() -> Array[int]:
	var out: Array[int] = []
	for pid: int in players.keys():
		if not bool(players[pid]["released"]):
			out.append(pid)
	out.sort()
	return out


func connected_pids() -> Array[int]:
	var out: Array[int] = []
	for pid: int in active_pids():
		if bool(players[pid]["connected"]):
			out.append(pid)
	return out


func in_reconnect_window_count() -> int:
	var n: int = 0
	for pid: int in active_pids():
		if not bool(players[pid]["connected"]):
			n += 1
	return n


func taken_colors(except_pid: int = -1) -> Array[int]:
	var out: Array[int] = []
	for pid: int in active_pids():
		if pid != except_pid:
			out.append(int(players[pid]["color"]))
	return out


func color_owner(color: int) -> int:
	for pid: int in active_pids():
		if int(players[pid]["color"]) == color:
			return pid
	return -1


func all_clients_ready() -> bool:
	for pid: int in connected_pids():
		var p: Dictionary = players[pid]
		if not bool(p["host"]) and not bool(p["ready"]):
			return false
	return true


## START is enabled with >= 2 players and every client ready (§9.5).
func can_start() -> bool:
	return connected_pids().size() >= GameConfig.MIN_PLAYERS and all_clients_ready()


func total_kills() -> Dictionary:
	var d: Dictionary = {}
	for pid: int in players.keys():
		d[pid] = int(players[pid]["kills"])
	return d


func round_kills() -> Dictionary:
	var d: Dictionary = {}
	for pid: int in players.keys():
		if not bool(players[pid]["released"]):
			d[pid] = int(players[pid]["round_kills"])
	return d


## All players sorted by total kills (desc), then name.
func sorted_by_kills() -> Array[int]:
	var ids: Array[int] = []
	for pid: int in players.keys():
		ids.append(pid)
	ids.sort_custom(func(a: int, b: int) -> bool:
		var ka: int = int(players[a]["kills"])
		var kb: int = int(players[b]["kills"])
		if ka != kb:
			return ka > kb
		return str(players[a]["name"]) < str(players[b]["name"]))
	return ids


# ---------------------------------------------------------------- server mutations
func server_add_player(display_name: String, is_host: bool) -> int:
	var pid: int = _next_pid
	_next_pid += 1
	var color: int = Rules.first_free_color(taken_colors())
	players[pid] = _new_player(pid, display_name, maxi(color, 0), is_host)
	player_joined.emit(pid)
	return pid


func server_remove_player(pid: int) -> void:
	if players.erase(pid):
		player_left.emit(pid)


func server_set_name(pid: int, new_name: String) -> void:
	if players.has(pid) and Rules.is_valid_name(new_name):
		players[pid]["name"] = new_name


func server_set_color(pid: int, color: int) -> bool:
	if not players.has(pid) or not Rules.can_take_color(color, taken_colors(pid)):
		return false
	players[pid]["color"] = color
	return true


func server_set_ready(pid: int, is_ready: bool) -> void:
	if players.has(pid):
		players[pid]["ready"] = is_ready


func server_set_rounds(value: int) -> void:
	rounds = Rules.clamp_rounds(value)


func server_reset_scores() -> void:
	for pid: int in players.keys():
		players[pid]["kills"] = 0
		players[pid]["round_kills"] = 0
		players[pid]["round_wins"] = 0
		players[pid]["ready"] = false
	current_round = 0


func server_reset_round_kills() -> void:
	for pid: int in players.keys():
		players[pid]["round_kills"] = 0


func server_add_kill(pid: int) -> void:
	if players.has(pid):
		players[pid]["kills"] = int(players[pid]["kills"]) + 1
		players[pid]["round_kills"] = int(players[pid]["round_kills"]) + 1


func server_add_round_win(pid: int) -> void:
	if players.has(pid):
		players[pid]["round_wins"] = int(players[pid]["round_wins"]) + 1


## Back to lobby: released players (whose window expired) are dropped.
func server_drop_released() -> void:
	for pid: int in players.keys():
		if bool(players[pid]["released"]) or not bool(players[pid]["connected"]):
			players.erase(pid)


# ---------------------------------------------------------------- replication
func to_dict() -> Dictionary:
	return {"players": players, "rounds": rounds, "phase": phase, "round": current_round}


func apply_dict(d: Dictionary) -> void:
	var old: Dictionary = players
	players = {}
	var incoming: Dictionary = d.get("players", {})
	for k: Variant in incoming.keys():
		players[int(k)] = incoming[k]
	rounds = int(d.get("rounds", rounds))
	phase = int(d.get("phase", phase))
	current_round = int(d.get("round", current_round))
	for pid: int in players.keys():
		if not old.has(pid):
			player_joined.emit(pid)
	for pid2: int in old.keys():
		if not players.has(pid2):
			player_left.emit(pid2)
	changed.emit()


func broadcast() -> void:
	changed.emit()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync.rpc(to_dict())


@rpc("authority", "call_remote", "reliable")
func _sync(d: Dictionary) -> void:
	apply_dict(d)


# ---------------------------------------------------------------- lobby requests
func _is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _sender_pid() -> int:
	return NetManager.pid_for_peer(multiplayer.get_remote_sender_id())


func request_name(new_name: String) -> void:
	if not Rules.is_valid_name(new_name):
		return
	if _is_server():
		server_set_name(local_pid, new_name)
		broadcast()
	else:
		_c_set_name.rpc_id(1, new_name)


func request_color(color: int) -> void:
	if _is_server():
		if server_set_color(local_pid, color):
			broadcast()
	else:
		_c_set_color.rpc_id(1, color)


func request_set_ready(is_ready: bool) -> void:
	if _is_server():
		server_set_ready(local_pid, is_ready)
		broadcast()
	else:
		_c_set_ready.rpc_id(1, is_ready)


func request_rounds(value: int) -> void:
	if _is_server():
		server_set_rounds(value)
		broadcast()


@rpc("any_peer", "call_remote", "reliable")
func _c_set_name(new_name: String) -> void:
	if _is_server() and phase == Phase.LOBBY:
		server_set_name(_sender_pid(), new_name)
		broadcast()


@rpc("any_peer", "call_remote", "reliable")
func _c_set_color(color: int) -> void:
	if _is_server() and phase == Phase.LOBBY and server_set_color(_sender_pid(), color):
		broadcast()


@rpc("any_peer", "call_remote", "reliable")
func _c_set_ready(is_ready: bool) -> void:
	if _is_server() and phase == Phase.LOBBY:
		server_set_ready(_sender_pid(), is_ready)
		broadcast()
