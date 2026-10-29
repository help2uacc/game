class_name PickupState
extends RefCounted
## A pickup lying in the world (weapon with ammo, or an item).

enum Kind { WEAPON = 0, HEALTH = 1, ARMOR = 2 }

var id: int = 0
var kind: int = Kind.WEAPON
var weapon_id: int = 0
var ammo: int = 0
var pos: Vector3 = Vector3.ZERO
var vel_y: float = 0.0
var resting: bool = false
var age: float = 0.0
var node: PickupView = null


func is_weapon() -> bool:
	return kind == Kind.WEAPON


func center() -> Vector3:
	return pos + Vector3(0, 0.45, 0)


func blinking() -> bool:
	return is_weapon() and age >= GameConfig.GROUND_WEAPON_DESPAWN - GameConfig.DESPAWN_BLINK_TIME
