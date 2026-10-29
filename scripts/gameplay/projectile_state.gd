class_name ProjectileState
extends RefCounted
## A projectile in flight: rocket, grenade or a thrown weapon.

enum Type { ROCKET = 0, GRENADE = 1, THROWN = 2 }

var id: int = 0
var type: int = Type.ROCKET
var owner: int = -1
var pos: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO
var age: float = 0.0
var weapon_id: int = 0
var ammo: int = 0
var bounce_cooldown: float = 0.0
var node: Node3D = null
