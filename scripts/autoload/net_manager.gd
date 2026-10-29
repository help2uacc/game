extends Node
## ENet host/join, handshake (protocol version, session token), reconnect,
## ping, host-left handling (PRD §5).

signal hosted
signal joined
signal join_failed(reason: String)
signal left_game(message: String)
signal reconnect_status(seconds_left: float)
signal reconnected
signal notice(text: String)

enum Role { NONE = 0, HOST = 1, CLIENT = 2 }

const SESSION_PATH := "user://session.cfg"
const MAX_ENET_PEERS := 16
const REJECT_DELAY := 0.4

var role: int = Role.NONE
var session_token: String = ""
var last_host_ip: String = ""
var ping_ms: int = 0
var reconnecting: bool = false

# Server-side maps.
var _peer_to_pid: Dictionary = {}
var _pid_to_peer: Dictionary = {}
var _token_to_pid: Dictionary = {}

var _connecting: bool = false
var _connect_t: float = 0.0
var _accepted: bool = false
var _leaving: bool = false
var _host_left: bool = false
var _rejected: String = ""
var _reconnect_elapsed: float = 0.0
var _retry_t: float = 0.0
var _ping_t: float = 0.0
var _session_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	session_token = _uuid_v4()


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


func is_online() -> bool:
	return role != Role.NONE


## Client: connected and accepted by the host.
func is_connected_to_host() -> bool:
	if role != Role.CLIENT or not _accepted:
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func peer_for(pid: int) -> int:
	return int(_pid_to_peer.get(pid, -1))


func pid_for_peer(peer_id: int) -> int:
	return int(_peer_to_pid.get(peer_id, -1))


static func _uuid_v4() -> String:
	var b: PackedByteArray = Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var h: String = b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


# ================================================================ host
## Creates the server and the discovery responder (§9.3).
func host() -> int:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(GameConfig.GAME_PORT, MAX_ENET_PEERS)
	if err != OK:
		return err
	if not LanDiscovery.start_responder():
		peer.close()
		return ERR_CANT_CREATE
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	_leaving = false
	GameState.reset()
	GameState.phase = GameState.Phase.LOBBY
	GameState.host_ip = ", ".join(local_ipv4_addresses())
	GameState.local_pid = GameState.server_add_player(Settings.player_name, true)
	_pid_to_peer[GameState.local_pid] = 1
	_peer_to_pid[1] = GameState.local_pid
	GameState.broadcast()
	hosted.emit()
	return OK


static func local_ipv4_addresses() -> Array[String]:
	var out: Array[String] = []
	for ip: String in IP.get_local_addresses():
		if DiscoveryProtocol.is_private_ipv4(ip) and not out.has(ip):
			out.append(ip)
	out.sort()
	return out


# ================================================================ join
func join(ip: String, is_reconnect: bool = false) -> int:
	if not is_reconnect:
		close()
	elif multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(ip, GameConfig.GAME_PORT)
	if err != OK:
		if not is_reconnect:
			join_failed.emit("Could not connect")
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	last_host_ip = ip
	GameState.host_ip = ip
	_connecting = true
	_connect_t = 0.0
	_accepted = false
	_leaving = false
	_host_left = false
	_rejected = ""
	return OK


## REJOIN from the main menu (§5.5): valid session < 60 s old.
func saved_session() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return {}
	var t: float = float(cfg.get_value("session", "time", 0.0))
	var age: float = Time.get_unix_time_from_system() - t
	if age < 0.0 or age > GameConfig.RECONNECT_WINDOW:
		return {}
	var token: String = str(cfg.get_value("session", "token", ""))
	var ip: String = str(cfg.get_value("session", "host_ip", ""))
	if token.is_empty() or not DiscoveryProtocol.is_valid_ipv4(ip):
		return {}
	return {"token": token, "host_ip": ip, "age": age}


func rejoin_saved() -> int:
	var s: Dictionary = saved_session()
	if s.is_empty():
		return ERR_DOES_NOT_EXIST
	session_token = str(s["token"])
	return join(str(s["host_ip"]))


func _write_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "token", session_token)
	cfg.set_value("session", "host_ip", last_host_ip)
	cfg.set_value("session", "time", Time.get_unix_time_from_system())
	cfg.save(SESSION_PATH)


func clear_session() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))


# ================================================================ leave
## Leave: the host ends the game for everyone (§5.4).
func leave(message: String = "") -> void:
	if role == Role.HOST and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_s_host_left.rpc()
		_leaving = true
		await get_tree().create_timer(0.25).timeout
	_leaving = true
	clear_session()
	close()
	left_game.emit(message)


## Best effort when the host app is closed: tell clients right away.
func notify_host_closing() -> void:
	if role == Role.HOST and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_s_host_left.rpc()
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).host.flush()


func close() -> void:
	LanDiscovery.stop_responder()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.NONE
	_peer_to_pid.clear()
	_pid_to_peer.clear()
	_token_to_pid.clear()
	_connecting = false
	_accepted = false
	reconnecting = false
	GameState.reset()


func _process(delta: float) -> void:
	if _connecting and not reconnecting:
		_connect_t += delta
		if _connect_t >= GameConfig.CONNECT_TIMEOUT:
			_connecting = false
			close()
			join_failed.emit("Could not connect")
	if reconnecting:
		_reconnect_elapsed += delta
		_retry_t += delta
		reconnect_status.emit(maxf(0.0, GameConfig.RECONNECT_WINDOW - _reconnect_elapsed))
		if _reconnect_elapsed >= GameConfig.RECONNECT_WINDOW:
			reconnecting = false
			clear_session()
			close()
			left_game.emit("Host left the game")
		elif _retry_t >= GameConfig.RECONNECT_RETRY_INTERVAL and not _accepted:
			_retry_t = 0.0
			join(last_host_ip, true)
	_debug_drop(delta)
	if is_connected_to_host():
		_ping_t += delta
		if _ping_t >= GameConfig.PING_INTERVAL:
			_ping_t = 0.0
			_c_ping.rpc_id(1, Time.get_ticks_msec(), ping_ms)
		_session_t += delta
		if _session_t >= 5.0 and GameState.phase == GameState.Phase.IN_MATCH:
			_session_t = 0.0
			_write_session()
	if role == Role.HOST:
		_server_tick_reconnect_windows()


# ================================================================ multiplayer signals
func _on_peer_connected(peer_id: int) -> void:
	# The client introduces itself with _c_hello. Detect dead peers quickly.
	if role == Role.HOST:
		_set_fast_timeout(peer_id)


func _set_fast_timeout(peer_id: int) -> void:
	var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var pp: ENetPacketPeer = enet.get_peer(peer_id)
	if pp != null:
		pp.set_timeout(32, 3000, 8000)


func _on_connected_to_server() -> void:
	_set_fast_timeout(1)
	_c_hello.rpc_id(1, GameConfig.NET_PROTOCOL_VERSION, Settings.player_name, session_token)


func _on_connection_failed() -> void:
	if reconnecting:
		return
	_connecting = false
	close()
	join_failed.emit("Could not connect")


func _on_server_disconnected() -> void:
	if _leaving:
		return
	if not _rejected.is_empty():
		var reason: String = _rejected
		close()
		join_failed.emit(reason)
		return
	if _host_left or not _accepted:
		clear_session()
		close()
		left_game.emit("Host left the game")
		return
	if GameState.phase == GameState.Phase.IN_MATCH:
		# Connection lost mid-match: retry the host every 2 s for 60 s (§5.5).
		_write_session()
		_accepted = false
		reconnecting = true
		_reconnect_elapsed = 0.0
		_retry_t = 0.0
		reconnect_status.emit(GameConfig.RECONNECT_WINDOW)
		return
	clear_session()
	close()
	left_game.emit("Host left the game")


func cancel_reconnect() -> void:
	reconnecting = false
	leave("")


# ================================================================ server side
func _on_peer_disconnected(peer_id: int) -> void:
	if role != Role.HOST:
		return
	var pid: int = pid_for_peer(peer_id)
	_peer_to_pid.erase(peer_id)
	if pid < 0:
		return
	_pid_to_peer.erase(pid)
	var pname: String = GameState.player_name(pid)
	if GameState.phase == GameState.Phase.IN_MATCH:
		# Keep the slot for the reconnect window (§5.5).
		GameState.players[pid]["connected"] = false
		GameState.players[pid]["disconnect_time"] = Time.get_ticks_msec() / 1000.0
		MatchManager.server_on_player_disconnected(pid)
	else:
		for t: String in _token_to_pid.keys():
			if int(_token_to_pid[t]) == pid:
				_token_to_pid.erase(t)
		GameState.server_remove_player(pid)
	GameState.broadcast()
	send_notice("%s left" % pname, "player_leave")


func _server_tick_reconnect_windows() -> void:
	if GameState.phase != GameState.Phase.IN_MATCH:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var changed_any: bool = false
	for pid: int in GameState.active_pids():
		var p: Dictionary = GameState.players[pid]
		if not bool(p["connected"]) and now - float(p["disconnect_time"]) >= GameConfig.RECONNECT_WINDOW:
			p["released"] = true
			changed_any = true
			for t: String in _token_to_pid.keys():
				if int(_token_to_pid[t]) == pid:
					_token_to_pid.erase(t)
	if changed_any:
		GameState.broadcast()
		MatchManager.server_check_enough_players()


func send_notice(text: String, sfx: String = "") -> void:
	if role == Role.HOST:
		_s_notice.rpc(text, sfx)
		_show_notice(text, sfx)


func _show_notice(text: String, sfx: String) -> void:
	notice.emit(text)
	if not sfx.is_empty():
		AudioManager.play_ui(sfx)


func _reject(peer_id: int, reason: String) -> void:
	_s_rejected.rpc_id(peer_id, reason)
	await get_tree().create_timer(REJECT_DELAY).timeout
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and role == Role.HOST:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _c_hello(version: int, player_name: String, token: String) -> void:
	if role != Role.HOST:
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if version != GameConfig.NET_PROTOCOL_VERSION:
		_reject(peer_id, "Version mismatch — update the app")
		return
	var clean_name: String = Rules.sanitize_name(player_name, "Player")
	var pid: int = -1
	var reconnect: bool = false
	if _token_to_pid.has(token):
		var existing: int = int(_token_to_pid[token])
		var slot: Dictionary = GameState.get_player(existing)
		if not slot.is_empty() and not bool(slot["released"]) and not bool(slot["connected"]):
			pid = existing
			reconnect = true
	if pid < 0:
		if GameState.phase == GameState.Phase.IN_MATCH:
			_reject(peer_id, "Match in progress")  # TODO(PRD): message for joins during a match
			return
		if GameState.connected_pids().size() >= GameConfig.MAX_PLAYERS:
			_reject(peer_id, "Game is full")
			return
		pid = GameState.server_add_player(clean_name, false)
		_token_to_pid[token] = pid
	else:
		GameState.players[pid]["connected"] = true
	_peer_to_pid[peer_id] = pid
	_pid_to_peer[pid] = peer_id
	_s_welcome.rpc_id(peer_id, pid, reconnect)
	GameState.broadcast()
	send_notice("%s joined" % GameState.player_name(pid), "player_join")
	if reconnect:
		MatchManager.server_on_player_reconnected(pid, peer_id)


@rpc("any_peer", "call_remote", "unreliable")
func _c_ping(client_ms: int, last_ping: int) -> void:
	if role != Role.HOST:
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	var pid: int = pid_for_peer(peer_id)
	if pid >= 0 and GameState.players.has(pid):
		GameState.players[pid]["ping"] = last_ping
	_s_pong.rpc_id(peer_id, client_ms)


@rpc("authority", "call_remote", "unreliable")
func _s_pong(client_ms: int) -> void:
	ping_ms = maxi(0, Time.get_ticks_msec() - client_ms)


@rpc("authority", "call_remote", "reliable")
func _s_welcome(pid: int, is_reconnect: bool) -> void:
	_connecting = false
	_accepted = true
	GameState.local_pid = pid
	_write_session()
	if reconnecting or is_reconnect:
		reconnecting = false
		reconnected.emit()
	else:
		joined.emit()


@rpc("authority", "call_remote", "reliable")
func _s_rejected(reason: String) -> void:
	_rejected = reason
	_connecting = false


@rpc("authority", "call_remote", "reliable")
func _s_host_left() -> void:
	_host_left = true
	_leaving = true
	clear_session()
	close()
	left_game.emit("Host left the game")


@rpc("authority", "call_remote", "reliable")
func _s_notice(text: String, sfx: String) -> void:
	_show_notice(text, sfx)


var _debug_elapsed: float = 0.0
var _debug_dropped: bool = false


## Debug builds: --drop-at=SECONDS simulates a lost connection (smoke test).
func _debug_drop(delta: float) -> void:
	if _debug_dropped or role != Role.CLIENT or not OS.is_debug_build():
		return
	_debug_elapsed += delta
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--drop-at=") and _debug_elapsed >= a.trim_prefix("--drop-at=").to_float() and _accepted:
			_debug_dropped = true
			MatchManager.dlog("simulating connection loss")
			multiplayer.multiplayer_peer.close()
			_on_server_disconnected()
