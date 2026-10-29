class_name WeaponData
extends Resource
## Weapon definition (PRD §7.3). Instances live in res://data/weapons/*.tres.

enum Kind { HITSCAN = 0, PROJECTILE = 1, THROWN_PROJECTILE = 2, MELEE = 3 }

@export var id: int = 0
@export var key: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.HITSCAN
## Damage per hit / per pellet / direct hit / explosion centre.
@export var damage: int = 0
@export var pellets: int = 1
## Shots per second (melee: 1 / cooldown).
@export var fire_rate: float = 1.0
## -1 = infinite.
@export var ammo: int = -1
@export var weapon_range: float = 10.0
@export var spread_deg: float = 0.0
@export var knockback: float = 0.0
@export var splash_radius: float = 0.0
@export var splash_edge_damage: int = 0
@export var projectile_speed: float = 0.0
@export var projectile_lifetime: float = 0.0
@export var fuse_time: float = 0.0
@export var self_damage_factor: float = 0.0
@export var destroys_crates: bool = false
@export var spawn_weight: int = 0
@export var shake: float = 0.0
@export var recoil: float = 0.3
@export var sfx: String = ""
@export var icon: String = ""
@export var scene_path: String = ""


func cooldown() -> float:
	return 1.0 / fire_rate if fire_rate > 0.0 else 1.0


func is_ranged() -> bool:
	return kind != Kind.MELEE
