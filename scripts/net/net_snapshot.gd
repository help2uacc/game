class_name NetSnapshot
extends RefCounted
## Packed world state host -> clients at 30 Hz (PRD §5.6): per player
## position, velocity, facing, HP, armor, weapon id, ammo, animation state
## (grounded/aim), alive flag and input ack; plus projectiles, pickups,
## moving platforms and crates. 8 players ≈ 0.6 KB (budget 2 KB, §12).
## TODO(PRD): used instead of MultiplayerSynchronizer/Spawner ("equivalent packed RPC"); clients
## create entity visuals from the snapshot lists.

const P_ALIVE := 1
const P_FACING_RIGHT := 2
const P_GROUNDED := 4
const PK_BLINK := 1
const PK_FRESH := 2


static func pack(world: World, acks: Dictionary, tick: int, time_left: float) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(tick)
	b.put_float(world.sim_time)
	b.put_float(time_left)
	b.put_u8(world.players.size())
	for p: Player in world.players.values():
		b.put_u8(p.pid)
		var flags: int = 0
		if p.alive:
			flags |= P_ALIVE
		if p.facing > 0:
			flags |= P_FACING_RIGHT
		if p.grounded:
			flags |= P_GROUNDED
		b.put_u8(flags)
		b.put_float(p.global_position.x)
		b.put_float(p.global_position.y)
		b.put_half(p.velocity.x)
		b.put_half(p.velocity.y)
		b.put_u8(clampi(p.hp, 0, 255))
		b.put_u8(clampi(p.armor, 0, 255))
		b.put_u8(p.weapon_id)
		b.put_u8(clampi(p.ammo, 0, 255))
		b.put_8(clampi(int(round(p.aim_angle * 40.0)), -127, 127))
		b.put_u32(int(acks.get(p.pid, 0)))
	b.put_u8(mini(world.projectiles.size(), 255))
	for pr: ProjectileState in world.projectiles.values():
		b.put_u16(pr.id & 0xFFFF)
		b.put_u8(pr.type)
		b.put_u8(pr.weapon_id)
		b.put_float(pr.pos.x)
		b.put_float(pr.pos.y)
		b.put_half(pr.vel.x)
		b.put_half(pr.vel.y)
	b.put_u8(mini(world.pickups.size(), 255))
	for pk: PickupState in world.pickups.values():
		b.put_u16(pk.id & 0xFFFF)
		b.put_u8(pk.kind)
		b.put_u8(pk.weapon_id)
		b.put_u8(clampi(pk.ammo, 0, 255))
		var pf: int = 0
		if pk.blinking():
			pf |= PK_BLINK
		if pk.age < GameConfig.SPAWN_POP_TIME:
			pf |= PK_FRESH
		b.put_u8(pf)
		b.put_float(pk.pos.x)
		b.put_float(pk.pos.y)
	var movers: Array[MovingPlatform] = world.map.movers
	b.put_u8(movers.size())
	for m: MovingPlatform in movers:
		b.put_float(m.position.x)
		b.put_float(m.position.y)
	var crates: Array[Crate] = world.map.crates
	b.put_u16(crates.size())
	var byte: int = 0
	for i: int in range(crates.size()):
		if crates[i].alive:
			byte |= 1 << (i % 8)
		if i % 8 == 7 or i == crates.size() - 1:
			b.put_u8(byte)
			byte = 0
	return b.data_array


static func unpack(data: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var s: Dictionary = {}
	s["tick"] = b.get_u32()
	s["t"] = b.get_float()
	s["time_left"] = b.get_float()
	var players: Dictionary = {}
	var n: int = b.get_u8()
	for i: int in range(n):
		var pid: int = b.get_u8()
		var flags: int = b.get_u8()
		var pos := Vector2(b.get_float(), b.get_float())
		var vel := Vector2(b.get_half(), b.get_half())
		players[pid] = {
			"alive": flags & P_ALIVE != 0,
			"facing": 1 if flags & P_FACING_RIGHT != 0 else -1,
			"grounded": flags & P_GROUNDED != 0,
			"pos": pos,
			"vel": vel,
			"hp": b.get_u8(),
			"armor": b.get_u8(),
			"weapon": b.get_u8(),
			"ammo": b.get_u8(),
			"aim": float(b.get_8()) / 40.0,
			"ack": b.get_u32(),
		}
	s["players"] = players
	var proj: Dictionary = {}
	n = b.get_u8()
	for i: int in range(n):
		var id: int = b.get_u16()
		proj[id] = {
			"type": b.get_u8(),
			"weapon": b.get_u8(),
			"pos": Vector2(b.get_float(), b.get_float()),
			"vel": Vector2(b.get_half(), b.get_half()),
		}
	s["proj"] = proj
	var pickups: Dictionary = {}
	n = b.get_u8()
	for i: int in range(n):
		var pid2: int = b.get_u16()
		var kind: int = b.get_u8()
		var weapon: int = b.get_u8()
		var ammo: int = b.get_u8()
		var pf: int = b.get_u8()
		pickups[pid2] = {
			"kind": kind,
			"weapon": weapon,
			"ammo": ammo,
			"blink": pf & PK_BLINK != 0,
			"fresh": pf & PK_FRESH != 0,
			"pos": Vector2(b.get_float(), b.get_float()),
		}
	s["pickups"] = pickups
	var movers: Array[Vector2] = []
	n = b.get_u8()
	for i: int in range(n):
		movers.append(Vector2(b.get_float(), b.get_float()))
	s["movers"] = movers
	var crate_count: int = b.get_u16()
	var crates: Array[bool] = []
	var byte: int = 0
	for i: int in range(crate_count):
		if i % 8 == 0:
			byte = b.get_u8()
		crates.append(byte & (1 << (i % 8)) != 0)
	s["crates"] = crates
	return s
