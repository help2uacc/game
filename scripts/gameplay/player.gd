class_name Player
extends CharacterBody3D
## A player in the world (PRD §6). On the authority (host / sandbox) it is
## simulated with CharacterBody3D physics from PlayerInput; on clients it is
## a replica positioned from interpolated snapshots.

signal landed(player: Player)
signal jumped(player: Player, double: bool)

const STICKMAN_SCENE: PackedScene = preload("res://scenes/characters/stickman.tscn")
const DROP_THROUGH_TIME := 0.25

# Identity.
var pid: int = 0
var color_id: int = 0
var display_name: String = ""
var is_local: bool = false

# Gameplay state (replicated).
var alive: bool = true
var hp: int = GameConfig.MAX_HP
var armor: int = 0
var weapon_id: int = 0
var ammo: int = 0
var facing: int = 1
var aim_angle: float = 0.0
var grounded: bool = false

# Simulation-only state.
var on_platform: bool = false
var coyote_t: float = 0.0
var jump_buffer_t: float = 0.0
var drop_t: float = 0.0
var invuln_t: float = 0.0
## Stunned (no control) after the second melee hit in a row (v1.1).
var stun_t: float = 0.0
var melee_hits: int = 0
var last_melee_t: float = -100.0
var fire_cooldown: float = 0.0
var double_jump_ready: bool = true
var last_input: PlayerInput = PlayerInput.new()
var _prev_jump_pressed: bool = false
var _prev_pickup_pressed: bool = false
var _prev_throw_pressed: bool = false
var _wants_drop: bool = false
var _down_hold_t: float = 0.0
## v1.2: holding down this long on a one-way platform drops through it.
const DROP_HOLD_TIME := 0.15
var _was_grounded: bool = false

var stickman: Stickman
var _step_t: float = 0.0


func _init() -> void:
	collision_layer = 2
	collision_mask = 1
	axis_lock_linear_z = true
	floor_snap_length = 0.15
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = 0.02
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = GameConfig.PLAYER_RADIUS
	capsule.height = GameConfig.PLAYER_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0, GameConfig.PLAYER_HEIGHT * 0.5, 0)
	add_child(shape)
	stickman = STICKMAN_SCENE.instantiate()
	add_child(stickman)


func setup(player_pid: int, player_color: int, player_name: String, local: bool) -> void:
	pid = player_pid
	color_id = player_color
	display_name = player_name
	is_local = local
	name = "Player%d" % pid
	stickman.color_id = player_color
	stickman.set_color(player_color)
	stickman.set_player_name(player_name, local)


func chest() -> Vector3:
	return global_position + Vector3(0, GameConfig.CHEST_HEIGHT, 0)


func center() -> Vector3:
	return global_position + Vector3(0, GameConfig.PLAYER_HEIGHT * 0.5, 0)


func reset_for_round(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	alive = true
	hp = GameConfig.MAX_HP
	armor = 0
	weapon_id = 0
	ammo = 0
	facing = 1 if pos.x < 50.0 else -1
	aim_angle = 0.0
	coyote_t = 0.0
	jump_buffer_t = 0.0
	drop_t = 0.0
	invuln_t = 0.0
	stun_t = 0.0
	melee_hits = 0
	last_melee_t = -100.0
	fire_cooldown = 0.0
	double_jump_ready = true
	visible = true
	collision_layer = 2
	stickman.reset_pose()
	stickman.set_weapon(0)
	stickman.set_facing(facing)


func is_knocked() -> bool:
	return absf(velocity.x) > GameConfig.RUN_SPEED + 0.01


## Rising-edge helpers for latched "pressed" flags (the client keeps sending
## a press until acknowledged, so the server only reacts to the rising edge).
## Returns a bit mask of EDGE_* flags (no allocation in the hot path).
const EDGE_JUMP := 1
const EDGE_PICKUP := 2
const EDGE_THROW := 4


func consume_edges(inp: PlayerInput) -> int:
	var e: int = 0
	if inp.jump_pressed and not _prev_jump_pressed:
		e |= EDGE_JUMP
	if inp.pickup_pressed and not _prev_pickup_pressed:
		e |= EDGE_PICKUP
	if inp.throw_pressed and not _prev_throw_pressed:
		e |= EDGE_THROW
	_prev_jump_pressed = inp.jump_pressed
	_prev_pickup_pressed = inp.pickup_pressed
	_prev_throw_pressed = inp.throw_pressed
	return e


## Movement simulation (PRD §6.4). Authority only.
func simulate_movement(inp: PlayerInput, jump_edge: bool, delta: float, map: GameMap) -> void:
	coyote_t = maxf(0.0, coyote_t - delta)
	jump_buffer_t = maxf(0.0, jump_buffer_t - delta)
	drop_t = maxf(0.0, drop_t - delta)
	invuln_t = maxf(0.0, invuln_t - delta)
	if grounded:
		coyote_t = GameConfig.COYOTE_TIME
		double_jump_ready = true
	if jump_edge:
		jump_buffer_t = GameConfig.JUMP_BUFFER
		_wants_drop = inp.down
	elif inp.jump_held and grounded and jump_buffer_t <= 0.0:
		# v1.2: holding the joystick up keeps hopping.
		jump_buffer_t = GameConfig.JUMP_BUFFER
		_wants_drop = false
	# v1.2: holding down on a one-way platform drops through it.
	if inp.down and on_platform and absf(inp.move_x) < 0.9:
		_down_hold_t += delta
		if _down_hold_t >= DROP_HOLD_TIME:
			_down_hold_t = 0.0
			jump_buffer_t = GameConfig.JUMP_BUFFER
			_wants_drop = true
	else:
		_down_hold_t = 0.0
	# Horizontal: accelerate toward input; reduced control while knocked back.
	var target_x: float = clampf(inp.move_x, -1.0, 1.0) * GameConfig.RUN_SPEED
	if is_knocked():
		target_x *= GameConfig.KNOCKBACK_CONTROL
	var accel: float = GameConfig.GROUND_ACCEL if grounded else GameConfig.AIR_ACCEL
	velocity.x = move_toward(velocity.x, target_x, accel * delta)
	if absf(inp.move_x) > 0.15 and not is_knocked():
		facing = 1 if inp.move_x > 0.0 else -1
	# Jumping.
	if jump_buffer_t > 0.0:
		if _wants_drop and on_platform:
			drop_t = DROP_THROUGH_TIME
			on_platform = false
			grounded = false
			coyote_t = 0.0
			jump_buffer_t = 0.0
			global_position.y -= 0.05
		elif coyote_t > 0.0:
			velocity.y = GameConfig.JUMP_VELOCITY
			coyote_t = 0.0
			jump_buffer_t = 0.0
			grounded = false
			jumped.emit(self, false)
		elif double_jump_ready and not grounded:
			velocity.y = GameConfig.DOUBLE_JUMP_VELOCITY
			double_jump_ready = false
			jump_buffer_t = 0.0
			jumped.emit(self, true)
	# Gravity.
	velocity.y = maxf(velocity.y - GameConfig.GRAVITY * delta, -GameConfig.MAX_FALL_SPEED)
	velocity.z = 0.0
	var prev_feet: float = global_position.y
	move_and_slide()
	global_position.z = 0.0
	# One-way platforms: land when the feet cross a platform top while falling.
	on_platform = false
	if velocity.y <= 0.0 and drop_t <= 0.0 and map != null:
		var x: float = global_position.x
		var r: float = GameConfig.PLAYER_RADIUS * 0.9
		var top: float = map.one_way_top_crossed(x - r, x + r, prev_feet, global_position.y)
		if not is_nan(top):
			global_position.y = top
			velocity.y = 0.0
			on_platform = true
	grounded = is_on_floor() or on_platform
	if grounded and not _was_grounded:
		landed.emit(self)
	_was_grounded = grounded


## Knockback impulse (PRD §6.4): `knockback × direction` plus an extra
## upward component of 0.3 × knockback.
func apply_knockback(direction: Vector3, knockback: float) -> void:
	if knockback <= 0.0:
		return
	var d := Vector3(direction.x, direction.y, 0.0)
	if d.length() < 0.001:
		d = Vector3(float(facing), 0, 0)
	d = d.normalized()
	velocity.x += d.x * knockback
	velocity.y += d.y * knockback + GameConfig.KNOCKBACK_UP_FACTOR * knockback
	grounded = false


## Visual update from the current state (both authority and replicas).
func update_visuals(delta: float) -> void:
	if not alive:
		return
	stickman.set_facing(facing)
	stickman.set_aim(aim_angle)
	stickman.set_weapon(weapon_id)
	stickman.set_motion(grounded, Vector2(velocity.x, velocity.y))
	stickman.set_stunned(stun_t > 0.0)
	# Footsteps while running on the ground.
	if grounded and absf(velocity.x) > 1.0:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.28
			AudioManager.play_at("footstep", global_position, randf_range(0.9, 1.15), -10.0)
	else:
		_step_t = 0.0
	if weapon_id == 0:
		aim_angle = move_toward(aim_angle, 0.0, delta * 4.0)
