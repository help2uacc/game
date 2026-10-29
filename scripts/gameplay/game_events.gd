class_name GameEvents
extends RefCounted
## Discrete events sent reliably host -> clients (PRD §5.6) and applied
## locally for VFX/SFX. Each event is an Array: [type, ...args].

enum {
	SHOT = 0,          # pid, weapon_id, origin: Vector3, ends: PackedVector3Array
	PUNCH = 1,         # pid, hit: bool
	HIT = 2,           # victim pid, damage, armor_hit: bool, pos: Vector3, attacker pid
	DEATH = 3,         # victim pid, killer pid, cause
	PICKUP_SPAWN = 4,  # pickup id, pos
	PICKUP_TAKEN = 5,  # pickup id, pid, kind, weapon_id
	WEAPON_EMPTY = 6,  # pid, pos
	THROW = 7,         # pid
	EXPLOSION = 8,     # pos, radius
	CRATE_BROKEN = 9,  # crate index
	JUMP_PAD = 10,     # pid, pos
	JUMP = 11,         # pid, double: bool
	LAND = 12,         # pid
	SPIKE = 13,        # pid
	LAVA = 14,         # pid
	BOUNCE = 15,       # pos
	THROWN_HIT = 16,   # pos
	DESPAWN = 17,      # pickup id, pos
	ROCKET_FIRED = 18, # pid, pos
	SPAWN_WARN = 19,   # pos, kind (v1.1 spawn telegraph)
	STUN = 20,         # pid (v1.1 melee disarm + stun)
}
