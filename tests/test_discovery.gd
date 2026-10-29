extends TestCase


func test_discover_roundtrip() -> void:
	var d: Dictionary = DiscoveryProtocol.decode(DiscoveryProtocol.encode_discover())
	assert_eq(d.get("t"), "BB_DISCOVER")
	assert_eq(d.get("v"), 1)
	assert_true(DiscoveryProtocol.is_compatible(d))


func test_host_roundtrip() -> void:
	var bytes: PackedByteArray = DiscoveryProtocol.encode_host("Joe's game", 3, 8, "lobby", 47820)
	var d: Dictionary = DiscoveryProtocol.decode(bytes)
	assert_eq(d.get("t"), "BB_HOST")
	assert_eq(d.get("name"), "Joe's game")
	assert_eq(d.get("players"), 3)
	assert_eq(d.get("max"), 8)
	assert_eq(d.get("state"), "lobby")
	assert_eq(d.get("port"), 47820)
	assert_true(DiscoveryProtocol.is_compatible(d))


func test_exact_json_format() -> void:
	var text: String = DiscoveryProtocol.encode_discover().get_string_from_utf8()
	var parsed: Dictionary = JSON.parse_string(text)
	assert_eq(parsed.size(), 2)
	assert_eq(parsed["t"], "BB_DISCOVER")


func test_version_mismatch_rejected() -> void:
	var bytes: PackedByteArray = '{"t":"BB_HOST","v":2,"name":"x","players":1,"max":8,"state":"lobby","port":47820}'.to_utf8_buffer()
	var d: Dictionary = DiscoveryProtocol.decode(bytes)
	assert_false(d.is_empty(), "well formed")
	assert_false(DiscoveryProtocol.is_compatible(d), "wrong version")


func test_garbage_rejected() -> void:
	assert_true(DiscoveryProtocol.decode("hello".to_utf8_buffer()).is_empty())
	assert_true(DiscoveryProtocol.decode(PackedByteArray()).is_empty())
	assert_true(DiscoveryProtocol.decode('{"t":"OTHER","v":1}'.to_utf8_buffer()).is_empty())
	assert_true(DiscoveryProtocol.decode('{"t":"BB_HOST","v":1}'.to_utf8_buffer()).is_empty())
	assert_true(DiscoveryProtocol.decode('[1,2]'.to_utf8_buffer()).is_empty())


func test_ip_helpers() -> void:
	assert_true(DiscoveryProtocol.is_valid_ipv4("192.168.1.20"))
	assert_false(DiscoveryProtocol.is_valid_ipv4("192.168.1"))
	assert_false(DiscoveryProtocol.is_valid_ipv4("192.168.1.256"))
	assert_false(DiscoveryProtocol.is_valid_ipv4("a.b.c.d"))
	assert_true(DiscoveryProtocol.is_private_ipv4("10.0.0.3"))
	assert_true(DiscoveryProtocol.is_private_ipv4("172.20.1.1"))
	assert_false(DiscoveryProtocol.is_private_ipv4("172.32.1.1"))
	assert_true(DiscoveryProtocol.is_private_ipv4("192.168.43.1"))
	assert_false(DiscoveryProtocol.is_private_ipv4("8.8.8.8"))
	assert_eq(DiscoveryProtocol.broadcast_address("192.168.43.17"), "192.168.43.255")
