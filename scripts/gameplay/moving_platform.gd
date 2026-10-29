class_name MovingPlatform
extends AnimatableBody3D
## Moving platform (PRD §10.1 `M` cells): ping-pong along a path of cell
## offsets at `speed` m/s, pausing `pause` s at every path point.
## The server simulates it; clients receive its position in snapshots.

var index: int = 0
var origin: Vector3 = Vector3.ZERO
var points: Array[Vector3] = []
var speed: float = 2.0
var pause: float = 1.0

var _target: int = 1
var _dir: int = 1
var _pause_t: float = 0.0


## `cells` are layout cells (x, row); `path` offsets are in cells with +y
## pointing down the layout (same as rows).  # TODO(PRD): path axis convention.
func setup(map: MapData, cells: Array, path: Array, move_speed: float, pause_time: float, material: Material) -> void:
	speed = move_speed
	pause = pause_time
	var min_c := Vector2i(1 << 20, 1 << 20)
	var max_c := Vector2i(-(1 << 20), -(1 << 20))
	for c: Variant in cells:
		var arr: Array = c
		var v := Vector2i(int(arr[0]), int(arr[1]))
		min_c = Vector2i(mini(min_c.x, v.x), mini(min_c.y, v.y))
		max_c = Vector2i(maxi(max_c.x, v.x), maxi(max_c.y, v.y))
	# Body origin = bottom-left corner of the bounding rect.
	origin = Vector3(float(min_c.x), float(map.height - 1 - max_c.y), 0.0)
	position = origin
	for c: Variant in cells:
		var arr2: Array = c
		var local := Vector3(float(int(arr2[0]) - min_c.x) + 0.5, float(max_c.y - int(arr2[1])) + 0.5, 0.0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE
		shape.shape = box
		shape.position = local
		add_child(shape)
	var mesh_inst := MeshInstance3D.new()
	var st: SurfaceTool = BoxBuilder.begin()
	for c: Variant in cells:
		var arr3: Array = c
		var local2 := Vector3(float(int(arr3[0]) - min_c.x) + 0.5, float(max_c.y - int(arr3[1])) + 0.5, 0.0)
		BoxBuilder.add_box(st, local2, Vector3(1.0, 1.0, 1.0), Color.WHITE)
	mesh_inst.mesh = BoxBuilder.finish(st)
	mesh_inst.material_override = material
	add_child(mesh_inst)
	points.clear()
	for p: Variant in path:
		var pa: Array = p
		points.append(origin + Vector3(float(pa[0]), -float(pa[1]), 0.0))
	if points.is_empty():
		points.append(origin)
	position = points[0]
	_target = 1 if points.size() > 1 else 0
	_dir = 1
	_pause_t = pause


func server_step(delta: float) -> void:
	if points.size() < 2:
		return
	if _pause_t > 0.0:
		_pause_t -= delta
		return
	var target: Vector3 = points[_target]
	var to: Vector3 = target - position
	var step: float = speed * delta
	if to.length() <= step:
		position = target
		_pause_t = pause
		if _target + _dir >= points.size() or _target + _dir < 0:
			_dir = -_dir
		_target += _dir
	else:
		position += to.normalized() * step


func set_remote_position(p: Vector3) -> void:
	position = p
