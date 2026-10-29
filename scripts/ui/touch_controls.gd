class_name TouchControls
extends Control
## Touch controls (PRD §8): floating joystick on the left half, Attack, Jump,
## Pick Up, Throw on the right; multi-touch. Debug keyboard controls on
## desktop (A/D move, S down, Space jump, J attack, K pick up, L throw).


const JOYSTICK_RADIUS := 110.0
const ICON_DIR := "res://assets/ui/icons/"

var attack_btn: TouchButton
var jump_btn: TouchButton
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


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keyboard = not OS.has_feature("mobile")
	attack_btn = _make_button(160.0, "attack")
	jump_btn = _make_button(130.0, "jump")
	pickup_btn = _make_button(100.0, "pickup")
	throw_btn = _make_button(100.0, "throw")
	pickup_btn.visible = false
	throw_btn.visible = false
	resized.connect(_layout)
	_layout()


func _make_button(s: float, icon_name: String) -> TouchButton:
	var b := TouchButton.new()
	b.setup(s, load(ICON_DIR + icon_name + ".svg"))
	add_child(b)
	return b


## Right-side layout in design pixels (safe-area aware).
func _layout() -> void:
	var r: Rect2 = _safe_rect()
	var right: float = r.end.x
	var bottom: float = r.end.y
	attack_btn.position = Vector2(right - 360, bottom - 330)
	jump_btn.position = Vector2(right - 170, bottom - 170)
	pickup_btn.position = Vector2(right - 330, bottom - 470)
	throw_btn.position = Vector2(right - 500, bottom - 300)


func _safe_rect() -> Rect2:
	var vp: Rect2 = get_viewport_rect()
	var margin := Vector2(24, 24)
	if OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var win: Vector2i = DisplayServer.window_get_size()
		if win.x > 0 and safe.size.x > 0:
			var sx: float = vp.size.x / float(win.x)
			var left: float = float(safe.position.x) * sx
			var right_inset: float = float(win.x - safe.end.x) * sx
			return Rect2(Vector2(left, 0) + margin, vp.size - Vector2(left + right_inset, 0) - margin * 2.0)
	return Rect2(margin, vp.size - margin * 2.0)


func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on
	if not on:
		_release_all()


func _release_all() -> void:
	_joy_index = -1
	_joy_vec = Vector2.ZERO
	for b: TouchButton in [attack_btn, jump_btn, pickup_btn, throw_btn]:
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


func _touch_down(index: int, pos: Vector2) -> void:
	for b: TouchButton in [pickup_btn, throw_btn, jump_btn, attack_btn]:
		if b.touch_index == -1 and b.hit(pos):
			b.touch_index = index
			b.set_pressed(true)
			if b == jump_btn:
				_jump_latch = true
			elif b == pickup_btn:
				_pickup_latch = true
			elif b == throw_btn:
				_throw_latch = true
			return
	if _joy_index == -1 and pos.x < get_viewport_rect().size.x * 0.5 and pos.y > 150.0:
		_joy_index = index
		_joy_origin = pos
		_joy_pos = pos
		_update_joy()


func _touch_up(index: int) -> void:
	if index == _joy_index:
		_joy_index = -1
		_joy_vec = Vector2.ZERO
		queue_redraw()
	for b: TouchButton in [pickup_btn, throw_btn, jump_btn, attack_btn]:
		if b.touch_index == index:
			b.touch_index = -1
			b.set_pressed(false)


func _update_joy() -> void:
	var d: Vector2 = _joy_pos - _joy_origin
	if d.length() > JOYSTICK_RADIUS:
		d = d.normalized() * JOYSTICK_RADIUS
	_joy_vec = d / JOYSTICK_RADIUS
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
	var jump_held: bool = jump_btn.is_pressed
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


## Clears latched presses once the authority has seen them.
func ack_presses(jump: bool, pickup: bool, throw: bool) -> void:
	if jump:
		_jump_latch = false
	if pickup:
		_pickup_latch = false
	if throw:
		_throw_latch = false


func _draw() -> void:
	if _joy_index == -1:
		return
	draw_circle(_joy_origin, JOYSTICK_RADIUS, Color(1, 1, 1, 0.18))
	draw_arc(_joy_origin, JOYSTICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 4.0)
	draw_circle(_joy_origin + _joy_vec * JOYSTICK_RADIUS, 48.0, Color(1, 1, 1, 0.55))
