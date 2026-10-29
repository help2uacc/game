class_name MaterialCache
extends RefCounted
## Shared materials (PRD §11.2): one ShaderMaterial per colour, reused by
## every instance. Palette materials are pre-generated in res://assets/materials.

const FLAT_SHADER: Shader = preload("res://assets/shaders/flat_block.gdshader")
const ALPHA_SHADER: Shader = preload("res://assets/shaders/flat_block_alpha.gdshader")

static var _flat: Dictionary = {}
static var _files: Dictionary = {}
static var _alpha: Dictionary = {}


static func flat(color: Color) -> ShaderMaterial:
	var key: String = color.to_html(true)
	if _flat.has(key):
		return _flat[key]
	var mat := ShaderMaterial.new()
	mat.shader = FLAT_SHADER
	mat.set_shader_parameter("albedo", color)
	_flat[key] = mat
	return mat


static func player(color_id: int) -> ShaderMaterial:
	var path: String = "res://assets/materials/player_%d.tres" % color_id
	var key: String = "player_%d" % color_id
	if _flat.has(key):
		return _flat[key]
	var mat: ShaderMaterial = load(path) if ResourceLoader.exists(path) else flat(Palette.player_color(color_id))
	_flat[key] = mat
	return mat


## Shared transparent material (used for blinking / fading). Alpha is set
## per material, so callers needing a unique fade should use `unique_alpha`.
static func alpha(color: Color, a: float) -> ShaderMaterial:
	var key: String = "%s_%.2f" % [color.to_html(true), a]
	if _alpha.has(key):
		return _alpha[key]
	var mat := unique_alpha(color, a)
	_alpha[key] = mat
	return mat


static func unique_alpha(color: Color, a: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ALPHA_SHADER
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("alpha", a)
	return mat


static func _file(name: String) -> ShaderMaterial:
	if not _files.has(name):
		_files[name] = load("res://assets/materials/%s.tres" % name)
	return _files[name]


static func vertex() -> ShaderMaterial:
	return _file("flat_vertex")


static func vertex_flash() -> ShaderMaterial:
	return _file("flat_vertex_flash")


static func white() -> ShaderMaterial:
	return _file("white")


static func ink() -> ShaderMaterial:
	return _file("ink")
