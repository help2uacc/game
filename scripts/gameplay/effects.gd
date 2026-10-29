class_name Effects
extends Node3D
## Pooled VFX (PRD §11.4, §12): cube bursts (CPUParticles3D), tracers,
## damage numbers. Particle counts are scaled by the quality preset.

const BURST_POOL := 16
const TRACER_POOL := 24
const NUMBER_POOL := 16
const TRACER_TIME := 0.12  # v1.1: tracers fade out instead of popping
const NUMBER_TIME := 0.7

var particle_factor: float = 1.0
var damage_numbers_enabled: bool = true

var _bursts: Array[CPUParticles3D] = []
var _burst_next: int = 0
var _tracers: Array[MeshInstance3D] = []
var _tracer_t: Array[float] = []
var _tracer_next: int = 0
var _numbers: Array[Label3D] = []
var _number_t: Array[float] = []
var _number_next: int = 0
var _cube: BoxMesh
var _tracer_mats: Array[ShaderMaterial] = []
var _tracer_len: Array[float] = []
var _glows: Array[MeshInstance3D] = []
var _glow_mats: Array[ShaderMaterial] = []
var _glow_sparks: Array[CPUParticles3D] = []
var _glow_t: Array[float] = []
var _glow_total: Array[float] = []
var _glow_next: int = 0
const GLOW_POOL := 8
var _tracer_mesh: BoxMesh


func _ready() -> void:
	_cube = BoxMesh.new()
	_cube.size = Vector3(0.16, 0.16, 0.16)
	_tracer_mesh = BoxMesh.new()
	_tracer_mesh.size = Vector3(1, 0.05, 0.05)
	var vmat: ShaderMaterial = MaterialCache.vertex()
	for i: int in range(BURST_POOL):
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.mesh = _cube
		p.material_override = vmat
		p.local_coords = false
		p.gravity = Vector3(0, -18, 0)
		p.direction = Vector3(0, 1, 0)
		p.spread = 180.0
		p.lifetime = 0.6
		p.amount = 8
		var curve := Curve.new()
		curve.add_point(Vector2(0, 1))
		curve.add_point(Vector2(1, 0))
		p.scale_amount_curve = curve
		add_child(p)
		_bursts.append(p)
	for i: int in range(TRACER_POOL):
		var t := MeshInstance3D.new()
		t.mesh = _tracer_mesh
		var tm: ShaderMaterial = MaterialCache.unique_alpha(Color("#FFF6D8"), 1.0)
		tm.set_shader_parameter("flat_tint", true)
		t.material_override = tm
		_tracer_mats.append(tm)
		_tracer_len.append(1.0)
		t.visible = false
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(t)
		_tracers.append(t)
		_tracer_t.append(0.0)
	_build_glows()
	for i: int in range(NUMBER_POOL):
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.pixel_size = 0.008
		l.font_size = 44
		l.outline_size = 14
		l.outline_modulate = Palette.INK
		l.visible = false
		l.render_priority = 3
		l.outline_render_priority = 2
		add_child(l)
		_numbers.append(l)
		_number_t.append(0.0)


## Burst of small cubes. `count` is the High-quality count.
func burst(pos: Vector3, color: Color, count: int, speed: float = 5.0, size: float = 1.0,
		lifetime: float = 0.6, gravity: float = -18.0, spread: float = 180.0, dir: Vector3 = Vector3.UP) -> void:
	var n: int = int(round(float(count) * particle_factor))
	if n <= 0:
		return
	var p: CPUParticles3D = _bursts[_burst_next]
	_burst_next = (_burst_next + 1) % _bursts.size()
	p.emitting = false
	p.global_position = pos
	p.amount = n
	p.color = color
	p.lifetime = lifetime
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.2
	p.gravity = Vector3(0, gravity, 0)
	p.spread = spread
	p.direction = dir
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	p.restart()
	p.emitting = true


## Ring of cubes (explosion shockwave) in the XY plane.
func ring(pos: Vector3, color: Color, radius: float, count: int) -> void:
	var n: int = int(round(float(count) * particle_factor))
	if n <= 0:
		return
	var p: CPUParticles3D = _bursts[_burst_next]
	_burst_next = (_burst_next + 1) % _bursts.size()
	p.emitting = false
	p.global_position = pos
	p.amount = n
	p.color = color
	p.lifetime = 0.35
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3(0, 0, 1)
	p.emission_ring_radius = radius * 0.3
	p.emission_ring_inner_radius = radius * 0.25
	p.emission_ring_height = 0.0
	p.direction = Vector3(1, 0, 0)
	p.spread = 180.0
	p.initial_velocity_min = radius * 2.0
	p.initial_velocity_max = radius * 2.6
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.6
	p.restart()
	p.emitting = true


func tracer(from: Vector3, to: Vector3, color: Color = Color("#FFF6D8")) -> void:
	var t: MeshInstance3D = _tracers[_tracer_next]
	_tracer_t[_tracer_next] = TRACER_TIME
	_tracer_next = (_tracer_next + 1) % _tracers.size()
	var d: Vector3 = to - from
	var length: float = d.length()
	if length < 0.01:
		return
	t.visible = true
	var idx: int = _tracers.find(t)
	_tracer_mats[idx].set_shader_parameter("albedo", color)
	_tracer_mats[idx].set_shader_parameter("alpha", 1.0)
	_tracer_len[idx] = length
	var x_axis: Vector3 = d / length
	var y_axis := Vector3(-x_axis.y, x_axis.x, 0)
	t.global_transform = Transform3D(Basis(x_axis * length, y_axis, Vector3(0, 0, 1)), from + d * 0.5)


func damage_number(pos: Vector3, amount: int, color: Color) -> void:
	if not damage_numbers_enabled:
		return
	var l: Label3D = _numbers[_number_next]
	_number_t[_number_next] = NUMBER_TIME
	_number_next = (_number_next + 1) % _numbers.size()
	l.text = str(amount)
	l.modulate = color
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0, 0.5)
	l.visible = true


func _process(delta: float) -> void:
	for i: int in range(_tracers.size()):
		if _tracer_t[i] > 0.0:
			_tracer_t[i] -= delta
			var k: float = clampf(_tracer_t[i] / TRACER_TIME, 0.0, 1.0)
			_tracer_mats[i].set_shader_parameter("alpha", k)
			# Thin out while fading for a smooth streak.
			var tb: Basis = _tracers[i].global_transform.basis
			_tracers[i].global_transform.basis = Basis(tb.x, tb.y.normalized() * (0.4 + 0.6 * k), tb.z.normalized() * (0.4 + 0.6 * k))
			if _tracer_t[i] <= 0.0:
				_tracers[i].visible = false
	_process_glows(delta)
	for i: int in range(_numbers.size()):
		if _number_t[i] > 0.0:
			_number_t[i] -= delta
			var l: Label3D = _numbers[i]
			l.position.y += delta * 1.6
			l.modulate.a = clampf(_number_t[i] / 0.25, 0.0, 1.0)
			if _number_t[i] <= 0.0:
				l.visible = false


# ---------------------------------------------------------------- spawn glow (v1.1)
func _build_glows() -> void:
	var col := BoxMesh.new()
	col.size = Vector3(0.9, 3.0, 0.9)
	var spark := BoxMesh.new()
	spark.size = Vector3(0.1, 0.1, 0.1)
	for i: int in range(GLOW_POOL):
		var g := MeshInstance3D.new()
		g.mesh = col
		var m: ShaderMaterial = MaterialCache.unique_alpha(Palette.GOLD, 0.0)
		m.set_shader_parameter("flat_tint", true)
		g.material_override = m
		g.visible = false
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_glows.append(g)
		_glow_mats.append(m)
		_glow_t.append(0.0)
		_glow_total.append(1.0)
		var p := CPUParticles3D.new()
		p.mesh = spark
		p.material_override = MaterialCache.vertex()
		p.emitting = false
		p.amount = 10
		p.lifetime = 0.8
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(0.45, 0.05, 0.3)
		p.direction = Vector3.UP
		p.spread = 10.0
		p.gravity = Vector3.ZERO
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 3.0
		add_child(p)
		_glow_sparks.append(p)


## A pulsing light column + rising sparkles over a spawn point, shown for
## `duration` seconds before the pickup pops in.
func spawn_glow(pos: Vector3, duration: float, weapon: bool) -> void:
	var i: int = _glow_next
	_glow_next = (_glow_next + 1) % GLOW_POOL
	var color: Color = Palette.GOLD if weapon else Palette.HEAL
	_glow_t[i] = duration
	_glow_total[i] = duration
	_glow_mats[i].set_shader_parameter("albedo", color)
	_glows[i].global_position = pos + Vector3(0, 1.5, 0)
	_glows[i].visible = true
	var p: CPUParticles3D = _glow_sparks[i]
	p.global_position = pos + Vector3(0, 0.1, 0)
	p.color = color.lightened(0.4)
	p.amount = maxi(2, int(round(10.0 * maxf(particle_factor, 0.3))))
	p.emitting = true


func _process_glows(delta: float) -> void:
	for i: int in range(GLOW_POOL):
		if _glow_t[i] <= 0.0:
			continue
		_glow_t[i] -= delta
		var elapsed: float = _glow_total[i] - _glow_t[i]
		var grow: float = clampf(elapsed / 0.25, 0.0, 1.0)
		var pulse: float = 0.5 + 0.5 * sin(elapsed * TAU * 3.0)
		var fade_out: float = clampf(_glow_t[i] / 0.15, 0.0, 1.0)
		_glow_mats[i].set_shader_parameter("alpha", (0.35 + 0.35 * pulse) * grow * fade_out)
		var w: float = 0.7 + 0.3 * pulse
		_glows[i].scale = Vector3(w, grow, w)
		if _glow_t[i] <= 0.0:
			_glows[i].visible = false
			_glow_sparks[i].emitting = false
