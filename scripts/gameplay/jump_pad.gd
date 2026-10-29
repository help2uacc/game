class_name JumpPad
extends Node3D
## Jump pad visual (PRD §10.1). Launch logic lives in the world simulation.

@onready var _top: Node3D = $Top

var _t: float = 1.0


func launch() -> void:
	_t = 0.0


func _process(delta: float) -> void:
	if _t < 0.35:
		_t += delta
		var p: float = clampf(_t / 0.35, 0.0, 1.0)
		_top.position.y = 0.32 + sin(p * PI) * 0.25
		_top.scale = Vector3(1.0 + sin(p * PI) * 0.1, 1.0, 1.0 + sin(p * PI) * 0.1)
