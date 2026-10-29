class_name World
extends Node3D
## The playfield of one round: map, players, pickups, projectiles, effects,
## camera.
## `authority == true` (host or offline sandbox): runs the simulation
## (movement, combat, hazards, spawning) and emits events.
## `authority == false` (client): renders interpolated snapshots and applies
## events (see NetSnapshot / MatchManager).

signal player_died(victim: int, killer: int, cause: int)
signal event_emitted(ev: Array)
signal kill_feed(killer: int, victim: int, cause: int)

const ROCKET_SCENE: PackedScene = preload("res://scenes/weapons/rocket_projectile.tscn")
const GRENADE_SCENE: PackedScene = preload("res://scenes/weapons/grenade_projectile.tscn")
const WEAPON_PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/weapon_pickup.tscn")
const HEALTH_SCENE: PackedScene = preload("res://scenes/pickups/health_pack.tscn")
const ARMOR_SCENE: PackedScene = preload("res://scenes/pickups/armor.tscn")

const MASK_WORLD := 1
const MASK_PLAYERS := 2
const MUZZLE_FORWARD := 0.6
const MUZZLE_HEIGHT := 1.15
const THROW_UP_VELOCITY := 4.0  # TODO(PRD): "slight upward arc" has no value
const GRENADE_RESTITUTION := 0.5
const SPIKE_BOUNCE_VELOCITY := GameConfig.JUMP_VELOCITY  # TODO(PRD): spike bounce strength
const PICKUP_GRAVITY := GameConfig.GRAVITY

var authority: bool = true
var map: GameMap
var camera: CameraRig
var effects: Effects
var players: Dictionary = {}  # pid -> Player
var inputs: Dictionary = {}  # pid -> PlayerInput (latest received)
var pickups: Dictionary = {}  # id -> PickupState
var projectiles: Dictionary = {}  # id -> ProjectileState
var local_pid: int = -1
var frozen: bool = false  # countdown: players can't move or attack
var fighting: bool = true  # spawning active
var sim_time: float = 0.0
var fight_time: float = 0.0
var particle_factor: float = 1.0
var kill_credit := KillCredit.new()
var rng := RandomNumberGenerator.new()
var spawning_enabled: bool = true

var _players_root: Node3D
var _pickups_root: Node3D
var _projectiles_root: Node3D
var _next_entity_id: int = 1
var _weapon_spawn_t: float = 0.0
var _item_spawn_t: float = 0.0
var _items_started: bool = false
var _idle_input := PlayerInput.new()

# Client replication (§5.6): snapshot buffer rendered 100 ms in the past.
var last_snapshot: Dictionary = {}
var last_snapshot_bytes: int = 0
var local_ack: int = 0
var _snapshots: Array[Dictionary] = []
var _render_time: float = -1.0


func _ready() -> void:
	_players_root = _make_root("Players")
	_pickups_root = _make_root("Pickups")
	_projectiles_root = _make_root("Projectiles")
	effects = Effects.new()
	effects.name = "Effects"
	add_child(effects)
	camera = CameraRig.new()
	camera.name = "Camera"
	add_child(camera)
	particle_factor = Settings.particle_factor()
	effects.particle_factor = particle_factor
	effects.damage_numbers_enabled = Settings.hud_enabled("damage_numbers")
	rng.randomize()


func _make_root(n: String) -> Node3D:
	var r := Node3D.new()
	r.name = n
	add_child(r)
	return r


func load_map(map_id: String) -> bool:
	var md: MapData = GameMap.load_map(map_id)
	if not md.is_valid():
		push_error("Invalid map %s: %s" % [map_id, str(md.validate())])
		return false
	load_map_data(md)
	return true


## Builds the map from already parsed data (no validation; used by tests).
func load_map_data(md: MapData) -> void:
	map = GameMap.new()
	add_child(map)
	move_child(map, 0)
	map.build(md, Settings.background_decorations(), Settings.parallax_enabled(), particle_factor)
	camera.map_size = Vector2(map.width(), map.height())
	camera.set_sky(map.theme.bg_top, map.theme.bg_bottom)


# ================================================================ players
func add_player(pid: int, color_id: int, player_name: String, is_local: bool) -> Player:
	var p := Player.new()
	_players_root.add_child(p)
	p.setup(pid, color_id, player_name, is_local)
	p.landed.connect(_on_player_landed)
	p.jumped.connect(_on_player_jumped)
	p.stickman.death_finished.connect(_on_death_finished)
	players[pid] = p
	inputs[pid] = PlayerInput.new()
	# Not part of the round until placed on a spawn (or seen in a snapshot).
	p.alive = false
	p.visible = false
	p.collision_layer = 0
	if is_local:
		local_pid = pid
		camera.target = p
	elif not Settings.remote_blob_shadows():
		p.stickman.shadow_enabled = false
	if not authority:
		# Replicas are positioned from snapshots, not simulated.
		p.collision_layer = 0
		p.collision_mask = 0
	return p


func remove_player(pid: int) -> void:
	if players.has(pid):
		(players[pid] as Player).queue_free()
		players.erase(pid)
		inputs.erase(pid)


func get_player(pid: int) -> Player:
	return players.get(pid) as Player


func local_player() -> Player:
	return get_player(local_pid)


func set_input(pid: int, inp: PlayerInput) -> void:
	if inputs.has(pid):
		(inputs[pid] as PlayerInput).copy_from(inp)


func alive_players() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in players.values():
		if p.alive:
			out.append(p)
	return out


func alive_count() -> int:
	var n: int = 0
	for p: Player in players.values():
		if p.alive:
			n += 1
	return n


## Places every player on a distinct random spawn point (§7.5).
func place_players_at_spawns(pids: Array[int]) -> void:
	var spawns: Array[Vector3] = map.player_spawns.duplicate()
	for i: int in range(spawns.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector3 = spawns[i]
		spawns[i] = spawns[j]
		spawns[j] = tmp
	for i: int in range(pids.size()):
		var p: Player = get_player(pids[i])
		if p != null:
			p.reset_for_round(spawns[i % spawns.size()])
			p.facing = 1 if p.global_position.x < map.width() * 0.5 else -1


# ================================================================ simulation
func _physics_process(delta: float) -> void:
	if map == null:
		return
	if authority:
		_server_step(delta)


# ================================================================ client replication
func push_snapshot(s: Dictionary, size_bytes: int) -> void:
	if not _snapshots.is_empty() and float(s["t"]) <= float(_snapshots.back()["t"]):
		return  # duplicate or out of order
	_snapshots.append(s)
	while _snapshots.size() > 32:
		_snapshots.pop_front()
	last_snapshot = s
	last_snapshot_bytes = size_bytes
	if _render_time < 0.0:
		_render_time = float(s["t"]) - GameConfig.INTERP_DELAY
	_apply_discrete(s)


## Discrete state (HP, weapon, alive, ...) from the latest snapshot.
func _apply_discrete(s: Dictionary) -> void:
	var sp: Dictionary = s["players"]
	for pid: int in sp.keys():
		var p: Player = get_player(pid)
		if p == null:
			continue
		var d: Dictionary = sp[pid]
		var was_alive: bool = p.alive
		p.alive = bool(d["alive"])
		if p.alive and not was_alive:
			p.stickman.reset_pose()
		if not p.alive and was_alive:
			p.stickman.play(Stickman.Anim.DEATH)
		p.visible = p.alive or p.stickman.is_dead()
		p.hp = int(d["hp"])
		p.armor = int(d["armor"])
		p.weapon_id = int(d["weapon"])
		p.ammo = int(d["ammo"])
		if pid == local_pid:
			local_ack = int(d["ack"])
	var crates: Array[bool] = s["crates"]
	for i: int in range(mini(crates.size(), map.crates.size())):
		if not crates[i] and map.crates[i].alive:
			map.crates[i].break_crate()


func _client_step(delta: float) -> void:
	if _snapshots.is_empty():
		return
	var latest: float = float(_snapshots.back()["t"])
	var target: float = latest - GameConfig.INTERP_DELAY
	_render_time += delta
	if absf(_render_time - target) > 0.25:
		_render_time = target
	else:
		_render_time = lerpf(_render_time, target, 0.05)
	# Find the two snapshots around the render time.
	var a: Dictionary = _snapshots[0]
	var b: Dictionary = _snapshots[0]
	for i: int in range(_snapshots.size()):
		var sn: Dictionary = _snapshots[i]
		if float(sn["t"]) <= _render_time:
			a = sn
			b = sn
		else:
			b = sn
			break
	var ta: float = float(a["t"])
	var tb: float = float(b["t"])
	var alpha: float = 0.0 if tb <= ta else clampf((_render_time - ta) / (tb - ta), 0.0, 1.0)
	_interp_players(a, b, alpha)
	_interp_projectiles(a, b, alpha)
	_interp_pickups(a, b, alpha)
	var ma: Array[Vector2] = a["movers"]
	var mb: Array[Vector2] = b["movers"]
	for i: int in range(mini(map.movers.size(), mini(ma.size(), mb.size()))):
		var mp: Vector2 = ma[i].lerp(mb[i], alpha)
		map.movers[i].set_remote_position(Vector3(mp.x, mp.y, 0))


func _interp_players(a: Dictionary, b: Dictionary, alpha: float) -> void:
	var pa: Dictionary = a["players"]
	var pb: Dictionary = b["players"]
	for pid: int in pb.keys():
		var p: Player = get_player(pid)
		if p == null:
			continue
		var db: Dictionary = pb[pid]
		var pos: Vector2 = db["pos"]
		if pa.has(pid):
			pos = (pa[pid]["pos"] as Vector2).lerp(pos, alpha)
		p.global_position = Vector3(pos.x, pos.y, 0)
		var v: Vector2 = db["vel"]
		p.velocity = Vector3(v.x, v.y, 0)
		p.grounded = bool(db["grounded"])
		p.facing = int(db["facing"])
		p.aim_angle = float(db["aim"])


func _interp_projectiles(a: Dictionary, b: Dictionary, alpha: float) -> void:
	var pa: Dictionary = a["proj"]
	var pb: Dictionary = b["proj"]
	for id: int in projectiles.keys():
		if not pb.has(id):
			remove_projectile(projectiles[id])
	for id2: int in pb.keys():
		var d: Dictionary = pb[id2]
		var pr: ProjectileState = projectiles.get(id2) as ProjectileState
		if pr == null:
			pr = ProjectileState.new()
			pr.id = id2
			pr.type = int(d["type"])
			pr.weapon_id = int(d["weapon"])
			pr.node = _make_projectile_node(pr.type, pr.weapon_id)
			projectiles[id2] = pr
		var pos: Vector2 = d["pos"]
		if pa.has(id2):
			pos = (pa[id2]["pos"] as Vector2).lerp(pos, alpha)
		pr.pos = Vector3(pos.x, pos.y, 0)
		var v: Vector2 = d["vel"]
		pr.vel = Vector3(v.x, v.y, 0)
		pr.age += get_process_delta_time()
		_update_projectile_node(pr)


func _interp_pickups(a: Dictionary, b: Dictionary, alpha: float) -> void:
	var pa: Dictionary = a["pickups"]
	var pb: Dictionary = b["pickups"]
	for id: int in pickups.keys():
		if not pb.has(id):
			remove_pickup(pickups[id])
	for id2: int in pb.keys():
		var d: Dictionary = pb[id2]
		var pk: PickupState = pickups.get(id2) as PickupState
		if pk == null:
			pk = PickupState.new()
			pk.id = id2
			pk.kind = int(d["kind"])
			pk.weapon_id = int(d["weapon"])
			pk.node = make_pickup_node(pk.kind, pk.weapon_id)
			if bool(d["fresh"]):
				pk.node.pop()
			pickups[id2] = pk
		pk.ammo = int(d["ammo"])
		var pos: Vector2 = d["pos"]
		if pa.has(id2):
			pos = (pa[id2]["pos"] as Vector2).lerp(pos, alpha)
		pk.pos = Vector3(pos.x, pos.y, 0)
		pk.node.global_position = pk.pos
		pk.node.set_blink(bool(d["blink"]))


func _server_step(delta: float) -> void:
	sim_time += delta
	for m: MovingPlatform in map.movers:
		m.server_step(delta)
	for p: Player in players.values():
		if not p.alive:
			continue
		var inp: PlayerInput = inputs[p.pid]
		var edges: int = p.consume_edges(inp)
		if frozen:
			p.simulate_movement(_idle_input, false, delta, map)
		else:
			p.simulate_movement(inp, edges & Player.EDGE_JUMP != 0, delta, map)
		_check_hazards(p)
		if not p.alive:
			continue
		p.fire_cooldown = maxf(0.0, p.fire_cooldown - delta)
		if frozen:
			continue
		if edges & Player.EDGE_PICKUP != 0:
			try_pickup_weapon(p)
		if edges & Player.EDGE_THROW != 0:
			throw_weapon(p)
		if inp.attack_held and p.fire_cooldown <= 0.0:
			attack(p)
		_auto_pickup_items(p)
	_step_projectiles(delta)
	_step_pickups(delta)
	if fighting and not frozen:
		fight_time += delta
		if spawning_enabled:
			_step_spawning(delta)


# ================================================================ hazards
func _check_hazards(p: Player) -> void:
	var pos: Vector3 = p.global_position
	if pos.y < map.kill_line_y():
		kill_player(p, KillCredit.NONE, GameConfig.Cause.FALL)
		return
	var r: float = GameConfig.PLAYER_RADIUS
	var x0: float = pos.x - r
	var x1: float = pos.x + r
	var y0: float = pos.y + 0.02
	var y1: float = pos.y + GameConfig.PLAYER_HEIGHT
	if map.rect_touches("L", x0, y0, x1, y1, 0.84).x >= 0:
		emit_event([GameEvents.LAVA, p.pid])
		kill_player(p, KillCredit.NONE, GameConfig.Cause.LAVA)
		return
	if p.invuln_t <= 0.0 and map.rect_touches("^", x0, pos.y - 0.02, x1, y1, 0.55).x >= 0:
		p.invuln_t = GameConfig.SPIKE_INVULNERABILITY
		p.velocity.y = SPIKE_BOUNCE_VELOCITY
		p.grounded = false
		emit_event([GameEvents.SPIKE, p.pid])
		damage_player(p, GameConfig.SPIKE_DAMAGE, KillCredit.NONE, GameConfig.Cause.SPIKES, Vector3.ZERO, 0.0)
		if not p.alive:
			return
	var pad: Vector2i = map.rect_touches("J", x0, pos.y - 0.02, x1, y1, 0.45)
	if pad.x >= 0 and p.velocity.y <= 1.0:
		p.velocity.y = GameConfig.JUMP_PAD_VELOCITY
		p.grounded = false
		emit_event([GameEvents.JUMP_PAD, p.pid, map.data.cell_bottom(pad.x, pad.y)])


# ================================================================ damage
## Applies damage (armor first), records the attacker for kill credit,
## applies knockback and kills the player at 0 HP.
func damage_player(victim: Player, amount: int, attacker: int, cause: int, kb_dir: Vector3, knockback: float) -> void:
	if not victim.alive or amount <= 0:
		return
	var armor_hit: bool = victim.armor > 0
	var r: Vector2i = Rules.apply_damage(victim.hp, victim.armor, amount)
	victim.hp = r.x
	victim.armor = r.y
	kill_credit.record_damage(victim.pid, attacker, sim_time)
	victim.apply_knockback(kb_dir, knockback)
	emit_event([GameEvents.HIT, victim.pid, amount, armor_hit, victim.center(), attacker])
	if victim.hp <= 0:
		kill_player(victim, attacker, cause)


## Kills a player. `lethal_attacker` is the player who dealt the lethal
## damage (NONE for environmental deaths); credit follows §4.3.
func kill_player(p: Player, lethal_attacker: int, cause: int) -> void:
	if not p.alive:
		return
	p.alive = false
	p.hp = 0
	p.velocity = Vector3.ZERO
	p.collision_layer = 0
	if p.weapon_id != 0:  # TODO(PRD): held weapon on death is not specified; it disappears
		p.weapon_id = 0
		p.ammo = 0
	var credited: int = kill_credit.resolve(p.pid, lethal_attacker, sim_time)
	kill_credit.forget(p.pid)
	emit_event([GameEvents.DEATH, p.pid, credited, cause])
	player_died.emit(p.pid, credited, cause)


func damage_crate(crate: Crate, amount: int) -> void:
	if crate == null or not crate.alive:
		return
	if crate.apply_damage(amount):
		emit_event([GameEvents.CRATE_BROKEN, crate.index])


# ================================================================ combat
func muzzle_origin(p: Player) -> Vector3:
	return p.global_position + Vector3(MUZZLE_FORWARD * float(p.facing), MUZZLE_HEIGHT, 0)


func _ray(from: Vector3, to: Vector3, mask: int, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.hit_from_inside = false
	return get_world_3d().direct_space_state.intersect_ray(q)


## Line of sight against world geometry (blocks, crates, movers).
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	return _ray(from, to, MASK_WORLD, []).is_empty()


## Auto-aim target (§7.2): nearest living enemy within range with a clear
## line of sight; on equal distance prefer one in the facing direction.
func find_auto_aim_target(p: Player, weapon_range: float) -> Player:
	var origin: Vector3 = p.global_position + Vector3(0, MUZZLE_HEIGHT, 0)
	var best: Player = null
	var best_d: float = INF
	for o: Player in players.values():
		if o == p or not o.alive:
			continue
		var d: float = origin.distance_to(o.chest())
		if d > weapon_range:
			continue
		if not has_line_of_sight(origin, o.chest()):
			continue
		var in_front: bool = (o.global_position.x - p.global_position.x) * float(p.facing) >= 0.0
		if d < best_d - 0.01:
			best = o
			best_d = d
		elif absf(d - best_d) <= 0.01 and in_front:
			best = o
			best_d = d
	return best


## Attack with the held weapon, or punch when unarmed.
func attack(p: Player) -> void:
	if p.weapon_id == 0:
		punch(p)
	else:
		fire_weapon(p)


func punch(p: Player) -> void:
	var w: WeaponData = WeaponDB.weapon(WeaponDB.PUNCH_ID)
	p.fire_cooldown = w.cooldown()
	# TODO(PRD): reach measured from the attacker centre to the target capsule edge.
	var reach: float = w.weapon_range + GameConfig.PLAYER_RADIUS
	var best: Player = null
	var best_dx: float = INF
	for o: Player in players.values():
		if o == p or not o.alive:
			continue
		var dx: float = (o.global_position.x - p.global_position.x) * float(p.facing)
		var dy: float = absf(o.chest().y - p.chest().y)
		if dx >= -0.1 and dx <= reach and dy < 1.0 and dx < best_dx:
			best = o
			best_dx = dx
	var hit: bool = false
	if best != null:
		damage_player(best, w.damage, p.pid, GameConfig.Cause.PUNCH, Vector3(float(p.facing), 0, 0), w.knockback)
		hit = true
	else:
		for c: Crate in map.crates:
			if not c.alive:
				continue
			var cdx: float = (c.global_position.x - p.global_position.x) * float(p.facing)
			var cdy: float = absf(c.global_position.y + 0.5 - p.chest().y)
			if cdx >= 0.0 and cdx <= w.weapon_range + 0.5 and cdy < 1.0:
				damage_crate(c, w.damage)
				hit = true
				break
	emit_event([GameEvents.PUNCH, p.pid, hit])


func fire_weapon(p: Player) -> void:
	var w: WeaponData = WeaponDB.weapon(p.weapon_id)
	if w == null:
		return
	p.fire_cooldown = w.cooldown()
	var origin: Vector3 = p.global_position + Vector3(0, MUZZLE_HEIGHT, 0)
	var target: Player = find_auto_aim_target(p, w.weapon_range)
	var dir := Vector3(float(p.facing), 0, 0)
	if target != null:
		var dx: float = target.global_position.x - p.global_position.x
		if absf(dx) > 0.01:
			p.facing = 1 if dx > 0.0 else -1
		dir = (target.chest() - origin).normalized()
	p.aim_angle = atan2(dir.y, absf(dir.x))
	var muzzle: Vector3 = muzzle_origin(p)
	match w.kind:
		WeaponData.Kind.HITSCAN:
			_fire_hitscan(p, w, origin, muzzle, dir)
		WeaponData.Kind.PROJECTILE:
			spawn_projectile(ProjectileState.Type.ROCKET, p.pid, muzzle, dir * w.projectile_speed, w.id, 0)
			emit_event([GameEvents.SHOT, p.pid, w.id, muzzle, PackedVector3Array()])
		WeaponData.Kind.THROWN_PROJECTILE:
			var vel: Vector3
			if target != null:
				vel = ballistic_velocity(muzzle, target.global_position + Vector3(0, 0.3, 0), GameConfig.GRAVITY)
			else:
				vel = Vector3(10.0 * float(p.facing), 8.0, 0)  # TODO(PRD): grenade throw without target
			spawn_projectile(ProjectileState.Type.GRENADE, p.pid, muzzle, vel, w.id, 0)
			emit_event([GameEvents.SHOT, p.pid, w.id, muzzle, PackedVector3Array()])
	p.ammo -= 1
	if p.ammo <= 0:
		p.weapon_id = 0
		p.ammo = 0
		emit_event([GameEvents.WEAPON_EMPTY, p.pid, muzzle])


func _fire_hitscan(p: Player, w: WeaponData, origin: Vector3, muzzle: Vector3, dir: Vector3) -> void:
	var ends := PackedVector3Array()
	var hit_players: Dictionary = {}
	var exclude: Array[RID] = [p.get_rid()]
	var cause: int = w.id
	# TODO(PRD): spread read as the full cone angle (±spread/2 per shot/pellet).
	for i: int in range(maxi(1, w.pellets)):
		var angle: float = deg_to_rad(rng.randf_range(-w.spread_deg * 0.5, w.spread_deg * 0.5))
		var d: Vector3 = dir.rotated(Vector3(0, 0, 1), angle)
		var to: Vector3 = origin + d * w.weapon_range
		var hit: Dictionary = _ray(origin, to, MASK_WORLD | MASK_PLAYERS, exclude)
		if hit.is_empty():
			ends.append(to)
			continue
		var hp: Vector3 = hit["position"]
		ends.append(hp)
		var col: Object = hit["collider"]
		if col is Player:
			var victim: Player = col
			if w.pellets > 1:
				# Shotgun: damage per pellet, knockback once (total) per hit player.
				var first: bool = not hit_players.has(victim.pid)
				hit_players[victim.pid] = true
				damage_player(victim, w.damage, p.pid, cause, d, w.knockback if first else 0.0)
			else:
				damage_player(victim, w.damage, p.pid, cause, d, w.knockback)
		elif col is Crate:
			damage_crate(col as Crate, w.damage)
	emit_event([GameEvents.SHOT, p.pid, w.id, muzzle, ends])


## Initial velocity for an arc from `from` to `to` under gravity `g`
## (flight time scales with distance).
static func ballistic_velocity(from: Vector3, to: Vector3, g: float) -> Vector3:
	var dx: float = to.x - from.x
	var dy: float = to.y - from.y
	var t: float = clampf(absf(dx) / 11.0, 0.45, 1.1)
	return Vector3(dx / t, (dy + 0.5 * g * t * t) / t, 0)


func explode(pos: Vector3, owner_pid: int, w: WeaponData, direct_victim: Player) -> void:
	emit_event([GameEvents.EXPLOSION, pos, w.splash_radius])
	var cause: int = w.id
	for o: Player in players.values():
		if not o.alive:
			continue
		var c: Vector3 = o.center()
		# Distance to the closest point of the player's body segment.
		var seg_y: float = clampf(pos.y, o.global_position.y + 0.3, o.global_position.y + 1.5)
		var closest := Vector3(o.global_position.x, seg_y, 0)
		var dist: float = maxf(0.0, pos.distance_to(closest) - GameConfig.PLAYER_RADIUS)
		var dmg: int = 0
		if o == direct_victim:
			dmg = w.damage
		elif dist <= w.splash_radius:
			dmg = Rules.falloff_damage(dist, w.splash_radius, float(w.damage), float(w.splash_edge_damage))
		if dmg <= 0:
			continue
		if o.pid == owner_pid:
			dmg = int(round(float(dmg) * w.self_damage_factor))
		# TODO(PRD): full weapon knockback for every damaged player (not distance scaled).
		var kb_dir: Vector3 = (c - pos)
		if kb_dir.length() < 0.05:
			kb_dir = Vector3(0, 1, 0)
		damage_player(o, dmg, owner_pid, cause, kb_dir.normalized(), w.knockback)
	if w.destroys_crates:
		for cr: Crate in map.crates:
			if cr.alive and (cr.global_position + Vector3(0, 0.5, 0)).distance_to(pos) <= w.splash_radius + 0.5:
				cr.break_crate()
				emit_event([GameEvents.CRATE_BROKEN, cr.index])


# ================================================================ projectiles
func spawn_projectile(type: int, owner_pid: int, pos: Vector3, vel: Vector3, weapon_id: int, ammo: int) -> ProjectileState:
	var pr := ProjectileState.new()
	pr.id = _next_entity_id
	_next_entity_id += 1
	pr.type = type
	pr.owner = owner_pid
	pr.pos = pos
	pr.vel = vel
	pr.weapon_id = weapon_id
	pr.ammo = ammo
	projectiles[pr.id] = pr
	pr.node = _make_projectile_node(type, weapon_id)
	_update_projectile_node(pr)
	return pr


func _make_projectile_node(type: int, weapon_id: int) -> Node3D:
	var n: Node3D
	match type:
		ProjectileState.Type.ROCKET:
			n = ROCKET_SCENE.instantiate()
		ProjectileState.Type.GRENADE:
			n = GRENADE_SCENE.instantiate()
		_:
			var holder := Node3D.new()
			if Stickman.WEAPON_SCENES.has(weapon_id):
				var scene: PackedScene = load(Stickman.WEAPON_SCENES[weapon_id])
				holder.add_child(scene.instantiate())
			n = holder
	_projectiles_root.add_child(n)
	return n


func _update_projectile_node(pr: ProjectileState) -> void:
	if pr.node == null:
		return
	pr.node.global_position = pr.pos
	if pr.type == ProjectileState.Type.ROCKET:
		pr.node.rotation = Vector3(0, 0, atan2(pr.vel.y, pr.vel.x))
	else:
		pr.node.rotation = Vector3(0, 0, pr.age * -10.0 * signf(pr.vel.x if pr.vel.x != 0.0 else 1.0))


func remove_projectile(pr: ProjectileState) -> void:
	if pr.node != null:
		pr.node.queue_free()
		pr.node = null
	projectiles.erase(pr.id)


func _step_projectiles(delta: float) -> void:
	for pr: ProjectileState in projectiles.values():
		pr.age += delta
		pr.bounce_cooldown = maxf(0.0, pr.bounce_cooldown - delta)
		match pr.type:
			ProjectileState.Type.ROCKET:
				_step_rocket(pr, delta)
			ProjectileState.Type.GRENADE:
				_step_grenade(pr, delta)
			ProjectileState.Type.THROWN:
				_step_thrown(pr, delta)
		if projectiles.has(pr.id):
			if pr.pos.y < map.kill_line_y():
				remove_projectile(pr)
			else:
				_update_projectile_node(pr)


func _owner_exclude(pr: ProjectileState) -> Array[RID]:
	var ex: Array[RID] = []
	var owner_player: Player = get_player(pr.owner)
	if owner_player != null:
		ex.append(owner_player.get_rid())
	return ex


func _step_rocket(pr: ProjectileState, delta: float) -> void:
	var w: WeaponData = WeaponDB.weapon(GameConfig.WeaponId.ROCKET)
	var next: Vector3 = pr.pos + pr.vel * delta
	var hit: Dictionary = _ray(pr.pos, next, MASK_WORLD | MASK_PLAYERS, _owner_exclude(pr))
	if not hit.is_empty():
		var col: Object = hit["collider"]
		var direct: Player = col as Player
		var hp: Vector3 = hit["position"]
		remove_projectile(pr)
		explode(hp, pr.owner, w, direct)
		return
	pr.pos = next
	if pr.age >= w.projectile_lifetime:
		remove_projectile(pr)
		explode(pr.pos, pr.owner, w, null)


func _step_grenade(pr: ProjectileState, delta: float) -> void:
	var w: WeaponData = WeaponDB.weapon(GameConfig.WeaponId.GRENADE)
	pr.vel.y = maxf(pr.vel.y - GameConfig.GRAVITY * delta, -GameConfig.MAX_FALL_SPEED)
	var next: Vector3 = pr.pos + pr.vel * delta
	var hit: Dictionary = _ray(pr.pos, next, MASK_WORLD, [])
	if not hit.is_empty():
		var n: Vector3 = hit["normal"]
		pr.pos = (hit["position"] as Vector3) + n * 0.12
		pr.vel = pr.vel.bounce(n) * GRENADE_RESTITUTION
		if pr.bounce_cooldown <= 0.0 and pr.vel.length() > 1.5:
			pr.bounce_cooldown = 0.15
			emit_event([GameEvents.BOUNCE, pr.pos])
	else:
		pr.pos = next
	pr.pos.z = 0.0
	if pr.age >= w.fuse_time:
		remove_projectile(pr)
		explode(pr.pos, pr.owner, w, null)


func _step_thrown(pr: ProjectileState, delta: float) -> void:
	pr.vel.y = maxf(pr.vel.y - GameConfig.GRAVITY * delta, -GameConfig.MAX_FALL_SPEED)
	var next: Vector3 = pr.pos + pr.vel * delta
	var hit: Dictionary = _ray(pr.pos, next, MASK_WORLD | MASK_PLAYERS, _owner_exclude(pr))
	if hit.is_empty():
		pr.pos = next
		return
	var hp: Vector3 = hit["position"]
	var col: Object = hit["collider"]
	if col is Player:
		var victim: Player = col
		var dir := Vector3(signf(pr.vel.x), 0, 0)
		damage_player(victim, GameConfig.THROW_DAMAGE, pr.owner, GameConfig.Cause.THROWN, dir, GameConfig.THROW_KNOCKBACK)
		emit_event([GameEvents.THROWN_HIT, hp])
	elif col is Crate:
		damage_crate(col as Crate, GameConfig.THROW_DAMAGE)
	# The weapon falls to the ground as a normal pickup, keeping its ammo.
	var drop_pos: Vector3 = hp - pr.vel.normalized() * 0.3
	drop_pos.y -= 0.45
	remove_projectile(pr)
	spawn_pickup(PickupState.Kind.WEAPON, pr.weapon_id, pr.ammo, Vector3(drop_pos.x, drop_pos.y, 0), false)


# ================================================================ pickups
func spawn_pickup(kind: int, weapon_id: int, ammo: int, pos: Vector3, pop: bool) -> PickupState:
	var pk := PickupState.new()
	pk.id = _next_entity_id
	_next_entity_id += 1
	pk.kind = kind
	pk.weapon_id = weapon_id
	pk.ammo = ammo
	pk.pos = pos
	pk.resting = false
	pickups[pk.id] = pk
	pk.node = make_pickup_node(kind, weapon_id)
	pk.node.global_position = pos
	if pop:
		pk.node.pop()
		emit_event([GameEvents.PICKUP_SPAWN, pk.id, pos])
	return pk


func make_pickup_node(kind: int, weapon_id: int) -> PickupView:
	var n: PickupView
	match kind:
		PickupState.Kind.HEALTH:
			n = HEALTH_SCENE.instantiate()
		PickupState.Kind.ARMOR:
			n = ARMOR_SCENE.instantiate()
		_:
			n = WEAPON_PICKUP_SCENE.instantiate()
	_pickups_root.add_child(n)
	if kind == PickupState.Kind.WEAPON:
		n.set_weapon(weapon_id)
	return n


func remove_pickup(pk: PickupState) -> void:
	if pk.node != null:
		pk.node.queue_free()
		pk.node = null
	pickups.erase(pk.id)


## Overlap test between a pickup (radius 1.0) and a player's body.
func overlaps_pickup(p: Player, pk: PickupState) -> bool:
	var c: Vector3 = pk.center()
	var seg_y: float = clampf(c.y, p.global_position.y + 0.3, p.global_position.y + 1.5)
	var closest := Vector3(p.global_position.x, seg_y, 0)
	return c.distance_to(closest) <= GameConfig.PICKUP_RADIUS


func nearest_weapon_pickup(p: Player) -> PickupState:
	var best: PickupState = null
	var best_d: float = INF
	for pk: PickupState in pickups.values():
		if not pk.is_weapon() or not overlaps_pickup(p, pk):
			continue
		var d: float = pk.center().distance_to(p.center())
		if d < best_d:
			best = pk
			best_d = d
	return best


## Pick Up button (§7.1): takes the overlapping weapon; a held weapon is
## dropped at the player's position with its remaining ammo.
func try_pickup_weapon(p: Player) -> bool:
	var pk: PickupState = nearest_weapon_pickup(p)
	if pk == null:
		return false
	if p.weapon_id != 0:
		spawn_pickup(PickupState.Kind.WEAPON, p.weapon_id, p.ammo, p.global_position, false)
	p.weapon_id = pk.weapon_id
	p.ammo = pk.ammo
	p.fire_cooldown = 0.0
	emit_event([GameEvents.PICKUP_TAKEN, pk.id, p.pid, pk.kind, pk.weapon_id])
	remove_pickup(pk)
	return true


## Throw button (§7.1): throws the held weapon in the facing direction.
func throw_weapon(p: Player) -> bool:
	if p.weapon_id == 0:
		return false
	var pos: Vector3 = muzzle_origin(p)
	var vel := Vector3(GameConfig.THROW_SPEED * float(p.facing), THROW_UP_VELOCITY, 0)
	spawn_projectile(ProjectileState.Type.THROWN, p.pid, pos, vel, p.weapon_id, p.ammo)
	p.weapon_id = 0
	p.ammo = 0
	emit_event([GameEvents.THROW, p.pid])
	return true


## Items are picked up automatically on touch (§7.4).
## TODO(PRD): also picked up when HP/armor is already full.
func _auto_pickup_items(p: Player) -> void:
	for pk: PickupState in pickups.values():
		if pk.is_weapon() or not overlaps_pickup(p, pk):
			continue
		if pk.kind == PickupState.Kind.HEALTH:
			p.hp = Rules.heal(p.hp, WeaponDB.item(GameConfig.ItemId.HEALTH).heal_amount)
		else:
			p.armor = Rules.add_armor(p.armor, WeaponDB.item(GameConfig.ItemId.ARMOR).armor_amount)
		emit_event([GameEvents.PICKUP_TAKEN, pk.id, p.pid, pk.kind, 0])
		remove_pickup(pk)


func _step_pickups(delta: float) -> void:
	for pk: PickupState in pickups.values():
		pk.age += delta
		if pk.is_weapon() and pk.age >= GameConfig.GROUND_WEAPON_DESPAWN:
			emit_event([GameEvents.DESPAWN, pk.id, pk.pos])
			remove_pickup(pk)
			continue
		if not pk.resting:
			_fall_pickup(pk, delta)
			if pk.pos.y < map.kill_line_y():
				remove_pickup(pk)
				continue
		if pk.node != null:
			pk.node.global_position = pk.pos
			pk.node.set_blink(pk.blinking())


func _fall_pickup(pk: PickupState, delta: float) -> void:
	pk.vel_y = maxf(pk.vel_y - PICKUP_GRAVITY * delta, -GameConfig.MAX_FALL_SPEED)
	var next_y: float = pk.pos.y + pk.vel_y * delta
	var from := Vector3(pk.pos.x, pk.pos.y + 0.3, 0)
	var hit: Dictionary = _ray(from, Vector3(pk.pos.x, next_y, 0), MASK_WORLD, [])
	if not hit.is_empty():
		pk.pos.y = (hit["position"] as Vector3).y
		pk.vel_y = 0.0
		pk.resting = true
		return
	var top: float = map.one_way_top_crossed(pk.pos.x - 0.2, pk.pos.x + 0.2, pk.pos.y, next_y)
	if not is_nan(top):
		pk.pos.y = top
		pk.vel_y = 0.0
		pk.resting = true
		return
	pk.pos.y = next_y


func weapon_pickup_count() -> int:
	var n: int = 0
	for pk: PickupState in pickups.values():
		if pk.is_weapon():
			n += 1
	return n


func item_pickup_count() -> int:
	return pickups.size() - weapon_pickup_count()


## A spawn point is free if no pickup is within 1.5 m (§7.5).
func is_point_free(point: Vector3) -> bool:
	for pk: PickupState in pickups.values():
		if pk.pos.distance_to(point) < GameConfig.PICKUP_FREE_RADIUS:
			return false
	return true


func _random_free_point(points: Array[Vector3]) -> Variant:
	var free: Array[Vector3] = []
	for pt: Vector3 in points:
		if is_point_free(pt):
			free.append(pt)
	if free.is_empty():
		return null
	return free[rng.randi_range(0, free.size() - 1)]


func spawn_random_weapon() -> bool:
	var pt: Variant = _random_free_point(map.weapon_spawns)
	if pt == null:
		return false
	var wid: int = int(Rules.weighted_pick(WeaponDB.weapon_weights(), rng))
	spawn_pickup(PickupState.Kind.WEAPON, wid, WeaponDB.weapon(wid).ammo, pt, true)
	return true


func spawn_random_item() -> bool:
	var pt: Variant = _random_free_point(map.item_spawns)
	if pt == null:
		return false
	var iid: int = int(Rules.weighted_pick(WeaponDB.item_weights(), rng))
	var kind: int = PickupState.Kind.HEALTH if iid == GameConfig.ItemId.HEALTH else PickupState.Kind.ARMOR
	spawn_pickup(kind, 0, 0, pt, true)
	return true


## Called when the countdown ends (§7.5): 3 weapons immediately.
func start_fight() -> void:
	frozen = false
	fighting = true
	fight_time = 0.0
	_weapon_spawn_t = 0.0
	_item_spawn_t = 0.0
	_items_started = false
	if authority and spawning_enabled:
		for i: int in range(GameConfig.START_WEAPONS):
			spawn_random_weapon()


## Every 8 s one weapon if < 6 on the ground; items first at 30 s, then
## every 20 s if < 2 on the ground (§7.5).
func _step_spawning(delta: float) -> void:
	_weapon_spawn_t += delta
	if _weapon_spawn_t >= GameConfig.WEAPON_SPAWN_INTERVAL:
		_weapon_spawn_t -= GameConfig.WEAPON_SPAWN_INTERVAL
		if weapon_pickup_count() < GameConfig.MAX_GROUND_WEAPONS:
			spawn_random_weapon()
	_item_spawn_t += delta
	var interval: float = GameConfig.ITEM_SPAWN_INTERVAL if _items_started else GameConfig.FIRST_ITEM_TIME
	if _item_spawn_t >= interval:
		_item_spawn_t -= interval
		_items_started = true
		if item_pickup_count() < GameConfig.MAX_GROUND_ITEMS:
			spawn_random_item()


# ================================================================ events
## Authority: applies an event locally and forwards it to clients.
func emit_event(ev: Array) -> void:
	apply_event(ev)
	event_emitted.emit(ev)


## Visual/audio side of events (host and clients).
func apply_event(ev: Array) -> void:
	var type: int = ev[0]
	match type:
		GameEvents.SHOT:
			_fx_shot(int(ev[1]), int(ev[2]), ev[3], ev[4])
		GameEvents.PUNCH:
			var pp: Player = get_player(int(ev[1]))
			if pp != null:
				pp.stickman.play(Stickman.Anim.PUNCH)
				AudioManager.play_at("punch_hit" if bool(ev[2]) else "punch_swing", pp.chest())
		GameEvents.HIT:
			_fx_hit(int(ev[1]), int(ev[2]), bool(ev[3]), ev[4])
		GameEvents.DEATH:
			_fx_death(int(ev[1]), int(ev[3]))
			kill_feed.emit(int(ev[2]), int(ev[1]), int(ev[3]))
		GameEvents.PICKUP_SPAWN:
			effects.burst(ev[2] as Vector3 + Vector3(0, 0.5, 0), Palette.WHITE, 10, 4.0, 0.8, 0.4, -6.0)
			AudioManager.play_at("spawn_pop", ev[2])
		GameEvents.PICKUP_TAKEN:
			_fx_pickup_taken(int(ev[2]), int(ev[3]))
		GameEvents.WEAPON_EMPTY:
			effects.burst(ev[2], Color("#D8D4E4"), 10, 3.0, 0.8, 0.4, -4.0)
			AudioManager.play_at("weapon_empty", ev[2])
		GameEvents.THROW:
			var tp: Player = get_player(int(ev[1]))
			if tp != null:
				tp.stickman.play(Stickman.Anim.THROW)
				AudioManager.play_at("throw", tp.chest())
		GameEvents.EXPLOSION:
			_fx_explosion(ev[1], float(ev[2]))
		GameEvents.CRATE_BROKEN:
			_fx_crate(int(ev[1]))
		GameEvents.JUMP_PAD:
			var jp: Vector3 = ev[2]
			effects.burst(jp + Vector3(0, 0.4, 0), Palette.GOLD, 12, 5.0, 0.8, 0.4, -10.0, 40.0)
			AudioManager.play_at("jump_pad", jp)
			var cell: Vector2i = map.data.world_to_cell(jp.x, jp.y + 0.1)
			if map.jump_pads.has(cell):
				(map.jump_pads[cell] as JumpPad).launch()
		GameEvents.JUMP:
			var jpl: Player = get_player(int(ev[1]))
			if jpl != null:
				if bool(ev[2]):
					jpl.stickman.play(Stickman.Anim.DOUBLE_JUMP)
				AudioManager.play_at("double_jump" if bool(ev[2]) else "jump", jpl.global_position, 1.0, -4.0)
		GameEvents.LAND:
			var lp: Player = get_player(int(ev[1]))
			if lp != null:
				lp.stickman.play(Stickman.Anim.LAND)
				effects.burst(lp.global_position + Vector3(0, 0.1, 0), Palette.WHITE, 6, 2.5, 0.6, 0.3, -6.0, 70.0)
				AudioManager.play_at("land", lp.global_position, 1.0, -8.0)
		GameEvents.SPIKE:
			var sp: Player = get_player(int(ev[1]))
			if sp != null:
				AudioManager.play_at("spike_hit", sp.global_position)
		GameEvents.LAVA:
			var lv: Player = get_player(int(ev[1]))
			if lv != null:
				effects.burst(lv.global_position + Vector3(0, 0.3, 0), map.theme.lava, 14, 5.0, 1.0, 0.6)
				AudioManager.play_at("lava_sizzle", lv.global_position)
		GameEvents.BOUNCE:
			AudioManager.play_at("grenade_bounce", ev[1], 1.0, -4.0)
		GameEvents.THROWN_HIT:
			effects.burst(ev[1], Palette.WHITE, 8, 3.0, 0.8, 0.3)
			AudioManager.play_at("thrown_hit", ev[1])
		GameEvents.DESPAWN:
			effects.burst(ev[2] as Vector3 + Vector3(0, 0.45, 0), Color("#D8D4E4"), 8, 2.5, 0.7, 0.4, -3.0)


func _fx_shot(pid: int, weapon_id: int, origin: Vector3, ends: PackedVector3Array) -> void:
	var p: Player = get_player(pid)
	var w: WeaponData = WeaponDB.weapon(weapon_id)
	var from: Vector3 = origin
	if p != null:
		p.stickman.set_weapon(weapon_id)
		p.stickman.play(Stickman.Anim.SHOOT, w.recoil if w != null else 0.3)
		if ends.size() > 0 and p.alive:
			var dir: Vector3 = (ends[0] - origin)
			p.facing = 1 if dir.x >= 0.0 else -1
			p.aim_angle = atan2(dir.y, absf(dir.x))
			p.stickman.set_facing(p.facing)
			p.stickman.set_aim(p.aim_angle)
	for e: Vector3 in ends:
		effects.tracer(from, e)
	effects.burst(from, Palette.GOLD, 3, 2.0, 0.7, 0.05, 0.0)
	if w != null:
		AudioManager.play_at(w.sfx, from)
		if w.shake > 0.0:
			_shake_at(from, w.shake, 0.12)


func _fx_hit(pid: int, amount: int, armor_hit: bool, pos: Vector3) -> void:
	var p: Player = get_player(pid)
	if p == null:
		return
	p.stickman.play(Stickman.Anim.HIT)
	effects.burst(pos, Palette.ARMOR if armor_hit else p.stickman.get_color(), 8, 4.0, 0.7, 0.4)
	effects.damage_number(pos + Vector3(0, 1.1, 0), amount, Palette.ARMOR if armor_hit else Palette.WHITE)
	AudioManager.play_at("armor_hit" if armor_hit else "hit", pos)
	if pid == local_pid:
		AudioManager.vibrate(40)


func _fx_death(pid: int, cause: int) -> void:
	var p: Player = get_player(pid)
	if p == null:
		return
	p.alive = false
	p.stickman.play(Stickman.Anim.DEATH)
	AudioManager.play_at("fall_whoosh" if cause == GameConfig.Cause.FALL else "death", p.center())


func _on_death_finished(pos: Vector3, color: Color) -> void:
	effects.burst(pos, color, 16, 5.0, 1.0, 0.7)


func _fx_pickup_taken(pid: int, kind: int) -> void:
	var p: Player = get_player(pid)
	if p == null:
		return
	var sfx: String = "pickup_weapon"
	if kind == PickupState.Kind.HEALTH:
		sfx = "pickup_health"
	elif kind == PickupState.Kind.ARMOR:
		sfx = "pickup_armor"
	effects.burst(p.center(), Palette.GOLD if kind == PickupState.Kind.WEAPON else Palette.WHITE, 8, 3.0, 0.6, 0.4, -2.0)
	AudioManager.play_at(sfx, p.center())


func _fx_explosion(pos: Vector3, radius: float) -> void:
	effects.burst(pos, Color("#FFD9A8"), 24, radius * 3.0, 1.6, 0.6, -6.0)
	effects.burst(pos, Color("#FFB3C8"), 12, radius * 2.0, 1.2, 0.5, -6.0)
	effects.ring(pos, Palette.WHITE, radius, 18)
	AudioManager.play_at("explosion", pos)
	_shake_at(pos, 0.3, 0.25)


func _fx_crate(index: int) -> void:
	if index < 0 or index >= map.crates.size():
		return
	var c: Crate = map.crates[index]
	if c.alive:
		c.break_crate()
	effects.burst(c.global_position + Vector3(0, 0.5, 0), Color("#E8BE8A"), 14, 4.5, 1.0, 0.6)
	AudioManager.play_at("crate_break", c.global_position)


## Screen shake on the local camera, scaled by distance (§10.4).
func _shake_at(pos: Vector3, amplitude: float, duration: float) -> void:
	var focus: Vector3 = camera.target.global_position if camera.target != null else pos
	var d: float = focus.distance_to(pos)
	var k: float = clampf(1.0 - d / 25.0, 0.0, 1.0)
	if k > 0.0:
		camera.shake(amplitude * k, duration)


func _process(delta: float) -> void:
	if not authority and map != null:
		_client_step(delta)
	for p: Player in players.values():
		p.update_visuals(delta)


func _on_player_landed(p: Player) -> void:
	if authority:
		emit_event([GameEvents.LAND, p.pid])


func _on_player_jumped(p: Player, double: bool) -> void:
	if authority:
		emit_event([GameEvents.JUMP, p.pid, double])
