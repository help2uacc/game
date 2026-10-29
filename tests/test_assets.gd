extends TestCase
## Data/asset checks: weapon + item values match PRD §7.3/§7.4 and every
## generated asset exists.

const SFX: PackedStringArray = [
	"ui_click", "ui_back", "ui_toggle", "ready", "player_join", "player_leave", "countdown_tick",
	"round_start", "round_end", "match_win", "jump", "double_jump", "land", "footstep", "punch_swing",
	"punch_hit", "pickup_weapon", "pickup_health", "pickup_armor", "throw", "thrown_hit", "weapon_empty",
	"pistol", "smg", "shotgun", "sniper", "rocket_launch", "explosion", "grenade_throw", "grenade_bounce",
	"hit", "armor_hit", "death", "fall_whoosh", "lava_sizzle", "spike_hit", "crate_break", "jump_pad",
	"spawn_pop", "low_time_tick",
]
const MUSIC: PackedStringArray = ["menu_loop", "battle_loop_a", "battle_loop_b", "battle_loop_c", "results_jingle"]


func _w(key: String) -> WeaponData:
	return load("res://data/weapons/%s.tres" % key)


func test_weapon_stats_match_prd() -> void:
	var p: WeaponData = _w("pistol")
	assert_eq([p.damage, p.fire_rate, p.ammo, p.weapon_range, p.spread_deg, p.knockback, p.spawn_weight],
			[18, 3.0, 12, 25.0, 2.0, 2.0, 25], "pistol")
	var s: WeaponData = _w("smg")
	assert_eq([s.damage, s.fire_rate, s.ammo, s.weapon_range, s.spread_deg, s.knockback, s.spawn_weight],
			[9, 10.0, 40, 18.0, 6.0, 1.0, 20], "smg")
	var sg: WeaponData = _w("shotgun")
	assert_eq([sg.damage, sg.pellets, sg.fire_rate, sg.ammo, sg.weapon_range, sg.spread_deg, sg.knockback, sg.spawn_weight],
			[9, 6, 1.2, 6, 10.0, 15.0, 8.0, 20], "shotgun")
	var sn: WeaponData = _w("sniper")
	assert_eq([sn.damage, sn.fire_rate, sn.ammo, sn.weapon_range, sn.spread_deg, sn.knockback, sn.spawn_weight],
			[70, 0.8, 4, 60.0, 0.0, 10.0, 12], "sniper")
	var r: WeaponData = _w("rocket_launcher")
	assert_eq([r.damage, r.splash_radius, r.splash_edge_damage, r.fire_rate, r.ammo, r.weapon_range, r.knockback,
			r.projectile_speed, r.projectile_lifetime, r.self_damage_factor, r.destroys_crates, r.spawn_weight],
			[60, 3.0, 20, 0.7, 3, 40.0, 14.0, 18.0, 3.0, 0.5, true, 8], "rocket")
	var g: WeaponData = _w("grenades")
	assert_eq([g.damage, g.splash_radius, g.splash_edge_damage, g.fire_rate, g.ammo, g.weapon_range, g.knockback,
			g.fuse_time, g.self_damage_factor, g.destroys_crates, g.spawn_weight],
			[70, 3.5, 15, 1.0, 3, 16.0, 12.0, 2.0, 0.5, true, 15], "grenades")
	var pu: WeaponData = _w("punch")
	assert_eq([pu.damage, pu.weapon_range, pu.knockback], [12, 1.2, 5.0], "punch")
	assert_near(pu.cooldown(), 0.45, 0.0001, "punch cooldown")


func test_item_values_match_prd() -> void:
	var h: ItemData = load("res://data/items/health_pack.tres")
	var a: ItemData = load("res://data/items/armor.tres")
	assert_eq([h.heal_amount, h.spawn_weight], [40, 60])
	assert_eq([a.armor_amount, a.spawn_weight], [50, 40])


func test_audio_assets_exist() -> void:
	for n: String in SFX:
		assert_true(ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % n), "missing sfx " + n)
	for m: String in MUSIC:
		assert_true(ResourceLoader.exists("res://assets/audio/music/%s.wav" % m), "missing music " + m)


func test_scenes_exist() -> void:
	for path: String in [
		"res://scenes/characters/stickman.tscn",
		"res://scenes/weapons/pistol.tscn", "res://scenes/weapons/smg.tscn", "res://scenes/weapons/shotgun.tscn",
		"res://scenes/weapons/sniper.tscn", "res://scenes/weapons/rocket_launcher.tscn",
		"res://scenes/weapons/grenade.tscn", "res://scenes/weapons/rocket_projectile.tscn",
		"res://scenes/weapons/grenade_projectile.tscn",
		"res://scenes/pickups/weapon_pickup.tscn", "res://scenes/pickups/health_pack.tscn",
		"res://scenes/pickups/armor.tscn",
		"res://scenes/hazards/lava.tscn", "res://scenes/hazards/spikes.tscn", "res://scenes/hazards/crate.tscn",
		"res://scenes/hazards/jump_pad.tscn", "res://scenes/hazards/moving_platform.tscn",
		"res://assets/blocks/mesh_library.tres", "res://ui/theme/block_brawl_theme.tres",
	]:
		assert_true(ResourceLoader.exists(path), "missing " + path)


func test_themes_exist_for_all_maps() -> void:
	for t: String in ["candy", "mint", "lava", "cloud", "crate", "spike", "bubblegum", "lilac", "peach", "sky", "garden", "sorbet"]:
		var th: MapTheme = load("res://data/themes/%s.tres" % t)
		assert_true(th != null and th.id == t, "theme " + t)
