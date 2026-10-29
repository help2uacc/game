class_name Crate
extends StaticBody3D
## Destructible crate (PRD §10.1): 30 HP, any damage source damages it.
## TODO(PRD): "destroyed by any damage source" read as: every source deals damage; explosions destroy outright.

signal destroyed(crate: Crate)

var index: int = 0
var hp: int = GameConfig.CRATE_HP
var alive: bool = true
var _shake_t: float = 0.0

@onready var _mesh: MeshInstance3D = $Mesh


## Applies damage. Returns true if this destroyed the crate.
func apply_damage(amount: int) -> bool:
	if not alive or amount <= 0:
		return false
	hp -= amount
	_shake_t = 0.15
	if hp <= 0:
		break_crate()
		return true
	return false


func break_crate() -> void:
	if not alive:
		return
	alive = false
	hp = 0
	visible = false
	collision_layer = 0
	destroyed.emit(self)


func _process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		_mesh.position.x = sin(_shake_t * 90.0) * 0.05
		_mesh.material_override = MaterialCache.vertex_flash() if _shake_t > 0.1 else null
	elif _mesh.position.x != 0.0:
		_mesh.position.x = 0.0
		_mesh.material_override = null
