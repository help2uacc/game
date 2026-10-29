class_name BoxBuilder
extends RefCounted
## Builds box-only meshes (PRD §11.1) with per-vertex colours so that a
## multi-coloured model is a single draw call.

const _FACES: Array[Dictionary] = [
	{"n": Vector3(1, 0, 0), "u": Vector3(0, 0, -1), "v": Vector3(0, 1, 0)},
	{"n": Vector3(-1, 0, 0), "u": Vector3(0, 0, 1), "v": Vector3(0, 1, 0)},
	{"n": Vector3(0, 1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, -1)},
	{"n": Vector3(0, -1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, 1)},
	{"n": Vector3(0, 0, 1), "u": Vector3(1, 0, 0), "v": Vector3(0, 1, 0)},
	{"n": Vector3(0, 0, -1), "u": Vector3(-1, 0, 0), "v": Vector3(0, 1, 0)},
]


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Adds a box. `color` is an sRGB palette colour (the Compatibility renderer
## works in sRGB space, matching `source_color` uniforms).
static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	var half: Vector3 = size * 0.5
	var lin: Color = color
	for f: Dictionary in _FACES:
		var n: Vector3 = f["n"]
		var u: Vector3 = f["u"]
		var v: Vector3 = f["v"]
		var c: Vector3 = n * half
		var du: Vector3 = u * half
		var dv: Vector3 = v * half
		var corners: Array[Vector3] = [c - du - dv, c + du - dv, c + du + dv, c - du + dv]
		var wn: Vector3 = (basis * n).normalized()
		var idx: Array[int] = [0, 2, 1, 0, 3, 2]
		for i: int in idx:
			st.set_color(lin)
			st.set_normal(wn)
			st.set_uv(Vector2(1.0 if i == 1 or i == 2 else 0.0, 1.0 if i >= 2 else 0.0))
			st.add_vertex(center + basis * corners[i])


static func finish(st: SurfaceTool, material: Material = null) -> ArrayMesh:
	var mesh: ArrayMesh = st.commit()
	if material != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material)
	return mesh


## Convenience: one mesh from a list of [center, size, color, (basis)] entries.
static func build(boxes: Array, material: Material = null) -> ArrayMesh:
	var st: SurfaceTool = begin()
	for b: Array in boxes:
		var basis: Basis = b[3] if b.size() > 3 else Basis.IDENTITY
		add_box(st, b[0], b[1], b[2], basis)
	return finish(st, material)
