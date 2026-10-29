class_name DiscoveryProtocol
extends RefCounted
## LAN discovery packets (§5.2): UTF-8 JSON.

const TYPE_DISCOVER := "BB_DISCOVER"
const TYPE_HOST := "BB_HOST"


static func encode_discover() -> PackedByteArray:
	return JSON.stringify({"t": TYPE_DISCOVER, "v": GameConfig.NET_PROTOCOL_VERSION}).to_utf8_buffer()


static func encode_host(game_name: String, players: int, max_players: int, state: String, port: int) -> PackedByteArray:
	var d: Dictionary = {
		"t": TYPE_HOST,
		"v": GameConfig.NET_PROTOCOL_VERSION,
		"name": game_name,
		"players": players,
		"max": max_players,
		"state": state,
		"port": port,
	}
	return JSON.stringify(d).to_utf8_buffer()


## Returns the decoded dictionary, or an empty dictionary if the packet is
## not a well-formed Block Brawl discovery packet.
static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty() or data.size() > 1024:
		return {}
	var text: String = data.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = json.data
	if not d.has("t") or not d.has("v"):
		return {}
	var t: String = str(d["t"])
	if t != TYPE_DISCOVER and t != TYPE_HOST:
		return {}
	if typeof(d["v"]) != TYPE_FLOAT and typeof(d["v"]) != TYPE_INT:
		return {}
	d["v"] = int(d["v"])
	if t == TYPE_HOST:
		for key: String in ["name", "players", "max", "state", "port"]:
			if not d.has(key):
				return {}
		d["players"] = int(d["players"])
		d["max"] = int(d["max"])
		d["port"] = int(d["port"])
		d["name"] = str(d["name"])
		d["state"] = str(d["state"])
	return d


static func is_compatible(packet: Dictionary) -> bool:
	return not packet.is_empty() and int(packet.get("v", -1)) == GameConfig.NET_PROTOCOL_VERSION


## Private IPv4 check (10.x, 172.16-31.x, 192.168.x).
static func is_private_ipv4(ip: String) -> bool:
	if not ip.is_valid_ip_address() or ip.contains(":"):
		return false
	var parts: PackedStringArray = ip.split(".")
	var a: int = parts[0].to_int()
	var b: int = parts[1].to_int()
	if a == 10:
		return true
	if a == 172 and b >= 16 and b <= 31:
		return true
	return a == 192 and b == 168


static func is_valid_ipv4(ip: String) -> bool:
	var parts: PackedStringArray = ip.strip_edges().split(".")
	if parts.size() != 4:
		return false
	for p: String in parts:
		if p.is_empty() or p.length() > 3 or not p.is_valid_int():
			return false
		var n: int = p.to_int()
		if n < 0 or n > 255:
			return false
	return true


## /24 subnet broadcast address for an IPv4 address.
static func broadcast_address(ip: String) -> String:
	var parts: PackedStringArray = ip.split(".")
	return "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
