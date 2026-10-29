class_name GameScreen
extends Node
## In-round screen: World + touch controls + HUD layer.

@export var sandbox: bool = false
@export var sandbox_map: String = "candy_plains"

var world: World
var controls: TouchControls
var hud_layer: CanvasLayer
var _local_input := PlayerInput.new()


func _ready() -> void:
	world = World.new()
	world.name = "World"
	add_child(world)
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	add_child(hud_layer)
	controls = TouchControls.new()
	controls.name = "Controls"
	hud_layer.add_child(controls)
	if sandbox:
		_start_sandbox()


func _start_sandbox() -> void:
	world.authority = true
	world.load_map(sandbox_map)
	var spawn: Vector3 = world.map.player_spawns[0]
	var p: Player = world.add_player(1, 0, Settings.player_name if Settings.has_player_name() else "Player", true)
	p.reset_for_round(spawn)
	world.camera.snap_to_target()


func _physics_process(_delta: float) -> void:
	if world == null or world.local_pid == -1:
		return
	controls.read_input(_local_input)
	if world.authority:
		world.set_input(world.local_pid, _local_input)
		controls.ack_presses(true, true, true)
	var lp: Player = world.local_player()
	if lp != null:
		controls.update_context(false, lp.weapon_id)
