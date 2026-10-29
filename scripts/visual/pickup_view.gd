class_name PickupView
extends Node3D
## Pickup visuals: pop-in (0 -> 1.15 -> 1.0 over 0.25 s), bob, slow rotation,
## blinking during the last seconds (PRD §7.1, §7.5).

const BOB_AMPLITUDE := 0.12
const BOB_SPEED := 2.4
const SPIN_SPEED := 1.2
const BLINK_RATE := 8.0

@onready var _model: Node3D = $Model

var weapon_id: int = 0
var _t: float = 0.0
var _pop_t: float = 1.0
var _blink: bool = false
var _phase: float = 0.0


func _ready() -> void:
	_phase = randf() * TAU


func set_weapon(id: int) -> void:
	weapon_id = id
	if _model == null:
		_model = get_node("Model")
	for c: Node in _model.get_children():
		c.queue_free()
	if Stickman.WEAPON_SCENES.has(id):
		var scene: PackedScene = load(Stickman.WEAPON_SCENES[id])
		var w: Node3D = scene.instantiate()
		w.scale = Vector3.ONE * 1.4
		w.position = Vector3(-0.2, 0.0, 0.0)
		_model.add_child(w)


func pop() -> void:
	_pop_t = 0.0
	_model.scale = Vector3.ZERO


func set_blink(on: bool) -> void:
	_blink = on
	if not on:
		_model.visible = true


func _process(delta: float) -> void:
	_t += delta
	_model.position.y = 0.45 + sin(_t * BOB_SPEED + _phase) * BOB_AMPLITUDE
	_model.rotation.y = _t * SPIN_SPEED + _phase
	if _pop_t < GameConfig.SPAWN_POP_TIME:
		_pop_t += delta
		var p: float = clampf(_pop_t / GameConfig.SPAWN_POP_TIME, 0.0, 1.0)
		var s: float = lerpf(0.0, 1.15, p / 0.7) if p < 0.7 else lerpf(1.15, 1.0, (p - 0.7) / 0.3)
		_model.scale = Vector3.ONE * s
	if _blink:
		_model.visible = fmod(_t * BLINK_RATE, 2.0) < 1.2
