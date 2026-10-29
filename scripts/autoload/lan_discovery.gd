extends Node
## LAN discovery (PRD §5.2) without native plugins: broadcast probe and
## unicast /24 subnet sweep in parallel every 2 s; the host replies unicast.

signal hosts_changed

## ip -> {"name", "players", "max", "state", "port", "ip", "seen"}
var hosts: Dictionary = {}

var _responder: PacketPeerUDP = null
var _searcher: PacketPeerUDP = null
var _search_t: float = 0.0
var _searching: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ---------------------------------------------------------------- host side
func start_responder() -> bool:
	stop_responder()
	var udp := PacketPeerUDP.new()
	if udp.bind(GameConfig.DISCOVERY_PORT, "*") != OK:
		return false
	_responder = udp
	return true


func stop_responder() -> void:
	if _responder != null:
		_responder.close()
		_responder = null


func _host_info() -> PackedByteArray:
	var host_name: String = "%s's game" % Settings.player_name
	var state: String = "in_match" if GameState.phase == GameState.Phase.IN_MATCH else "lobby"
	return DiscoveryProtocol.encode_host(host_name, GameState.connected_pids().size(), GameConfig.MAX_PLAYERS,
			state, GameConfig.GAME_PORT)


func _poll_responder() -> void:
	while _responder.get_available_packet_count() > 0:
		var data: PackedByteArray = _responder.get_packet()
		var ip: String = _responder.get_packet_ip()
		var port: int = _responder.get_packet_port()
		var pkt: Dictionary = DiscoveryProtocol.decode(data)
		if pkt.is_empty() or str(pkt["t"]) != DiscoveryProtocol.TYPE_DISCOVER:
			continue
		if not DiscoveryProtocol.is_compatible(pkt):
			continue
		_responder.set_dest_address(ip, port)
		_responder.put_packet(_host_info())


# ---------------------------------------------------------------- client side
func start_search() -> void:
	stop_search()
	_searcher = PacketPeerUDP.new()
	_searcher.set_broadcast_enabled(true)
	if _searcher.bind(0, "*") != OK:
		_searcher = null
		return
	_searching = true
	_search_t = GameConfig.DISCOVERY_INTERVAL
	hosts.clear()
	hosts_changed.emit()


func stop_search() -> void:
	_searching = false
	if _searcher != null:
		_searcher.close()
		_searcher = null


func _send_probes() -> void:
	var probe: PackedByteArray = DiscoveryProtocol.encode_discover()
	var targets: Array[String] = ["255.255.255.255"]
	var local: Array[String] = []
	for ip: String in IP.get_local_addresses():
		if DiscoveryProtocol.is_private_ipv4(ip):
			local.append(ip)
	for ip2: String in local:
		var bc: String = DiscoveryProtocol.broadcast_address(ip2)
		if not targets.has(bc):
			targets.append(bc)
	# 1. Broadcast probe.
	for t: String in targets:
		_send(t, probe)
	# 2. Unicast /24 sweep of every private interface.  # TODO(PRD): netmask is not available without native code; /24 assumed
	var swept: Dictionary = {}
	for ip3: String in local:
		var parts: PackedStringArray = ip3.split(".")
		var prefix: String = "%s.%s.%s." % [parts[0], parts[1], parts[2]]
		if swept.has(prefix):
			continue
		swept[prefix] = true
		for h: int in range(1, 255):
			_send(prefix + str(h), probe)
	# Same-machine testing (several editor instances).
	if OS.is_debug_build():
		_send("127.0.0.1", probe)


func _send(ip: String, data: PackedByteArray) -> void:
	_searcher.set_dest_address(ip, GameConfig.DISCOVERY_PORT)
	_searcher.put_packet(data)


func _poll_searcher(delta: float) -> void:
	_search_t += delta
	if _search_t >= GameConfig.DISCOVERY_INTERVAL:
		_search_t = 0.0
		_send_probes()
	var changed_any: bool = false
	var now: float = Time.get_ticks_msec() / 1000.0
	while _searcher.get_available_packet_count() > 0:
		var data: PackedByteArray = _searcher.get_packet()
		var ip: String = _searcher.get_packet_ip()
		var pkt: Dictionary = DiscoveryProtocol.decode(data)
		if pkt.is_empty() or str(pkt["t"]) != DiscoveryProtocol.TYPE_HOST or not DiscoveryProtocol.is_compatible(pkt):
			continue
		var key: String = ip
		# A host answering on loopback and on its LAN address is listed once.
		if ip == "127.0.0.1":
			for other: String in hosts.keys():
				if other != ip and str(hosts[other]["name"]) == str(pkt["name"]):
					key = other
		pkt["ip"] = key
		pkt["seen"] = now
		if not hosts.has(key) or str(hosts[key]["state"]) != str(pkt["state"]) or int(hosts[key]["players"]) != int(pkt["players"]):
			changed_any = true
		hosts[key] = pkt
	# Remove hosts not seen for 6 s.
	for k: String in hosts.keys():
		if now - float(hosts[k]["seen"]) > GameConfig.DISCOVERY_HOST_TIMEOUT:
			hosts.erase(k)
			changed_any = true
	if changed_any:
		hosts_changed.emit()


func _process(delta: float) -> void:
	if _responder != null:
		_poll_responder()
	if _searching and _searcher != null:
		_poll_searcher(delta)
