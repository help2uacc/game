extends TestCase
## Combat integration tests (PRD §6.5, §7, §10.1 hazards, §4.3 credit).

const DT := 1.0 / 60.0


## 80x30 map: floor top y=2 for x in [2, 75); wall (block column) at
## x=40..41 rising to y=8; lava at x=50..52 (y=1); spikes at x=55 (y=2);
## jump pad at x=60 (y=2); crate at x=65 (y=2).
func _map() -> MapData:
	var rows: PackedStringArray = []
	for r: int in range(30):
		var y: int = 29 - r
		var line: PackedByteArray = ".".repeat(80).to_ascii_buffer()
		for x: int in range(2, 75):
			if y <= 1:
				line[x] = "#".unicode_at(0)
		if y >= 2 and y <= 7:
			line[40] = "#".unicode_at(0)
			line[41] = "#".unicode_at(0)
		if y == 1:
			for x2: int in [50, 51, 52]:
				line[x2] = "L".unicode_at(0)
		if y == 2:
			line[55] = "^".unicode_at(0)
			line[60] = "J".unicode_at(0)
			line[65] = "C".unicode_at(0)
		if y == 2 and (r % 2 == 1):
			pass
		rows.append(line.get_string_from_ascii())
	var md := MapData.new()
	md.id = "combat_test"
	md.display_name = "Combat Test"
	md.theme = "candy"
	md.rows = rows
	md.width = 80
	md.height = 30
	return md


func _world() -> World:
	var w := World.new()
	add_node(w)
	w.load_map_data(_map())
	w.spawning_enabled = false
	_world_ref = w
	# Weapon spawn points for spawn tests.
	for x: int in range(5, 23, 3):
		w.map.weapon_spawns.append(Vector3(float(x) + 0.5, 2.0, 0))
	for x2: int in range(26, 35, 4):
		w.map.item_spawns.append(Vector3(float(x2) + 0.5, 2.0, 0))
	return w


func _add(w: World, pid: int, x: float) -> Player:
	var p: Player = w.add_player(pid, pid % 8, "P%d" % pid, pid == 1)
	p.reset_for_round(Vector3(x, 2.05, 0))
	return p


func _steps(w: World, n: int) -> void:
	for i: int in range(n):
		w._server_step(DT)


var _world_ref: World = null


func _settle() -> void:
	await physics_frames(6)
	# From here on the test drives the simulation manually.
	if _world_ref != null:
		_world_ref.set_physics_process(false)


func test_pistol_auto_aim_damage_and_ammo() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	var b: Player = _add(w, 2, 6.5)  # behind the shooter
	await _settle()
	a.facing = 1
	a.weapon_id = GameConfig.WeaponId.PISTOL
	a.ammo = 12
	w.attack(a)
	assert_eq(a.facing, -1, "auto-aim turns to face the target")
	assert_eq(b.hp, 100 - 18, "pistol damage 18")
	assert_eq(a.ammo, 11, "ammo decremented")
	assert_true(a.fire_cooldown > 0.3, "fire rate cooldown 1/3 s")


func test_armor_absorbs_first() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	var b: Player = _add(w, 2, 14.5)
	await _settle()
	b.armor = 10
	w.damage_player(b, 18, a.pid, GameConfig.Cause.PISTOL, Vector3.RIGHT, 0.0)
	assert_eq([b.hp, b.armor], [92, 0])


func test_no_target_fires_horizontally_facing() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 30.5)
	var b: Player = _add(w, 2, 44.5)  # behind the wall at x=40..41
	await _settle()
	a.facing = -1
	a.weapon_id = GameConfig.WeaponId.SNIPER
	a.ammo = 4
	assert_true(w.find_auto_aim_target(a, 60.0) == null, "wall blocks line of sight")
	w.attack(a)
	assert_eq(a.facing, -1, "kept facing")
	assert_eq(b.hp, 100, "no damage through wall")


func test_nearest_target_chosen() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 20.5)
	var far: Player = _add(w, 2, 30.5)
	var near: Player = _add(w, 3, 15.5)
	await _settle()
	assert_eq(w.find_auto_aim_target(a, 25.0), near)
	assert_true(w.find_auto_aim_target(a, 4.0) == null, "out of range")
	assert_ne(far.pid, near.pid)


func test_out_of_ammo_removes_weapon() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	_add(w, 2, 20.5)
	await _settle()
	a.weapon_id = GameConfig.WeaponId.SMG
	a.ammo = 1
	w.attack(a)
	assert_eq(a.weapon_id, 0, "weapon removed at 0 ammo")
	assert_eq(w.weapon_pickup_count(), 0, "not dropped as pickup")


func test_shotgun_pellets_and_single_knockback() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	var b: Player = _add(w, 2, 12.5)
	await _settle()
	a.weapon_id = GameConfig.WeaponId.SHOTGUN
	a.ammo = 6
	w.attack(a)
	var dmg: int = 100 - b.hp
	assert_true(dmg >= 9 * 4 and dmg % 9 == 0, "multiple pellets of 9 hit (%d)" % dmg)
	# Knockback 8 applied once: horizontal speed about 8 (direction ~ +x).
	assert_true(b.velocity.x > 6.0 and b.velocity.x < 9.0, "single knockback (%f)" % b.velocity.x)


func test_punch() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	var b: Player = _add(w, 2, 11.5)
	var c: Player = _add(w, 3, 14.5)
	await _settle()
	a.facing = 1
	w.attack(a)
	assert_eq(b.hp, 88, "punch 12")
	assert_eq(c.hp, 100, "out of punch range")
	assert_near(a.fire_cooldown, 0.45, 0.001)


func test_pickup_and_drop_on_swap() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	await _settle()
	var pk: PickupState = w.spawn_pickup(PickupState.Kind.WEAPON, GameConfig.WeaponId.SNIPER, 4, Vector3(10.5, 2.0, 0), false)
	pk.resting = true
	a.weapon_id = GameConfig.WeaponId.PISTOL
	a.ammo = 5
	assert_true(w.try_pickup_weapon(a), "picked up")
	assert_eq([a.weapon_id, a.ammo], [GameConfig.WeaponId.SNIPER, 4])
	assert_eq(w.weapon_pickup_count(), 1, "old weapon dropped")
	var dropped: PickupState = w.pickups.values()[0]
	assert_eq([dropped.weapon_id, dropped.ammo], [GameConfig.WeaponId.PISTOL, 5], "dropped keeps ammo")
	var far_pk: PickupState = w.spawn_pickup(PickupState.Kind.WEAPON, GameConfig.WeaponId.SMG, 40, Vector3(14.5, 2.0, 0), false)
	far_pk.resting = true
	assert_false(w.overlaps_pickup(a, far_pk), "pickup radius 1.0")


func test_throw_hits_and_becomes_pickup() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	var b: Player = _add(w, 2, 13.5)
	await _settle()
	a.facing = 1
	a.weapon_id = GameConfig.WeaponId.SHOTGUN
	a.ammo = 3
	assert_true(w.throw_weapon(a))
	assert_eq(a.weapon_id, 0, "unarmed after throw")
	_steps(w, 30)
	assert_eq(b.hp, 100 - GameConfig.THROW_DAMAGE, "thrown weapon deals 15")
	assert_eq(w.projectiles.size(), 0)
	assert_eq(w.weapon_pickup_count(), 1, "falls as a pickup")
	var pk: PickupState = w.pickups.values()[0]
	assert_eq([pk.weapon_id, pk.ammo], [GameConfig.WeaponId.SHOTGUN, 3], "keeps remaining ammo")


func test_ground_weapon_despawns_after_30s() -> void:
	var w: World = _world()
	_add(w, 1, 30.5)
	await _settle()
	var pk: PickupState = w.spawn_pickup(PickupState.Kind.WEAPON, 1, 12, Vector3(10.5, 2.0, 0), false)
	pk.resting = true
	pk.age = 26.9
	_steps(w, 1)
	assert_false(pk.blinking(), "not blinking before last 3 s")
	pk.age = 27.1
	assert_true(pk.blinking(), "blinks during last 3 s")
	pk.age = 29.99
	_steps(w, 2)
	assert_eq(w.weapon_pickup_count(), 0, "despawned")


func test_items_heal_and_armor_capped() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	await _settle()
	a.hp = 80
	var h: PickupState = w.spawn_pickup(PickupState.Kind.HEALTH, 0, 0, Vector3(10.5, 2.0, 0), false)
	h.resting = true
	_steps(w, 1)
	assert_eq(a.hp, 100, "health capped at 100")
	a.armor = 20
	var ar: PickupState = w.spawn_pickup(PickupState.Kind.ARMOR, 0, 0, Vector3(10.5, 2.0, 0), false)
	ar.resting = true
	_steps(w, 1)
	assert_eq(a.armor, 50, "armor capped at 50")
	assert_eq(w.pickups.size(), 0)


func test_spawning_rules() -> void:
	var w: World = _world()
	_add(w, 1, 50.0)
	await _settle()
	w.spawning_enabled = true
	w.start_fight()
	assert_eq(w.weapon_pickup_count(), 3, "3 weapons at round start")
	_steps(w, int(8.0 / DT) + 2)
	assert_eq(w.weapon_pickup_count(), 4, "+1 after 8 s")
	_steps(w, int(17.0 / DT))
	assert_eq(w.weapon_pickup_count(), 6, "6 weapons at 25 s")
	for pk0: PickupState in w.pickups.values():
		pk0.age = 0.0
	_steps(w, int(5.5 / DT))
	assert_eq(w.weapon_pickup_count(), 6, "capped at 6")
	assert_eq(w.item_pickup_count(), 1, "first item at 30 s")
	_steps(w, int(20.0 / DT) + 2)
	assert_eq(w.item_pickup_count(), 2, "second item 20 s later")
	_steps(w, int(20.0 / DT) + 2)
	assert_eq(w.item_pickup_count(), 2, "max 2 items")
	for pk: PickupState in w.pickups.values():
		for other: PickupState in w.pickups.values():
			if other != pk:
				assert_true(pk.pos.distance_to(other.pos) >= GameConfig.PICKUP_FREE_RADIUS, "free points only")


func test_lava_kills_with_environment_credit() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 46.5)
	var b: Player = _add(w, 2, 51.5)
	await _settle()
	var deaths: Array = []
	w.player_died.connect(func(v: int, k: int, c: int) -> void: deaths.append([v, k, c]))
	w.damage_player(b, 10, a.pid, GameConfig.Cause.PISTOL, Vector3.ZERO, 0.0)
	b.global_position = Vector3(51.5, 1.2, 0)
	_steps(w, 1)
	assert_false(b.alive, "lava is instant death")
	assert_eq(deaths[0], [2, 1, GameConfig.Cause.LAVA], "last attacker within 5 s credited")


func test_spikes_damage_bounce_invulnerability() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 30.5)
	await _settle()
	a.global_position = Vector3(55.5, 2.05, 0)
	_steps(w, 1)
	assert_eq(a.hp, 100 - GameConfig.SPIKE_DAMAGE, "34 damage")
	assert_true(a.velocity.y > 5.0, "bounced up")
	assert_true(a.invuln_t > 0.4, "0.5 s invulnerability")
	a.global_position = Vector3(55.5, 2.05, 0)
	_steps(w, 1)
	assert_eq(a.hp, 100 - GameConfig.SPIKE_DAMAGE, "no damage while invulnerable")


func test_jump_pad_launch() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 30.5)
	await _settle()
	a.global_position = Vector3(60.5, 2.05, 0)
	_steps(w, 1)
	assert_true(a.velocity.y > 18.0, "launched at 20 m/s (%f)" % a.velocity.y)


func test_crate_has_30_hp() -> void:
	var w: World = _world()
	await _settle()
	var c: Crate = w.map.crates[0]
	w.damage_crate(c, 18)
	assert_true(c.alive, "survives 18")
	w.damage_crate(c, 18)
	assert_false(c.alive, "destroyed at 30 HP")


func test_rocket_direct_hit_and_self_damage() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	var b: Player = _add(w, 2, 18.5)
	await _settle()
	a.weapon_id = GameConfig.WeaponId.ROCKET
	a.ammo = 3
	w.attack(a)
	assert_eq(w.projectiles.size(), 1, "rocket spawned")
	_steps(w, 40)
	assert_eq(b.hp, 40, "direct hit 60")
	assert_eq(w.projectiles.size(), 0)
	# Self damage: explosion at own feet deals 50 %.
	var r: WeaponData = WeaponDB.weapon(GameConfig.WeaponId.ROCKET)
	w.explode(a.global_position + Vector3(0, 0.9, 0), a.pid, r, null)
	assert_eq(a.hp, 100 - 30, "self damage 50 % of 60")


func test_grenade_explodes_after_fuse() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	var b: Player = _add(w, 2, 16.5)
	await _settle()
	a.weapon_id = GameConfig.WeaponId.GRENADE
	a.ammo = 3
	w.attack(a)
	assert_eq(w.projectiles.size(), 1)
	_steps(w, int(1.9 / DT))
	assert_eq(w.projectiles.size(), 1, "still fused")
	_steps(w, 10)
	assert_eq(w.projectiles.size(), 0, "exploded at 2 s")
	assert_true(b.hp < 100, "grenade landed near the target (hp %d)" % b.hp)


func test_self_kill_credit_goes_to_recent_enemy() -> void:
	var w: World = _world()
	var a: Player = _add(w, 1, 10.5)
	var b: Player = _add(w, 2, 20.5)
	await _settle()
	var deaths: Array = []
	w.player_died.connect(func(v: int, k: int, c: int) -> void: deaths.append([v, k, c]))
	w.damage_player(a, 70, b.pid, GameConfig.Cause.SNIPER, Vector3.ZERO, 0.0)
	var r: WeaponData = WeaponDB.weapon(GameConfig.WeaponId.ROCKET)
	w.explode(a.global_position + Vector3(0, 0.9, 0), a.pid, r, null)
	assert_false(a.alive)
	assert_eq(int(deaths[0][1]), 2, "enemy within 5 s gets the kill, not self")
