class_name CameraRig
extends Camera3D
## Side-view follow camera (PRD §10.4): perspective FOV 40°, Z = +30 m,
## −6° tilt, smooth follow (lerp 8/s), 2 m look-ahead, 1 m vertical
## dead-zone, clamped to map bounds with 2 m margin, screen shake.

var target: Node3D = null
var map_size: Vector2 = Vector2(80, 35)

var _focus: Vector3 = Vector3.ZERO
var _look_ahead: float = 0.0
var _last_target_x: float = 0.0
var _shake_amp: float = 0.0
var _shake_t: float = 0.0
var _shake_dur: float = 0.0
var _rng := RandomNumberGenerator.new()
var _sky: MeshInstance3D
var _sky_mat: ShaderMaterial


func _ready() -> void:
	fov = GameConfig.CAMERA_FOV
	keep_aspect = Camera3D.KEEP_WIDTH
	near = 1.0
	far = 200.0
	current = true
	_sky = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(240, 160)
	_sky.mesh = quad
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://assets/shaders/sky_gradient.gdshader")
	_sky.material_override = _sky_mat
	_sky.position = Vector3(0, 0, -150)
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sky)


func set_sky(top: Color, bottom: Color) -> void:
	_sky_mat.set_shader_parameter("top_color", top)
	_sky_mat.set_shader_parameter("bottom_color", bottom)


func snap_to_target() -> void:
	if target == null:
		return
	_focus = target.global_position + Vector3(0, 1.0, 0)
	_last_target_x = target.global_position.x
	_look_ahead = 0.0
	_apply(_clamp_focus(_focus))


## Screen shake (amplitude in metres), scaled by distance by the caller.
func shake(amplitude: float, duration: float) -> void:
	if amplitude > _shake_amp * (1.0 - _shake_t / maxf(_shake_dur, 0.001)):
		_shake_amp = amplitude
		_shake_dur = duration
		_shake_t = 0.0


func _half_extents() -> Vector2:
	var half_w: float = tan(deg_to_rad(fov * 0.5)) * GameConfig.CAMERA_DISTANCE
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	return Vector2(half_w, half_w / aspect)


func _clamp_focus(f: Vector3) -> Vector3:
	var he: Vector2 = _half_extents()
	var m: float = GameConfig.CAMERA_MARGIN
	var out := f
	var min_x: float = -m + he.x
	var max_x: float = map_size.x + m - he.x
	out.x = (min_x + max_x) * 0.5 if min_x > max_x else clampf(f.x, min_x, max_x)
	var min_y: float = -m + he.y
	var max_y: float = map_size.y + m - he.y
	out.y = (min_y + max_y) * 0.5 if min_y > max_y else clampf(f.y, min_y, max_y)
	return out


func _apply(f: Vector3) -> void:
	var tilt: float = deg_to_rad(-GameConfig.CAMERA_TILT_DEG)
	var offset := Vector3(0, tan(tilt) * GameConfig.CAMERA_DISTANCE, GameConfig.CAMERA_DISTANCE)
	var shake_off := Vector3.ZERO
	if _shake_t < _shake_dur:
		var k: float = 1.0 - _shake_t / _shake_dur
		shake_off = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * _shake_amp * k
	global_position = Vector3(f.x, f.y, 0) + offset + shake_off
	rotation = Vector3(-tilt, 0, 0)


func _process(delta: float) -> void:
	if _shake_t < _shake_dur:
		_shake_t += delta
	if target == null or not is_instance_valid(target):
		_apply(_clamp_focus(_focus))
		return
	var tp: Vector3 = target.global_position
	# Look-ahead in the movement direction.
	var dx: float = tp.x - _last_target_x
	_last_target_x = tp.x
	if absf(dx) > 0.001:
		_look_ahead = move_toward(_look_ahead, signf(dx) * GameConfig.CAMERA_LOOK_AHEAD, delta * 4.0)
	var desired := Vector3(tp.x + _look_ahead, _focus.y, 0)
	# Vertical dead-zone around the focus.
	var ty: float = tp.y + 1.0
	if ty > _focus.y + GameConfig.CAMERA_DEAD_ZONE_Y:
		desired.y = ty - GameConfig.CAMERA_DEAD_ZONE_Y
	elif ty < _focus.y - GameConfig.CAMERA_DEAD_ZONE_Y:
		desired.y = ty + GameConfig.CAMERA_DEAD_ZONE_Y
	var k: float = 1.0 - exp(-GameConfig.CAMERA_LERP * delta)
	_focus = _focus.lerp(desired, k)
	_apply(_clamp_focus(_focus))


## Screen-space visibility helper for off-screen indicators.
func is_on_screen(world_pos: Vector3, margin: float = 0.0) -> bool:
	if is_position_behind(world_pos):
		return false
	var p: Vector2 = unproject_position(world_pos)
	var r: Rect2 = get_viewport().get_visible_rect().grow(-margin)
	return r.has_point(p)
