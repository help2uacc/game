extends SceneTree
## Generates every Godot resource asset from primitives (PRD §11.3):
##   godot --headless -s tools/build_assets.gd
## Outputs: shared materials, weapon/item/theme data, box-built scenes
## (stickman, weapons, projectiles, pickups, hazards), the GridMap
## MeshLibrary and the UI Theme. Deterministic: re-running gives the same files.

const INK := Color("#3A3550")
const WHITE := Color("#FFFDF8")

var _vertex_mat: ShaderMaterial
var _errors: int = 0


func _initialize() -> void:
	for d: String in ["res://assets/materials", "res://assets/blocks", "res://data/weapons", "res://data/items",
			"res://data/themes", "res://scenes/characters", "res://scenes/weapons", "res://scenes/pickups",
			"res://scenes/hazards", "res://ui/theme"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	_build_materials()
	_build_weapon_data()
	_build_item_data()
	_build_themes()
	_build_stickman()
	_build_weapons()
	_build_pickups()
	_build_hazards()
	_build_mesh_library()
	_build_ui_theme()
	print("build_assets finished with %d error(s)" % _errors)
	quit(1 if _errors > 0 else 0)


func _save(res: Resource, path: String) -> void:
	var err: int = ResourceSaver.save(res, path)
	if err != OK:
		printerr("Failed to save %s (%d)" % [path, err])
		_errors += 1


func _flat_mat(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/flat_block.gdshader")
	m.set_shader_parameter("albedo", color)
	return m


# ---------------------------------------------------------------- materials
func _build_materials() -> void:
	_save(_flat_mat(INK), "res://assets/materials/ink.tres")
	_save(_flat_mat(WHITE), "res://assets/materials/white.tres")
	for i: int in range(Palette.COLOR_COUNT):
		_save(_flat_mat(Palette.PLAYER_COLORS[i]), "res://assets/materials/player_%d.tres" % i)
	var v := ShaderMaterial.new()
	v.shader = load("res://assets/shaders/flat_vertex.gdshader")
	_save(v, "res://assets/materials/flat_vertex.tres")
	var vf := ShaderMaterial.new()
	vf.shader = load("res://assets/shaders/flat_vertex.gdshader")
	vf.set_shader_parameter("flash", 0.6)
	_save(vf, "res://assets/materials/flat_vertex_flash.tres")
	var sh := ShaderMaterial.new()
	sh.shader = load("res://assets/shaders/blob_shadow.gdshader")
	_save(sh, "res://assets/materials/blob_shadow.tres")
	_vertex_mat = load("res://assets/materials/flat_vertex.tres")


# ---------------------------------------------------------------- data
func _weapon(id: int, key: String, display: String, kind: int, damage: int, rate: float, ammo: int,
		rng: float, spread: float, kb: float, weight: int, sfx: String) -> WeaponData:
	var w := WeaponData.new()
	w.id = id
	w.key = key
	w.display_name = display
	w.kind = kind as WeaponData.Kind
	w.damage = damage
	w.fire_rate = rate
	w.ammo = ammo
	w.weapon_range = rng
	w.spread_deg = spread
	w.knockback = kb
	w.spawn_weight = weight
	w.sfx = sfx
	w.icon = "res://assets/ui/icons/%s.svg" % key
	w.scene_path = "res://scenes/weapons/%s.tscn" % ("grenade" if key == "grenades" else key)
	return w


func _build_weapon_data() -> void:
	var pistol := _weapon(1, "pistol", "Pistol", WeaponData.Kind.HITSCAN, 18, 3.0, 12, 25.0, 2.0, 2.0, 25, "pistol")
	pistol.recoil = 0.3
	_save(pistol, "res://data/weapons/pistol.tres")
	var smg := _weapon(2, "smg", "SMG", WeaponData.Kind.HITSCAN, 9, 10.0, 40, 18.0, 6.0, 1.0, 20, "smg")
	smg.recoil = 0.15
	_save(smg, "res://data/weapons/smg.tres")
	var shotgun := _weapon(3, "shotgun", "Shotgun", WeaponData.Kind.HITSCAN, 9, 1.2, 6, 10.0, 15.0, 8.0, 20, "shotgun")
	shotgun.pellets = 6
	shotgun.recoil = 0.7
	_save(shotgun, "res://data/weapons/shotgun.tres")
	var sniper := _weapon(4, "sniper", "Sniper", WeaponData.Kind.HITSCAN, 70, 0.8, 4, 60.0, 0.0, 10.0, 12, "sniper")
	sniper.shake = 0.1
	sniper.recoil = 0.9
	_save(sniper, "res://data/weapons/sniper.tres")
	var rocket := _weapon(5, "rocket_launcher", "Rocket Launcher", WeaponData.Kind.PROJECTILE, 60, 0.7, 3, 40.0, 0.0, 14.0, 8, "rocket_launch")
	rocket.splash_radius = 3.0
	rocket.splash_edge_damage = 20
	rocket.projectile_speed = 18.0
	rocket.projectile_lifetime = 3.0
	rocket.self_damage_factor = 0.5
	rocket.destroys_crates = true
	rocket.shake = 0.1
	rocket.recoil = 1.0
	_save(rocket, "res://data/weapons/rocket_launcher.tres")
	var grenades := _weapon(6, "grenades", "Grenades", WeaponData.Kind.THROWN_PROJECTILE, 70, 1.0, 3, 16.0, 0.0, 12.0, 15, "grenade_throw")
	grenades.splash_radius = 3.5
	grenades.splash_edge_damage = 15
	grenades.fuse_time = 2.0
	grenades.self_damage_factor = 0.5
	grenades.destroys_crates = true
	grenades.recoil = 0.2
	_save(grenades, "res://data/weapons/grenades.tres")
	var punch := _weapon(0, "punch", "Punch", WeaponData.Kind.MELEE, 12, 1.0 / 0.45, -1, 1.2, 0.0, 5.0, 0, "punch_swing")
	punch.scene_path = ""
	_save(punch, "res://data/weapons/punch.tres")


func _build_item_data() -> void:
	var h := ItemData.new()
	h.id = 0
	h.key = "health_pack"
	h.display_name = "Health Pack"
	h.heal_amount = 40
	h.spawn_weight = 60
	h.sfx = "pickup_health"
	h.scene_path = "res://scenes/pickups/health_pack.tscn"
	_save(h, "res://data/items/health_pack.tres")
	var a := ItemData.new()
	a.id = 1
	a.key = "armor"
	a.display_name = "Armor"
	a.armor_amount = 50
	a.spawn_weight = 40
	a.sfx = "pickup_armor"
	a.scene_path = "res://scenes/pickups/armor.tscn"
	_save(a, "res://data/items/armor.tres")


func _decor(c: Color, amount: float) -> Color:
	var light: Color = c.lerp(Color("#FFFFFF"), amount)
	light.s *= 0.75
	return light


func _theme(id: String, primary: String, secondary: String, bg_top: String, bg_bottom: String,
		lava: String = "#FF9F5A", crate: String = "#E8BE8A", accents: Array = []) -> void:
	var t := MapTheme.new()
	t.id = id
	t.primary = Color(primary)
	t.secondary = Color(secondary)
	t.platform = Color(secondary).lerp(Color(primary), 0.35).darkened(0.05)
	t.lava = Color(lava)
	t.crate = Color(crate)
	t.bg_top = Color(bg_top)
	t.bg_bottom = Color(bg_bottom)
	t.decor_a = _decor(Color(primary), 0.45)
	t.decor_b = _decor(Color(secondary), 0.35)
	var acc: Array[Color] = []
	for a: Variant in accents:
		acc.append(Color(str(a)))
	t.accents = acc
	_save(t, "res://data/themes/%s.tres" % id)


func _build_themes() -> void:
	_theme("candy", "#F7A8C4", "#FFF1D6", "#FFE3EE", "#FFF8EC")
	_theme("mint", "#9FE2C6", "#F4FFF9", "#DDF7EE", "#F7FFFB")
	_theme("lava", "#FFCBA4", "#FF9E8A", "#FFE6D5", "#FFF3E8", "#FF8C42")
	_theme("cloud", "#A7D3FF", "#FFFFFF", "#CFE6FF", "#F3F9FF")
	_theme("crate", "#FFE39A", "#C9A487", "#FFF4CF", "#FFFBEA", "#FF9F5A", "#D9A57A")
	_theme("spike", "#C7B8F5", "#C9C6D3", "#E6E0FA", "#F5F3FA")
	_theme("bubblegum", "#FFB3D9", "#D9B8F0", "#FFE0F0", "#F8F0FF")
	_theme("lilac", "#D4BFF2", "#A88BC7", "#E9DDF8", "#F6F0FC", "#FF8C5A")
	_theme("peach", "#FFD0B0", "#F2DDB0", "#FFEBDD", "#FFF8EE")
	_theme("sky", "#BFE0FF", "#BDF0D8", "#DCEEFF", "#F2FFF8")
	_theme("garden", "#A9E5A0", "#FFB8CF", "#E3F7DF", "#FFF4F8")
	_theme("sorbet", "#FFC4D6", "#C4E8FF", "#FFEAF1", "#F0F8FF", "#FF9F5A", "#E8BE8A",
			["#FFD9A8", "#FFF2A8", "#C8F2C2", "#D9C9FF"])


# ---------------------------------------------------------------- helpers
func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for c: Node in node.get_children():
		_own(c, owner_node)


func _pack(top: Node, path: String) -> void:
	for c: Node in top.get_children():
		_own(c, top)
	var ps := PackedScene.new()
	var err: int = ps.pack(top)
	if err != OK:
		printerr("pack failed for %s" % path)
		_errors += 1
		return
	_save(ps, path)
	top.free()


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _mesh_node(node_name: String, mesh: Mesh, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _vmesh(boxes: Array) -> ArrayMesh:
	return BoxBuilder.build(boxes, _vertex_mat)


# ---------------------------------------------------------------- stickman
func _build_stickman() -> void:
	var top := Node3D.new()
	top.name = "Stickman"
	top.set_script(load("res://scripts/visual/stickman.gd"))
	var flip := Node3D.new()
	flip.name = "Flip"
	flip.position = Vector3(0, 0.9, 0)
	top.add_child(flip)
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, -0.9, 0)
	flip.add_child(body)
	var leg_mesh := _box_mesh(Vector3(0.14, 0.55, 0.14))
	var arm_mesh := _box_mesh(Vector3(0.12, 0.45, 0.12))
	for side: Array in [["LegFront", -0.08], ["LegBack", 0.08]]:
		var leg := Node3D.new()
		leg.name = side[0]
		leg.position = Vector3(side[1], 0.55, 0)
		body.add_child(leg)
		leg.add_child(_mesh_node("Mesh", leg_mesh, Vector3(0, -0.275, 0)))
	body.add_child(_mesh_node("Torso", _box_mesh(Vector3(0.18, 0.6, 0.18)), Vector3(0, 0.85, 0)))
	var head := _mesh_node("Head", _box_mesh(Vector3(0.5, 0.5, 0.5)), Vector3(0, 1.45, 0))
	body.add_child(head)
	var eyes_mesh := BoxBuilder.build([
		[Vector3(-0.11, 0.04, 0.25), Vector3(0.08, 0.08, 0.04), INK],
		[Vector3(0.11, 0.04, 0.25), Vector3(0.08, 0.08, 0.04), INK],
	], _vertex_mat)
	head.add_child(_mesh_node("Eyes", eyes_mesh))
	for side2: Array in [["ArmFront", -0.15], ["ArmBack", 0.15]]:
		var arm := Node3D.new()
		arm.name = side2[0]
		arm.position = Vector3(side2[1], 1.12, 0)
		body.add_child(arm)
		arm.add_child(_mesh_node("Mesh", arm_mesh, Vector3(0, -0.225, 0)))
		if side2[0] == "ArmFront":
			var hand := Marker3D.new()
			hand.name = "Hand"
			hand.position = Vector3(0, -0.42, 0)
			arm.add_child(hand)
	var holder := Node3D.new()
	holder.name = "WeaponHolder"
	top.add_child(holder)
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.position = Vector3(0, 2.05, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.006
	tag.font_size = 40
	tag.outline_size = 14
	tag.modulate = WHITE
	tag.outline_modulate = INK
	tag.no_depth_test = true
	tag.render_priority = 2
	tag.outline_render_priority = 1
	tag.text = "Player"
	top.add_child(tag)
	var marker_mesh := PrismMesh.new()
	marker_mesh.size = Vector3(0.22, 0.16, 0.05)
	var marker := _mesh_node("LocalMarker", marker_mesh, Vector3(0, 0.26, 0))
	marker.rotation = Vector3(0, 0, PI)
	marker.material_override = load("res://assets/materials/white.tres")
	tag.add_child(marker)
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.9, 0.9)
	var shadow := _mesh_node("BlobShadow", plane)
	shadow.material_override = load("res://assets/materials/blob_shadow.tres")
	top.add_child(shadow)
	_pack(top, "res://scenes/characters/stickman.tscn")


# ---------------------------------------------------------------- weapons
func _weapon_scene(file_name: String, boxes: Array, muzzle: Vector3) -> void:
	var top := Node3D.new()
	top.name = file_name.to_pascal_case()
	top.add_child(_mesh_node("Mesh", _vmesh(boxes)))
	var m := Marker3D.new()
	m.name = "Muzzle"
	m.position = muzzle
	top.add_child(m)
	_pack(top, "res://scenes/weapons/%s.tscn" % file_name)


func _build_weapons() -> void:
	var gold := Palette.GOLD
	var blue := Palette.ARMOR
	var red := Palette.DANGER
	var mint := Color("#8FD694")
	var lilac := Color("#B49CFF")
	var peach := Color("#FFB26B")
	_weapon_scene("pistol", [
		[Vector3(0.12, 0.05, 0), Vector3(0.32, 0.1, 0.08), INK],
		[Vector3(0.0, -0.05, 0), Vector3(0.08, 0.16, 0.07), INK],
		[Vector3(0.14, 0.105, 0), Vector3(0.18, 0.03, 0.085), gold],
	], Vector3(0.29, 0.05, 0))
	_weapon_scene("smg", [
		[Vector3(0.14, 0.05, 0), Vector3(0.42, 0.12, 0.09), INK],
		[Vector3(0.05, -0.08, 0), Vector3(0.07, 0.2, 0.07), blue],
		[Vector3(-0.04, -0.04, 0), Vector3(0.07, 0.14, 0.07), INK],
		[Vector3(0.37, 0.06, 0), Vector3(0.1, 0.05, 0.05), INK],
		[Vector3(0.18, 0.12, 0), Vector3(0.2, 0.03, 0.095), blue],
	], Vector3(0.43, 0.06, 0))
	_weapon_scene("shotgun", [
		[Vector3(0.3, 0.07, 0), Vector3(0.7, 0.08, 0.08), INK],
		[Vector3(0.28, -0.01, 0), Vector3(0.22, 0.09, 0.1), peach],
		[Vector3(-0.08, 0.02, 0), Vector3(0.24, 0.12, 0.08), peach],
		[Vector3(0.0, -0.06, 0), Vector3(0.07, 0.14, 0.07), INK],
	], Vector3(0.66, 0.07, 0))
	_weapon_scene("sniper", [
		[Vector3(0.45, 0.06, 0), Vector3(0.95, 0.06, 0.06), INK],
		[Vector3(0.08, 0.04, 0), Vector3(0.4, 0.11, 0.08), INK],
		[Vector3(0.12, 0.14, 0), Vector3(0.26, 0.07, 0.07), lilac],
		[Vector3(-0.18, 0.02, 0), Vector3(0.2, 0.12, 0.07), lilac],
		[Vector3(0.0, -0.06, 0), Vector3(0.07, 0.14, 0.07), INK],
	], Vector3(0.93, 0.06, 0))
	_weapon_scene("rocket_launcher", [
		[Vector3(0.18, 0.1, 0), Vector3(0.9, 0.2, 0.2), mint],
		[Vector3(0.6, 0.1, 0), Vector3(0.08, 0.24, 0.24), INK],
		[Vector3(-0.24, 0.1, 0), Vector3(0.08, 0.24, 0.24), INK],
		[Vector3(0.05, -0.04, 0), Vector3(0.07, 0.14, 0.07), INK],
		[Vector3(0.22, 0.23, 0), Vector3(0.12, 0.06, 0.06), red],
	], Vector3(0.66, 0.1, 0))
	var grenade_boxes: Array = [
		[Vector3(0.08, 0.02, 0), Vector3(0.2, 0.2, 0.2), mint],
		[Vector3(0.08, 0.15, 0), Vector3(0.1, 0.07, 0.1), INK],
		[Vector3(0.15, 0.2, 0), Vector3(0.06, 0.06, 0.03), gold],
	]
	_weapon_scene("grenade", grenade_boxes, Vector3(0.1, 0.05, 0))
	# Projectiles.
	var rocket := Node3D.new()
	rocket.name = "RocketProjectile"
	rocket.add_child(_mesh_node("Mesh", _vmesh([
		[Vector3(0, 0, 0), Vector3(0.4, 0.12, 0.12), WHITE],
		[Vector3(0.24, 0, 0), Vector3(0.1, 0.1, 0.1), red],
		[Vector3(-0.18, 0, 0), Vector3(0.1, 0.24, 0.04), INK],
		[Vector3(-0.18, 0, 0), Vector3(0.1, 0.04, 0.24), INK],
	])))
	var trail := CPUParticles3D.new()
	trail.name = "Trail"
	trail.amount = 16
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.mesh = _box_mesh(Vector3(0.1, 0.1, 0.1))
	trail.direction = Vector3(-1, 0, 0)
	trail.spread = 25.0
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 1.5
	trail.gravity = Vector3(0, 0.5, 0)
	trail.scale_amount_min = 0.6
	trail.scale_amount_max = 1.0
	trail.color = Color("#FFE8C8")
	trail.position = Vector3(-0.25, 0, 0)
	trail.material_override = load("res://assets/materials/white.tres")
	rocket.add_child(trail)
	_pack(rocket, "res://scenes/weapons/rocket_projectile.tscn")
	var gp := Node3D.new()
	gp.name = "GrenadeProjectile"
	gp.add_child(_mesh_node("Mesh", _vmesh(grenade_boxes)))
	_pack(gp, "res://scenes/weapons/grenade_projectile.tscn")


# ---------------------------------------------------------------- pickups
func _pickup_scene(scene_name: String, boxes: Array) -> void:
	var top := Node3D.new()
	top.name = scene_name.to_pascal_case()
	top.set_script(load("res://scripts/visual/pickup_view.gd"))
	var model := Node3D.new()
	model.name = "Model"
	model.position = Vector3(0, 0.45, 0)
	top.add_child(model)
	if not boxes.is_empty():
		model.add_child(_mesh_node("Mesh", _vmesh(boxes)))
	_pack(top, "res://scenes/pickups/%s.tscn" % scene_name)


func _build_pickups() -> void:
	_pickup_scene("weapon_pickup", [])
	var red := Palette.HEAL
	var boxes: Array = [[Vector3.ZERO, Vector3(0.5, 0.5, 0.5), WHITE]]
	for n: Vector3 in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var thick: Vector3 = Vector3(0.04, 0.04, 0.04)
		var off: Vector3 = n * 0.25
		var horiz: Vector3 = Vector3(0.3, 0.09, 0.09)
		var vert: Vector3 = Vector3(0.09, 0.3, 0.09)
		if absf(n.x) > 0.5:
			horiz = Vector3(0.09, 0.09, 0.3)
		boxes.append([off, horiz + thick * 0.0, red])
		boxes.append([off, vert, red])
	boxes.append([Vector3(0, 0.25, 0), Vector3(0.3, 0.09, 0.09), red])
	boxes.append([Vector3(0, 0.25, 0), Vector3(0.09, 0.09, 0.3), red])
	_pickup_scene("health_pack", boxes)
	var blue := Palette.ARMOR
	var shield: Array = [[Vector3.ZERO, Vector3(0.5, 0.5, 0.5), blue]]
	for z: float in [0.25, -0.25]:
		shield.append([Vector3(0, 0.08, z), Vector3(0.28, 0.1, 0.04), WHITE])
		shield.append([Vector3(0, -0.02, z), Vector3(0.22, 0.1, 0.04), WHITE])
		shield.append([Vector3(0, -0.11, z), Vector3(0.12, 0.08, 0.04), WHITE])
	_pickup_scene("armor", shield)


# ---------------------------------------------------------------- hazards
func _spike_mesh() -> ArrayMesh:
	var steel := Color("#E9E6F2")
	var base := Color("#9C97B0")
	var boxes: Array = [[Vector3(0, -0.42, 0), Vector3(1.0, 0.16, 1.0), base]]
	var diamond := Basis(Vector3(0, 0, 1), PI * 0.25)
	for x: float in [-0.33, 0.0, 0.33]:
		for z: float in [-0.25, 0.25]:
			boxes.append([Vector3(x, -0.3, z), Vector3(0.24, 0.24, 0.22), steel, diamond])
	return _vmesh(boxes)


func _crate_mesh() -> ArrayMesh:
	var wood := Color("#E8BE8A")
	var dark := Color("#B98A5E")
	var boxes: Array = [[Vector3(0, 0.5, 0), Vector3(0.96, 0.96, 0.96), wood]]
	for z: float in [0.485, -0.485]:
		boxes.append([Vector3(0, 0.93, z), Vector3(0.96, 0.1, 0.03), dark])
		boxes.append([Vector3(0, 0.07, z), Vector3(0.96, 0.1, 0.03), dark])
		boxes.append([Vector3(0.43, 0.5, z), Vector3(0.1, 0.96, 0.03), dark])
		boxes.append([Vector3(-0.43, 0.5, z), Vector3(0.1, 0.96, 0.03), dark])
		boxes.append([Vector3(0, 0.5, z), Vector3(0.1, 1.05, 0.03), dark, Basis(Vector3(0, 0, 1), PI * 0.25)])
	return _vmesh(boxes)


func _build_hazards() -> void:
	# Lava: bubbling cubes over a lava run (blocks are GridMap cells).
	var lava := Node3D.new()
	lava.name = "Lava"
	lava.set_script(load("res://scripts/gameplay/lava.gd"))
	var bubbles := CPUParticles3D.new()
	bubbles.name = "Bubbles"
	bubbles.amount = 6
	bubbles.lifetime = 1.2
	bubbles.mesh = _box_mesh(Vector3(0.14, 0.14, 0.14))
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	bubbles.emission_box_extents = Vector3(0.5, 0.05, 0.35)
	bubbles.direction = Vector3(0, 1, 0)
	bubbles.spread = 10.0
	bubbles.initial_velocity_min = 0.3
	bubbles.initial_velocity_max = 0.8
	bubbles.gravity = Vector3.ZERO
	bubbles.scale_amount_min = 0.5
	bubbles.scale_amount_max = 1.2
	bubbles.material_override = load("res://assets/materials/white.tres")
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.2))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 0.0))
	bubbles.scale_amount_curve = curve
	lava.add_child(bubbles)
	_pack(lava, "res://scenes/hazards/lava.tscn")
	# Spikes (also used as the GridMap spike item).
	var spikes := Node3D.new()
	spikes.name = "Spikes"
	spikes.add_child(_mesh_node("Mesh", _spike_mesh(), Vector3(0, 0.5, 0)))
	_pack(spikes, "res://scenes/hazards/spikes.tscn")
	# Crate.
	var crate := StaticBody3D.new()
	crate.name = "Crate"
	crate.set_script(load("res://scripts/gameplay/crate.gd"))
	crate.collision_layer = 1 | 32
	crate.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	cs.shape = box
	cs.position = Vector3(0, 0.5, 0)
	crate.add_child(cs)
	crate.add_child(_mesh_node("Mesh", _crate_mesh()))
	_pack(crate, "res://scenes/hazards/crate.tscn")
	# Jump pad.
	var pad := Node3D.new()
	pad.name = "JumpPad"
	pad.set_script(load("res://scripts/gameplay/jump_pad.gd"))
	pad.add_child(_mesh_node("Base", _vmesh([
		[Vector3(0, 0.06, 0), Vector3(0.9, 0.12, 0.9), Color("#9C97B0")],
		[Vector3(0, 0.2, 0), Vector3(0.22, 0.18, 0.22), INK],
	])))
	pad.add_child(_mesh_node("Top", _vmesh([
		[Vector3(0, 0, 0), Vector3(0.8, 0.1, 0.8), Palette.GOLD],
		[Vector3(0, 0.06, 0), Vector3(0.3, 0.03, 0.3), WHITE],
	]), Vector3(0, 0.32, 0)))
	_pack(pad, "res://scenes/hazards/jump_pad.tscn")
	# Moving platform (cells are built at runtime from the map data).
	var mover := AnimatableBody3D.new()
	mover.name = "MovingPlatform"
	mover.set_script(load("res://scripts/gameplay/moving_platform.gd"))
	mover.sync_to_physics = true
	mover.collision_layer = 1
	mover.collision_mask = 0
	_pack(mover, "res://scenes/hazards/moving_platform.tscn")


# ---------------------------------------------------------------- mesh library
func _build_mesh_library() -> void:
	var lib := MeshLibrary.new()
	var white_mat: ShaderMaterial = load("res://assets/materials/white.tres")
	var cube := BoxBuilder.build([[Vector3.ZERO, Vector3.ONE, Color.WHITE]], white_mat)
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	var items: Array = [
		[0, "block", cube, true],
		[1, "block_alt", BoxBuilder.build([[Vector3.ZERO, Vector3.ONE, Color.WHITE]], white_mat), true],
		[2, "one_way", BoxBuilder.build([[Vector3(0, 0.375, 0), Vector3(1, 0.25, 1), Color.WHITE]], white_mat), false],
		[3, "lava", BoxBuilder.build([[Vector3(0, -0.08, 0), Vector3(1, 0.84, 1), Color.WHITE]], white_mat), false],
		[4, "spikes", _spike_mesh(), false],
		[5, "decor_a", BoxBuilder.build([[Vector3.ZERO, Vector3.ONE, Color.WHITE]], white_mat), false],
		[6, "decor_b", BoxBuilder.build([[Vector3.ZERO, Vector3.ONE, Color.WHITE]], white_mat), false],
	]
	for it: Array in items:
		var id: int = it[0]
		lib.create_item(id)
		lib.set_item_name(id, it[1])
		lib.set_item_mesh(id, it[2])
		if it[3]:
			lib.set_item_shapes(id, [shape, Transform3D.IDENTITY])
	_save(lib, "res://assets/blocks/mesh_library.tres")


# ---------------------------------------------------------------- UI theme
func _style(bg: Color, radius: int = 16, shadow: int = 8, border: int = 0, border_color: Color = INK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.shadow_color = Palette.UI_SHADOW
	s.shadow_size = shadow
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	if border > 0:
		s.set_border_width_all(border)
		s.border_color = border_color
	return s


func _build_ui_theme() -> void:
	var t := Theme.new()
	t.default_font_size = 34
	t.set_color("font_color", "Label", INK)
	t.set_color("font_outline_color", "Label", WHITE)
	# Buttons.
	t.set_stylebox("normal", "Button", _style(WHITE))
	t.set_stylebox("hover", "Button", _style(Color("#FFF6E0")))
	t.set_stylebox("pressed", "Button", _style(Color("#FFE7B8"), 16, 2))
	t.set_stylebox("disabled", "Button", _style(Color(1, 1, 1, 0.45), 16, 0))
	t.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), 16, 0, 4, Palette.GOLD))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.4))
	t.set_font_size("font_size", "Button", 38)
	# Panels.
	t.set_stylebox("panel", "PanelContainer", _style(Palette.UI_PANEL, 16, 10))
	t.set_stylebox("panel", "Panel", _style(Palette.UI_PANEL, 16, 10))
	# Line edit.
	t.set_stylebox("normal", "LineEdit", _style(WHITE, 12, 0, 3, Color(INK, 0.35)))
	t.set_stylebox("focus", "LineEdit", _style(Color(0, 0, 0, 0), 12, 0, 4, Palette.GOLD))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.4))
	t.set_font_size("font_size", "LineEdit", 36)
	# Check button / sliders / item list text.
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", INK)
	t.set_color("font_pressed_color", "CheckButton", INK)
	t.set_color("font_hover_pressed_color", "CheckButton", INK)
	t.set_color("font_focus_color", "CheckButton", INK)
	var empty := StyleBoxEmpty.new()
	for st: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", empty)
	if ResourceLoader.exists("res://assets/ui/icons/toggle_on.svg"):
		t.set_icon("checked", "CheckButton", load("res://assets/ui/icons/toggle_on.svg"))
		t.set_icon("unchecked", "CheckButton", load("res://assets/ui/icons/toggle_off.svg"))
		t.set_icon("checked_disabled", "CheckButton", load("res://assets/ui/icons/toggle_on.svg"))
		t.set_icon("unchecked_disabled", "CheckButton", load("res://assets/ui/icons/toggle_off.svg"))
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(INK, 0.15)
	slider.set_corner_radius_all(8)
	slider.content_margin_top = 8
	slider.content_margin_bottom = 8
	t.set_stylebox("slider", "HSlider", slider)
	var area := StyleBoxFlat.new()
	area.bg_color = Palette.GOLD
	area.set_corner_radius_all(8)
	area.content_margin_top = 8
	area.content_margin_bottom = 8
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	# Type variations.
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 72)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font_size("font_size", "HeaderLabel", 48)
	t.set_type_variation("SmallLabel", "Label")
	t.set_font_size("font_size", "SmallLabel", 26)
	t.set_type_variation("BigButton", "Button")
	t.set_font_size("font_size", "BigButton", 48)
	t.set_type_variation("HudLabel", "Label")
	t.set_color("font_color", "HudLabel", WHITE)
	t.set_color("font_outline_color", "HudLabel", INK)
	t.set_constant("outline_size", "HudLabel", 10)
	t.set_font_size("font_size", "HudLabel", 34)
	_save(t, "res://ui/theme/block_brawl_theme.tres")
