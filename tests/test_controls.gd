extends TestCase
## v1.2 touch controls: joystick up jumps (re-armed for double jump), no
## Jump button; sandbox restarts after the local player dies.


func _touch(c: TouchControls, index: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	c._input(t)


func _drag(c: TouchControls, index: int, pos: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = pos
	c._input(d)


func test_joystick_up_jumps_and_rearms() -> void:
	var c := TouchControls.new()
	add_node(c)
	await tree().process_frame
	var inp := PlayerInput.new()
	_touch(c, 0, Vector2(300, 700), true)
	_drag(c, 0, Vector2(300, 690))
	c.read_input(inp)
	assert_false(inp.jump_pressed, "small push: no jump")
	_drag(c, 0, Vector2(300, 600))
	c.read_input(inp)
	assert_true(inp.jump_pressed and inp.jump_held, "push up: jump")
	c.ack_presses(true, true, true)
	c.read_input(inp)
	assert_false(inp.jump_pressed, "acked; still holding up does not re-press")
	assert_true(inp.jump_held, "held up")
	_drag(c, 0, Vector2(300, 700))
	_drag(c, 0, Vector2(300, 590))
	c.read_input(inp)
	assert_true(inp.jump_pressed, "re-armed: second jump (double jump)")
	_drag(c, 0, Vector2(400, 700))
	c.read_input(inp)
	assert_true(inp.move_x > 0.8, "sideways moves")
	_touch(c, 0, Vector2(400, 700), false)


func test_no_jump_button() -> void:
	var c := TouchControls.new()
	add_node(c)
	await tree().process_frame
	assert_false("jump_btn" in c, "jump button removed")
	var buttons: int = 0
	for ch: Node in c.get_children():
		if ch is TouchButton:
			buttons += 1
	assert_eq(buttons, 3, "Attack, Pick Up, Throw")


func test_sandbox_restarts_after_death() -> void:
	var scene: PackedScene = load("res://scenes/main/sandbox.tscn")
	var gs: GameScreen = scene.instantiate()
	add_node(gs)
	await physics_frames(5)
	var first: World = gs.world
	var lp: Player = first.local_player()
	first.kill_player(lp, KillCredit.NONE, GameConfig.Cause.FALL)
	for i: int in range(150):
		await tree().process_frame
		if gs.world != first:
			break
	assert_ne(gs.world, first, "a new sandbox world was built")
	assert_true(gs.world.local_player() != null and gs.world.local_player().alive, "player respawned")
