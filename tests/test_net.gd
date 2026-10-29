extends TestCase
## Networking data tests: input packing, snapshot packing (size budget),
## roster rules (colours, START conditions, rounds clamp).


func test_input_pack_roundtrip() -> void:
	var i := PlayerInput.new()
	i.seq = 123456
	i.move_x = -0.5
	i.down = true
	i.jump_pressed = true
	i.attack_held = true
	i.throw_pressed = true
	var o: PlayerInput = PlayerInput.unpack(i.pack())
	assert_eq(o.seq, 123456)
	assert_near(o.move_x, -0.5, 0.01)
	assert_eq([o.down, o.jump_pressed, o.jump_held, o.attack_held, o.pickup_pressed, o.throw_pressed],
			[true, true, false, true, false, true])
	assert_eq(i.pack().size(), 6, "6 bytes per input")


func _md() -> MapData:
	var rows: PackedStringArray = []
	for r: int in range(30):
		rows.append(("#" if r > 27 else ".").repeat(70))
	var md := MapData.new()
	md.id = "net"
	md.display_name = "Net"
	md.theme = "candy"
	md.rows = rows
	md.width = 70
	md.height = 30
	return md


func test_snapshot_roundtrip_and_budget() -> void:
	var w := World.new()
	add_node(w)
	w.load_map_data(_md())
	for pid: int in range(1, 9):
		var p: Player = w.add_player(pid, pid - 1, "P%d" % pid, pid == 1)
		p.reset_for_round(Vector3(float(pid) * 5.0 + 0.5, 2.0, 0))
		p.hp = 50 + pid
		p.armor = pid
		p.weapon_id = pid % 7
		p.ammo = pid * 2
	for k: int in range(10):
		w.spawn_projectile(ProjectileState.Type.ROCKET, 1, Vector3(float(k), 10, 0), Vector3(18, 0, 0), 5, 0)
	for k2: int in range(8):
		w.spawn_pickup(PickupState.Kind.WEAPON, 1, 12, Vector3(float(k2) * 3.0, 3, 0), false)
	var acks: Dictionary = {2: 77}
	var bytes: PackedByteArray = NetSnapshot.pack(w, acks, 42, 123.5)
	assert_true(bytes.size() <= 2048, "8 players + 10 projectiles + 8 pickups fits 2 KB (%d B)" % bytes.size())
	var s: Dictionary = NetSnapshot.unpack(bytes)
	assert_eq(int(s["tick"]), 42)
	assert_near(float(s["time_left"]), 123.5, 0.001)
	var sp: Dictionary = s["players"]
	assert_eq(sp.size(), 8)
	assert_eq(int(sp[3]["hp"]), 53)
	assert_eq(int(sp[3]["armor"]), 3)
	assert_eq(int(sp[3]["weapon"]), 3)
	assert_eq(int(sp[3]["ammo"]), 6)
	assert_eq(int(sp[2]["ack"]), 77)
	assert_true(bool(sp[1]["alive"]))
	assert_near((sp[4]["pos"] as Vector2).x, 20.5, 0.001)
	assert_eq((s["proj"] as Dictionary).size(), 10)
	assert_eq((s["pickups"] as Dictionary).size(), 8)


func test_roster_colours_and_start() -> void:
	GameState.reset()
	GameState.phase = GameState.Phase.LOBBY
	var h: int = GameState.server_add_player("Host", true)
	var a: int = GameState.server_add_player("A", false)
	assert_eq(GameState.player_color(h), 0, "first free colour")
	assert_eq(GameState.player_color(a), 1, "next free colour")
	assert_false(GameState.server_set_color(a, 0), "taken colour rejected")
	assert_true(GameState.server_set_color(a, 5), "free colour accepted")
	var b: int = GameState.server_add_player("B", false)
	assert_eq(GameState.player_color(b), 1, "freed colour reused")
	assert_false(GameState.can_start(), "clients not ready")
	GameState.server_set_ready(a, true)
	assert_false(GameState.can_start(), "one client not ready")
	GameState.server_set_ready(b, true)
	assert_true(GameState.can_start(), "all ready, 3 players")
	GameState.server_remove_player(a)
	GameState.server_remove_player(b)
	assert_false(GameState.can_start(), "needs >= 2 players")
	GameState.server_set_rounds(150)
	assert_eq(GameState.rounds, 99)
	GameState.server_set_rounds(1)
	assert_eq(GameState.rounds, 4)
	GameState.reset()


func test_eight_colours_unique() -> void:
	GameState.reset()
	var seen: Dictionary = {}
	for i: int in range(8):
		var pid: int = GameState.server_add_player("P%d" % i, i == 0)
		seen[GameState.player_color(pid)] = true
	assert_eq(seen.size(), 8, "8 unique colours")
	GameState.reset()


func test_session_token_is_uuid_v4() -> void:
	var t: String = NetManager.session_token
	assert_eq(t.length(), 36)
	assert_eq(t[14], "4", "version 4")
	assert_true("89ab".contains(t[19]), "variant bits")
