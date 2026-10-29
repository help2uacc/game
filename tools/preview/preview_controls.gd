extends SceneTree
## Shows all action buttons: sandbox with a held shotgun and a pickup in reach.

var _f: int = 0
var _gs: Node = null


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		_gs = (load("res://scenes/main/sandbox.tscn") as PackedScene).instantiate()
		root.add_child(_gs)
	if _f == 40:
		var w: Object = _gs.get("world")
		var lp: Object = w.call("local_player")
		lp.set("weapon_id", 3)
		lp.set("ammo", 6)
		var pos: Vector3 = lp.get("global_position")
		w.call("spawn_pickup", 0, 4, 4, pos, false)
	if _f == 70:
		root.get_texture().get_image().save_png("res://build/controls.png")
		print("saved")
		quit()
	return false
