class_name TouchControls
extends Control
## Touch controls (PRD §8): floating joystick on the left half, Attack,
## Pick Up, Throw on the right; multi-touch. v1.1: bigger buttons and manual
## aim — press Attack to fire, drag from it to aim (release = stop).
## v1.2: no Jump button — push the joystick up to jump (push up again in the
## air for the double jump, hold up to keep hopping); hold it down on a
## one-way platform to drop through. The joystick base is always visible.
## Debug keyboard controls on desktop (A/D move, S down, Space jump, J attack,
## K pick up, L throw); on desktop the mouse pointer aims.


const JOYSTICK_RADIUS := 110.0
const ATTACK_SIZE := 230.0
const PICKUP_SIZE := 170.0
const THROW_SIZE := 160.0
## Joystick y (screen, -1 = up) that triggers a jump; re-armed below JUMP_REARM.
const JUMP_ZONE := -0.6
const JUMP_REARM := -0.35
const ATTACK_COLOR := Color("#FF8FA3")
const PICKUP_COLOR := Color("#FFD36E")
const THROW_COLOR := Color("#8EC9FF")
## Drag distance (design px) from the Attack centre for a full aim vector.
const AIM_RADIUS := 150.0
const AIM_DEADZONE := 0.18
const ICON_DIR := "res://assets/ui/icons/"

var attack_btn: TouchButton
var pickup_btn: TouchButton
var throw_btn: TouchButton

var _joy_index: int = -1
var _joy_origin: Vector2 = Vector2.ZERO
var _joy_pos: Vector2 = Vector2.ZERO
var _joy_vec: Vector2 = Vector2.ZERO
var _keyboard: bool = false
var _jump_latch: bool = false
var _pickup_latch: bool = false
var _throw_latch: bool = false
var _enabled: bool = true
var _weapon_icon_key: String = ""
var _aim_pos: Vector2 = Vector2.ZERO
var _aim_vec: Vector2 = Vector2.ZERO
var _jump_armed: bool = true
var _joy_home: Vector2 = Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keyboard = not OS.has_feature("mobile")
	attack_btn = _make_button(ATTACK_SIZE, "attack", ATTACK_COLOR, "")
	pickup_btn = _make_button(PICKUP_SIZE, "pickup", PICKUP_COLOR, "PICK UP")
	throw_btn = _make_button(THROW_SIZE, "throw", THROW_COLOR, "THROW")
	pickup_btn.visible = false
	throw_btn.visible = false
	resized.connect(_layout)
	_layout()


func _make_button(s: float, icon_name: String, color: Color, caption: String) -> TouchButton:
	var b := TouchButton.new()
	b.setup(s, load(ICON_DIR + icon_name + ".svg"), color, caption)
	add_child(b)
	return b


## Right-side layout in design pixels (safe-area aware).
func _layout() -> void:
	var r: Rect2 = _safe_rect()
	var right: float = r.end.x
	var bottom: float = r.end.y
	attack_btn.position = Vector2(right - ATTACK_SIZE - 30, bottom - ATTACK_SIZE - 30)
	pickup_btn.position = Vector2(right - PICKUP_SIZE - 60, bottom - ATTACK_SIZE - PICKUP_SIZE - 70)
	throw_btn.position = Vector2(right - ATTACK_SIZE - THROW_SIZE - 80, bottom - THROW_SIZE - 20)
	_joy_home = Vector2(r.position.x + JOYSTICK_RADIUS + 70, bottom - JOYSTICK_RADIUS - 60)
	queue_redraw()


## Visible area minus notches. Uses UiKit.safe_insets, which ignores bogus
## safe-area values (some older Android versions report the portrait rect).
func _safe_rect() -> Rect2:
	var vp: Rect2 = get_viewport_rect()
	var margin := Vector2(24, 24)
	var inset: Vector4 = UiKit.safe_insets(get_viewport())
	var pos := Vector2(inset.x, inset.y) + margin
	var end: Vector2 = vp.size - Vector2(inset.z, inset.w) - margin
	return Rect2(pos, end - pos)


func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on
	if not on:
		_release_all()


func _release_all() -> void:
	_joy_index = -1
	_joy_vec = Vector2.ZERO
	_aim_vec = Vector2.ZERO
	for b: TouchButton in [attack_btn, pickup_btn, throw_btn]:
		b.touch_index = -1
		b.set_pressed(false)
	queue_redraw()


## Context buttons: Pick Up only when overlapping a weapon pickup, Throw only
## when holding a weapon (PRD §8). Attack icon shows the current weapon.
func update_context(can_pickup: bool, weapon_id: int) -> void:
	pickup_btn.visible = can_pickup
	throw_btn.visible = weapon_id != 0
	var key: String = "attack" if weapon_id == 0 else GameConfig.WEAPON_KEYS[weapon_id]
	if key != _weapon_icon_key:
		_weapon_icon_key = key
		var path: String = ICON_DIR + key + ".svg"
		attack_btn.icon = load(path) if ResourceLoader.exists(path) else load(ICON_DIR + "attack.svg")
	if not pickup_btn.visible and pickup_btn.is_pressed:
		pickup_btn.touch_index = -1
		pickup_btn.set_pressed(false)
	if not throw_btn.visible and throw_btn.is_pressed:
		throw_btn.touch_index = -1
		throw_btn.set_pressed(false)


func _input(event: InputEvent) -> void:
	if not _enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == _joy_index:
			_joy_pos = d.position
			_update_joy()
		elif d.index == attack_btn.touch_index:
			_aim_pos = d.position
			_update_aim()


func _touch_down(index: int, pos: Vector2) -> void:
	for b: TouchButton in [pickup_btn, throw_btn, attack_btn]:
		if b.touch_index == -1 and b.hit(pos):
			b.touch_index = index
			b.set_pressed(true)
			if b == attack_btn:
				_aim_pos = pos
				_update_aim()
			if b == pickup_btn:
				_pickup_latch = true
			elif b == throw_btn:
				_throw_latch = true
			return
	if _joy_index == -1 and pos.x < get_viewport_rect().size.x * 0.5 and pos.y > 170.0:
		_joy_index = index
		_joy_origin = pos
		_joy_pos = pos
		_update_joy()


func _touch_up(index: int) -> void:
	if index == _joy_index:
		_joy_index = -1
		_joy_vec = Vector2.ZERO
		_jump_armed = true
		queue_redraw()
	for b: TouchButton in [pickup_btn, throw_btn, attack_btn]:
		if b.touch_index == index:
			b.touch_index = -1
			b.set_pressed(false)
			if b == attack_btn:
				_aim_vec = Vector2.ZERO
				queue_redraw()


func _update_aim() -> void:
	var c: Vector2 = attack_btn.position + attack_btn.size * 0.5
	var d: Vector2 = (_aim_pos - c) / AIM_RADIUS
	if d.length() > 1.0:
		d = d.normalized()
	_aim_vec = d if d.length() >= AIM_DEADZONE else Vector2.ZERO
	queue_redraw()


## True while the Attack stick is dragged out of its dead zone.
func has_touch_aim() -> bool:
	return _aim_vec != Vector2.ZERO


func _update_joy() -> void:
	var d: Vector2 = _joy_pos - _joy_origin
	if d.length() > JOYSTICK_RADIUS:
		d = d.normalized() * JOYSTICK_RADIUS
	_joy_vec = d / JOYSTICK_RADIUS
	# Pushing up into the jump zone jumps; leaving it re-arms (double jump).
	if _joy_vec.y <= JUMP_ZONE and _jump_armed:
		_jump_latch = true
		_jump_armed = false
	elif _joy_vec.y > JUMP_REARM:
		_jump_armed = true
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _keyboard or not _enabled:
		return
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_SPACE:
			_jump_latch = true
		KEY_K:
			_pickup_latch = true
		KEY_L:
			_throw_latch = true


## Builds this frame's input. Latched presses are kept until `ack_presses`.
func read_input(target: PlayerInput) -> void:
	var sens: float = Settings.joystick_sensitivity
	var mx: float = clampf(_joy_vec.x * sens, -1.0, 1.0)
	var down: bool = _joy_vec.y * sens > GameConfig.DROP_DOWN_THRESHOLD
	var attack: bool = attack_btn.is_pressed
	var jump_held: bool = _joy_index != -1 and _joy_vec.y <= JUMP_ZONE
	if _keyboard and _enabled:
		var kx: float = 0.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			kx -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			kx += 1.0
		if kx != 0.0:
			mx = kx
		down = down or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
		attack = attack or Input.is_physical_key_pressed(KEY_J)
		jump_held = jump_held or Input.is_physical_key_pressed(KEY_SPACE)
	target.move_x = mx
	target.down = down
	target.attack_held = attack
	target.jump_held = jump_held
	target.jump_pressed = _jump_latch
	target.pickup_pressed = _pickup_latch
	target.throw_pressed = _throw_latch
	# Screen y points down, world y up.
	target.aim_x = _aim_vec.x
	target.aim_y = -_aim_vec.y


## Clears latched presses once the authority has seen them.
func ack_presses(jump: bool, pickup: bool, throw: bool) -> void:
	if jump:
		_jump_latch = false
	if pickup:
		_pickup_latch = false
	if throw:
		_throw_latch = false


func _draw() -> void:
	# Attack aim stick.
	if attack_btn != null and attack_btn.is_pressed:
		var c: Vector2 = attack_btn.position + attack_btn.size * 0.5
		draw_arc(c, AIM_RADIUS, 0, TAU, 64, Color(Palette.INK, 0.25), 10.0, true)
		draw_arc(c, AIM_RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.75), 4.0, true)
		if _aim_vec != Vector2.ZERO:
			var tip: Vector2 = c + _aim_vec * AIM_RADIUS
			draw_line(c, tip, Color(ATTACK_COLOR, 0.8), 8.0, true)
			draw_circle(tip + Vector2(0, 4), 36.0, Color(Palette.INK, 0.25), true, -1.0, true)
			draw_circle(tip, 36.0, Color(1, 1, 1, 0.95), true, -1.0, true)
			draw_circle(tip, 26.0, ATTACK_COLOR, true, -1.0, true)
	# Joystick: always visible (ghost at its home spot when not touched).
	var active: bool = _joy_index != -1
	var origin: Vector2 = _joy_origin if active else _joy_home
	var a: float = 1.0 if active else 0.6
	draw_circle(origin + Vector2(0, 6), JOYSTICK_RADIUS, Color(Palette.INK, 0.18 * a), true, -1.0, true)
	draw_circle(origin, JOYSTICK_RADIUS, Color(1, 1, 1, 0.22 * a), true, -1.0, true)
	draw_arc(origin, JOYSTICK_RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.85 * a), 6.0, true)
	# Jump zone at the top of the ring.
	var in_zone: bool = active and _joy_vec.y <= JUMP_ZONE
	draw_arc(origin, JOYSTICK_RADIUS - 2.0, -PI * 0.5 - 0.55, -PI * 0.5 + 0.55, 24,
			Color(Palette.GOLD, (0.95 if in_zone else 0.7) * a), 12.0, true)
	var chev: Vector2 = origin + Vector2(0, -JOYSTICK_RADIUS * 0.62)
	draw_polyline(PackedVector2Array([chev + Vector2(-18, 10), chev, chev + Vector2(18, 10)]), Color(1, 1, 1, 0.9 * a), 6.0, true)
	var knob: Vector2 = origin + _joy_vec * JOYSTICK_RADIUS
	draw_circle(knob + Vector2(0, 5), 50.0, Color(Palette.INK, 0.25 * a), true, -1.0, true)
	draw_circle(knob, 50.0, Color(1, 1, 1, 0.95 * a), true, -1.0, true)
	draw_circle(knob, 38.0, Color(Palette.ARMOR if not in_zone else Palette.GOLD, 0.9 * a), true, -1.0, true)
	draw_circle(knob - Vector2(0, 12), 20.0, Color(1, 1, 1, 0.3 * a), true, -1.0, true)
