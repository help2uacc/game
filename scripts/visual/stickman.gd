class_name Stickman
extends Node3D
## Blocky stickman visuals + procedural animation (PRD §6.1, §6.3).
## Pure visuals: driven by Player (gameplay) or by menus/podium.

signal death_finished(world_position: Vector3, color: Color)

enum Anim { IDLE, RUN, JUMP, DOUBLE_JUMP, FALL, LAND, PUNCH, SHOOT, THROW, HIT, DEATH }

const BODY_YAW := deg_to_rad(40.0)
const FLIP_TIME := 0.35
const LAND_TIME := 0.14
const PUNCH_TIME := 0.18
const SHOOT_TIME := 0.12
const THROW_TIME := 0.25
const HIT_TIME := 0.15
const HIT_FLASH_TIME := 0.08
const TOPPLE_TIME := 0.45
const FADE_TIME := 0.6

const WEAPON_SCENES: Dictionary = {
	1: "res://scenes/weapons/pistol.tscn",
	2: "res://scenes/weapons/smg.tscn",
	3: "res://scenes/weapons/shotgun.tscn",
	4: "res://scenes/weapons/sniper.tscn",
	5: "res://scenes/weapons/rocket_launcher.tscn",
	6: "res://scenes/weapons/grenade.tscn",
}

@onready var _flip: Node3D = $Flip
@onready var _body: Node3D = $Flip/Body
@onready var _torso: MeshInstance3D = $Flip/Body/Torso
@onready var _head: MeshInstance3D = $Flip/Body/Head
@onready var _eyes: MeshInstance3D = $Flip/Body/Head/Eyes
@onready var _arm_f: Node3D = $Flip/Body/ArmFront
@onready var _arm_b: Node3D = $Flip/Body/ArmBack
@onready var _leg_f: Node3D = $Flip/Body/LegFront
@onready var _leg_b: Node3D = $Flip/Body/LegBack
@onready var _hand: Marker3D = $Flip/Body/ArmFront/Hand
@onready var _weapon_holder: Node3D = $WeaponHolder
@onready var _name_tag: Label3D = $NameTag
@onready var _local_marker: MeshInstance3D = $NameTag/LocalMarker
@onready var _shadow: MeshInstance3D = $BlobShadow

var color_id: int = 0
var facing: int = 1
var aim_angle: float = 0.0
var shadow_enabled: bool = true

var _parts: Array[MeshInstance3D] = []
var _base: int = Anim.IDLE
var _oneshot: int = -1
var _oneshot_t: float = 0.0
var _flip_t: float = -1.0
var _land_t: float = -1.0
var _hit_t: float = -1.0
var _flash_t: float = -1.0
var _recoil: float = 0.0
var _time: float = 0.0
var _run_phase: float = 0.0
var _run_speed: float = 0.0
var _dead: bool = false
var _death_t: float = 0.0
var _death_mat: ShaderMaterial = null
var _death_done: bool = false
var _weapon_id: int = 0
var _weapon_node: Node3D = null
var _flashing: bool = false
var _pending_name: String = ""
var _pending_local: bool = false
var _pending_weapon: int = 0


func _ready() -> void:
	_parts = [
		_torso, _head,
		_arm_f.get_node("Mesh") as MeshInstance3D, _arm_b.get_node("Mesh") as MeshInstance3D,
		_leg_f.get_node("Mesh") as MeshInstance3D, _leg_b.get_node("Mesh") as MeshInstance3D,
	]
	_shadow.top_level = true
	_weapon_holder.top_level = true
	set_color(color_id)
	set_facing(facing)
	_name_tag.text = _pending_name
	_local_marker.visible = _pending_local
	if _pending_weapon != 0:
		var w: int = _pending_weapon
		_pending_weapon = 0
		set_weapon(w)


func set_color(new_color_id: int) -> void:
	color_id = new_color_id
	if _parts.is_empty():
		return
	var mat: ShaderMaterial = MaterialCache.player(color_id)
	for p: MeshInstance3D in _parts:
		p.material_override = mat


func get_color() -> Color:
	return Palette.player_color(color_id)


func set_player_name(text: String, is_local: bool) -> void:
	_pending_name = text
	_pending_local = is_local
	if _name_tag == null:
		return
	_name_tag.text = text
	_local_marker.visible = is_local


func set_name_visible(v: bool) -> void:
	if _name_tag != null:
		_name_tag.visible = v


func set_facing(dir: int) -> void:
	facing = 1 if dir >= 0 else -1
	if _body == null:
		return
	# Mirror instead of turning so the front arm (weapon hand) always faces the camera.
	if facing > 0:
		_body.basis = Basis(Vector3.UP, BODY_YAW)
	else:
		_body.basis = Basis(Vector3.UP, -BODY_YAW) * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))


func set_aim(angle: float) -> void:
	aim_angle = angle


func set_weapon(weapon_id: int) -> void:
	if _weapon_holder == null:
		_pending_weapon = weapon_id
		return
	if weapon_id == _weapon_id:
		return
	_weapon_id = weapon_id
	if _weapon_node != null:
		_weapon_node.queue_free()
		_weapon_node = null
	if WEAPON_SCENES.has(weapon_id):
		var scene: PackedScene = load(WEAPON_SCENES[weapon_id])
		_weapon_node = scene.instantiate()
		_weapon_holder.add_child(_weapon_node)


func get_muzzle_position() -> Vector3:
	if _weapon_node != null and _weapon_node.has_node("Muzzle"):
		return (_weapon_node.get_node("Muzzle") as Node3D).global_position
	return _hand.global_position


## Base locomotion state from movement.
func set_motion(on_floor: bool, velocity: Vector2) -> void:
	_run_speed = absf(velocity.x)
	if on_floor:
		_base = Anim.RUN if _run_speed > 0.5 else Anim.IDLE
	else:
		_base = Anim.JUMP if velocity.y > 0.0 else Anim.FALL


func play(anim: int, strength: float = 0.3) -> void:
	if _dead:
		return
	match anim:
		Anim.DOUBLE_JUMP:
			_flip_t = 0.0
		Anim.LAND:
			_land_t = 0.0
		Anim.HIT:
			_hit_t = 0.0
			_flash_t = 0.0
		Anim.SHOOT:
			_recoil = clampf(strength, 0.05, 1.0)
		Anim.DEATH:
			_start_death()
		_:
			_oneshot = anim
			_oneshot_t = 0.0


func is_dead() -> bool:
	return _dead


func reset_pose() -> void:
	_dead = false
	_death_done = false
	_death_t = 0.0
	_flip.rotation = Vector3.ZERO
	_flip.position = Vector3(0, 0.9, 0)
	_flip.scale = Vector3.ONE
	visible = true
	_name_tag.visible = true
	set_color(color_id)


func _start_death() -> void:
	_dead = true
	_death_t = 0.0
	_death_done = false
	_name_tag.visible = false
	_shadow.visible = false
	set_weapon(0)


func _process(delta: float) -> void:
	_time += delta
	if _dead:
		_animate_death(delta)
		return
	_animate(delta)
	_update_weapon_holder()
	if _flash_t >= 0.0:
		_flash_t += delta
		_set_flash(_flash_t < HIT_FLASH_TIME)
		if _flash_t >= HIT_FLASH_TIME:
			_flash_t = -1.0


func _set_flash(on: bool) -> void:
	if on == _flashing:
		return
	_flashing = on
	var mat: ShaderMaterial = MaterialCache.white() if on else MaterialCache.player(color_id)
	for p: MeshInstance3D in _parts:
		p.material_override = mat


func _animate(delta: float) -> void:
	var arm_f: float = 0.15
	var arm_b: float = -0.15
	var leg_f: float = 0.0
	var leg_b: float = 0.0
	var bob: float = 0.0
	var lean: float = 0.0
	match _base:
		Anim.IDLE:
			bob = sin(_time * 3.0) * 0.025
			arm_f = 0.08 + sin(_time * 3.0) * 0.05
			arm_b = -0.08 - sin(_time * 3.0) * 0.05
		Anim.RUN:
			_run_phase += delta * (6.0 + _run_speed * 1.4)
			var s: float = sin(_run_phase)
			leg_f = s * 0.85
			leg_b = -s * 0.85
			arm_f = -s * 0.7
			arm_b = s * 0.7
			bob = absf(cos(_run_phase)) * 0.06
			lean = 0.12
		Anim.JUMP:
			leg_f = -0.7
			leg_b = 0.35
			arm_f = -2.4
			arm_b = -2.2
		Anim.FALL:
			leg_f = -0.25
			leg_b = 0.25
			arm_f = -2.7 + sin(_time * 14.0) * 0.15
			arm_b = -2.6 - sin(_time * 14.0) * 0.15
	# Weapon pose overlay (hold_weapon): front arm points along the aim.
	if _weapon_id != 0:
		arm_f = -PI * 0.5 - aim_angle + _recoil * 0.9
	_recoil = move_toward(_recoil, 0.0, delta * 6.0)
	# One-shot overlays.
	if _oneshot >= 0:
		_oneshot_t += delta
		match _oneshot:
			Anim.PUNCH:
				var p: float = clampf(_oneshot_t / PUNCH_TIME, 0.0, 1.0)
				arm_f = lerpf(-PI * 0.5, 0.2, p) if p > 0.5 else lerpf(0.4, -PI * 0.5, p * 2.0)
				lean = 0.25 * sin(p * PI)
				if _oneshot_t >= PUNCH_TIME:
					_oneshot = -1
			Anim.THROW:
				var p2: float = clampf(_oneshot_t / THROW_TIME, 0.0, 1.0)
				arm_f = lerpf(-3.0, -1.2, p2)
				lean = 0.2 * sin(p2 * PI)
				if _oneshot_t >= THROW_TIME:
					_oneshot = -1
			_:
				_oneshot = -1
	if _hit_t >= 0.0:
		_hit_t += delta
		lean -= 0.35 * sin(clampf(_hit_t / HIT_TIME, 0.0, 1.0) * PI)
		if _hit_t >= HIT_TIME:
			_hit_t = -1.0
	_arm_f.rotation.x = arm_f
	_arm_b.rotation.x = arm_b
	_leg_f.rotation.x = leg_f
	_leg_b.rotation.x = leg_b
	_torso.rotation.x = lean * 0.5
	_head.rotation.x = lean * 0.3
	# Whole-body flip (double jump) and squash (land).
	var flip_angle: float = 0.0
	if _flip_t >= 0.0:
		_flip_t += delta
		var f: float = clampf(_flip_t / FLIP_TIME, 0.0, 1.0)
		flip_angle = -TAU * ease(f, -1.6) * float(facing)
		if _flip_t >= FLIP_TIME:
			_flip_t = -1.0
			flip_angle = 0.0
	var squash: float = 0.0
	if _land_t >= 0.0:
		_land_t += delta
		squash = sin(clampf(_land_t / LAND_TIME, 0.0, 1.0) * PI) * 0.22
		if _land_t >= LAND_TIME:
			_land_t = -1.0
	_flip.rotation = Vector3(0.0, 0.0, flip_angle)
	_flip.position = Vector3(0.0, 0.9 + bob - squash * 0.9 * 0.5, 0.0)
	_flip.scale = Vector3(1.0 + squash * 0.6, 1.0 - squash, 1.0 + squash * 0.6)


func _update_weapon_holder() -> void:
	if _weapon_node == null:
		return
	var b := Basis(Vector3.FORWARD, -aim_angle) if facing > 0 else Basis(Vector3.UP, PI) * Basis(Vector3.FORWARD, -aim_angle)
	_weapon_holder.global_transform = Transform3D(b, _hand.global_position + Vector3(0, 0, 0.12))


## Topples backwards, bounces once, fades over 0.6 s, then pops (§6.3).
func _animate_death(delta: float) -> void:
	if _death_done:
		return
	_death_t += delta
	var t: float = _death_t
	var topple: float = clampf(t / TOPPLE_TIME, 0.0, 1.0)
	var angle: float = (PI * 0.5) * ease(topple, 0.4) * float(facing)
	var bounce: float = 0.0
	if topple >= 1.0:
		var bt: float = clampf((t - TOPPLE_TIME) / 0.25, 0.0, 1.0)
		bounce = sin(bt * PI) * 0.25
	_flip.rotation = Vector3(0.0, 0.0, angle)
	_flip.position = Vector3(0.0, 0.9 - 0.6 * topple + bounce, 0.0)
	if t > TOPPLE_TIME:
		if _death_mat == null:
			_death_mat = MaterialCache.unique_alpha(get_color(), 1.0)
			for p: MeshInstance3D in _parts:
				p.material_override = _death_mat
		var fade: float = clampf((t - TOPPLE_TIME) / FADE_TIME, 0.0, 1.0)
		_death_mat.set_shader_parameter("alpha", 1.0 - fade)
		if fade >= 1.0:
			_death_done = true
			visible = false
			death_finished.emit(_flip.global_position, get_color())


func _physics_process(_delta: float) -> void:
	if not shadow_enabled or _dead or not is_inside_tree():
		_shadow.visible = false
		return
	var from: Vector3 = global_position + Vector3(0, 0.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -30, 0), 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_shadow.visible = false
		return
	_shadow.visible = true
	var hp: Vector3 = hit["position"]
	_shadow.global_position = hp + Vector3(0, 0.02, 0)
	var dist: float = from.y - hp.y
	var s: float = clampf(1.0 - dist * 0.06, 0.4, 1.0)
	_shadow.scale = Vector3(s, 1.0, s)
