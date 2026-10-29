extends SceneTree
## Renders a preview of the box-built assets to build/preview_assets.png.
## xvfb-run godot --rendering-driver opengl3 -s tools/preview/preview_assets.gd

var _frames: int = 0
var _root3d: Node3D


func _initialize() -> void:
	_root3d = Node3D.new()
	root.add_child(_root3d)
	var cam := Camera3D.new()
	cam.position = Vector3(5.5, 2.5, 14)
	cam.fov = 40
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	_root3d.add_child(cam)
	cam.look_at(Vector3(5.5, 1.0, 0))
	var sky := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(200, 120)
	sky.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/sky_gradient.gdshader")
	sky.material_override = sm
	sky.position = Vector3(0, 0, -40)
	_root3d.add_child(sky)
	# floor
	var lib: MeshLibrary = load("res://assets/blocks/mesh_library.tres")
	for x: int in range(-4, 14):
		var b := MeshInstance3D.new()
		b.mesh = lib.get_item_mesh(0 if x % 3 else 1)
		b.material_override = MaterialCache.flat(Color("#F7A8C4") if x % 3 else Color("#FFF1D6"))
		b.position = Vector3(x + 0.5, -0.5, 0)
		_root3d.add_child(b)
	var stick: PackedScene = load("res://scenes/characters/stickman.tscn")
	for i: int in range(4):
		var s: Stickman = stick.instantiate()
		s.color_id = i * 2
		s.position = Vector3(i * 1.4 - 0.5, 0, 0)
		_root3d.add_child(s)
		s.set_facing(1 if i % 2 == 0 else -1)
		s.set_player_name("Player%d" % i, i == 0)
		s.set_weapon(i + 1)
	for j: int in range(2):
		var p: PackedScene = load("res://scenes/pickups/%s.tscn" % ["health_pack", "armor"][j])
		var n: Node3D = p.instantiate()
		n.position = Vector3(5.5 + j * 1.2, 0, 0)
		_root3d.add_child(n)
	var wp: PickupView = (load("res://scenes/pickups/weapon_pickup.tscn") as PackedScene).instantiate()
	wp.position = Vector3(8, 0, 0)
	_root3d.add_child(wp)
	wp.set_weapon(4)
	var crate: Node3D = (load("res://scenes/hazards/crate.tscn") as PackedScene).instantiate()
	crate.position = Vector3(9.5, 0, 0)
	_root3d.add_child(crate)
	var pad: Node3D = (load("res://scenes/hazards/jump_pad.tscn") as PackedScene).instantiate()
	pad.position = Vector3(10.7, 0, 0)
	_root3d.add_child(pad)
	var sp: Node3D = (load("res://scenes/hazards/spikes.tscn") as PackedScene).instantiate()
	sp.position = Vector3(11.9, 0, 0)
	_root3d.add_child(sp)
	var rk: Node3D = (load("res://scenes/weapons/rocket_projectile.tscn") as PackedScene).instantiate()
	rk.position = Vector3(6, 2.5, 0)
	_root3d.add_child(rk)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var img: Image = root.get_texture().get_image()
		img.save_png("res://build/preview_assets.png")
		print("saved preview")
		quit()
	return false
