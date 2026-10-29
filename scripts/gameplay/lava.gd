class_name Lava
extends Node3D
## Animated bubbling lava strip (PRD §10.1). The lava blocks themselves are
## GridMap cells; this node adds bubbling cubes over a horizontal run of cells.

@onready var _bubbles: CPUParticles3D = $Bubbles


func setup(width_cells: int, color: Color, particle_factor: float) -> void:
	_bubbles.emission_box_extents = Vector3(float(width_cells) * 0.5, 0.05, 0.35)
	_bubbles.position = Vector3(float(width_cells) * 0.5, 0.9, 0.0)
	_bubbles.amount = maxi(1, int(round(float(width_cells) * 1.5 * particle_factor)))
	_bubbles.color = color.lightened(0.35)
	_bubbles.emitting = particle_factor > 0.0
