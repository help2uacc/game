extends TestCase
## Integration tests of the player controller against a real physics world
## (PRD §6.4): jump, double jump, one-way drop-through, knockback, kill line.


## 70x30 test map. Floor top at y=2 for x in [2, 60); one-way platform
## with top at y=5 for x in [20, 31).
func _test_map() -> MapData:
	var rows: PackedStringArray = []
	for r: int in range(30):
		var line: String = ".".repeat(70)
		var y: int = 29 - r
		if y <= 1:
			line = "..".rpad(2, ".") + "#".repeat(58) + ".".repeat(10)
		elif y == 4:
			line = ".".repeat(20) + "=".repeat(11) + ".".repeat(39)
		rows.append(line)
	var md := MapData.new()
	md.id = "test"
	md.display_name = "Test"
	md.theme = "candy"
	md.rows = rows
	md.width = 70
	md.height = 30
	return md


func _world() -> World:
	var w := World.new()
	add_node(w)
	w.load_map_data(_test_map())
	return w


func _spawn(w: World, pos: Vector3) -> Player:
	var p: Player = w.add_player(1, 0, "T", true)
	p.reset_for_round(pos)
	return p


func test_lands_on_floor() -> void:
	var w: World = _world()
	var p: Player = _spawn(w, Vector3(10.5, 4.0, 0))
	await physics_frames(40)
	assert_true(p.grounded, "grounded")
	assert_near(p.global_position.y, 2.0, 0.08, "standing on floor top")


func test_single_and_double_jump_heights() -> void:
	var w: World = _world()
	var p: Player = _spawn(w, Vector3(10.5, 2.2, 0))
	await physics_frames(20)
	var inp := PlayerInput.new()
	inp.jump_pressed = true
	w.set_input(1, inp)
	var apex: float = 0.0
	var start_y: float = p.global_position.y
	for i: int in range(50):
		await tree().physics_frame
		inp.jump_pressed = false
		w.set_input(1, inp)
		apex = maxf(apex, p.global_position.y)
	assert_near(apex - start_y, 121.0 / 60.0, 0.15, "single jump height v^2/2g")
	# Double jump: second press in the air adds height.
	await physics_frames(40)
	inp.jump_pressed = true
	w.set_input(1, inp)
	await tree().physics_frame
	inp.jump_pressed = false
	w.set_input(1, inp)
	for i: int in range(18):
		await tree().physics_frame
	inp.jump_pressed = true
	w.set_input(1, inp)
	var apex2: float = 0.0
	for i: int in range(60):
		await tree().physics_frame
		inp.jump_pressed = false
		w.set_input(1, inp)
		apex2 = maxf(apex2, p.global_position.y)
	assert_true(apex2 - start_y > 121.0 / 60.0 + 0.8, "double jump goes higher (%f)" % (apex2 - start_y))
	assert_false(p.double_jump_ready and not p.grounded, "double jump consumed in air")


func test_one_way_platform_and_drop_through() -> void:
	var w: World = _world()
	# Jump up through the platform from below.
	var p: Player = _spawn(w, Vector3(25.5, 2.2, 0))
	await physics_frames(20)
	var inp := PlayerInput.new()
	inp.jump_pressed = true
	w.set_input(1, inp)
	await tree().physics_frame
	inp.jump_pressed = false
	w.set_input(1, inp)
	await physics_frames(12)
	inp.jump_pressed = true
	w.set_input(1, inp)
	await tree().physics_frame
	inp.jump_pressed = false
	w.set_input(1, inp)
	await physics_frames(70)
	assert_near(p.global_position.y, 5.0, 0.05, "landed on one-way platform top")
	assert_true(p.on_platform and p.grounded, "standing on platform")
	# Drop through: hold down + press jump.
	inp.down = true
	inp.jump_pressed = true
	w.set_input(1, inp)
	await tree().physics_frame
	inp.jump_pressed = false
	w.set_input(1, inp)
	await physics_frames(50)
	assert_near(p.global_position.y, 2.0, 0.08, "dropped to the floor")


func test_knockback_and_reduced_control() -> void:
	var w: World = _world()
	var p: Player = _spawn(w, Vector3(30.5, 2.2, 0))
	await physics_frames(20)
	p.apply_knockback(Vector3(1, 0, 0), 14.0)
	assert_near(p.velocity.x, 14.0, 0.001, "horizontal impulse")
	assert_near(p.velocity.y, 0.3 * 14.0, 0.001, "extra upward 0.3 x knockback")
	assert_true(p.is_knocked(), "knocked")
	var inp := PlayerInput.new()
	inp.move_x = -1.0
	w.set_input(1, inp)
	await physics_frames(3)
	assert_true(p.velocity.x > GameConfig.RUN_SPEED, "still knocked after 3 frames")
	await physics_frames(60)
	assert_near(p.velocity.x, -GameConfig.RUN_SPEED, 0.01, "control regained")


func test_fall_off_map_kills() -> void:
	var w: World = _world()
	var p: Player = _spawn(w, Vector3(65.5, 3.0, 0))
	var deaths: Array = []
	w.player_died.connect(func(v: int, k: int, c: int) -> void: deaths.append([v, k, c]))
	await physics_frames(120)
	assert_false(p.alive, "dead after falling")
	assert_eq(deaths.size(), 1)
	assert_eq(int(deaths[0][2]), GameConfig.Cause.FALL)


func test_holding_jump_keeps_hopping() -> void:
	var w: World = _world()
	var p: Player = _spawn(w, Vector3(10.5, 2.2, 0))
	await physics_frames(20)
	var inp := PlayerInput.new()
	inp.jump_held = true
	w.set_input(1, inp)
	var takeoffs: int = 0
	var was_grounded: bool = true
	for i: int in range(120):
		await tree().physics_frame
		if was_grounded and not p.grounded and p.velocity.y > 5.0:
			takeoffs += 1
		was_grounded = p.grounded
	assert_true(takeoffs >= 2, "hopped repeatedly while held (%d)" % takeoffs)


func test_hold_down_drops_through_platform() -> void:
	var w: World = _world()
	var p: Player = _spawn(w, Vector3(25.5, 5.2, 0))
	await physics_frames(20)
	assert_true(p.on_platform, "standing on the one-way platform")
	var inp := PlayerInput.new()
	inp.down = true
	w.set_input(1, inp)
	await physics_frames(50)
	assert_near(p.global_position.y, 2.0, 0.08, "dropped by holding down")


func test_holding_up_double_jumps() -> void:
	var w: World = _world()
	var p: Player = _spawn(w, Vector3(10.5, 2.2, 0))
	await physics_frames(20)
	var start_y: float = p.global_position.y
	var inp := PlayerInput.new()
	inp.jump_pressed = true
	inp.jump_held = true
	w.set_input(1, inp)
	await tree().physics_frame
	inp.jump_pressed = false
	w.set_input(1, inp)
	var apex: float = 0.0
	for i: int in range(70):
		await tree().physics_frame
		apex = maxf(apex, p.global_position.y)
	assert_true(apex - start_y > 121.0 / 60.0 + 1.2, "held up: double jump at the apex (%f)" % (apex - start_y))
