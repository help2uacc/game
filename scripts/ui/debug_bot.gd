class_name DebugBot
extends RefCounted
## Development-only input driver used by the automated multi-instance smoke
## test (`tools/net_smoke_test.sh`, user arg `--bot`). Not a gameplay
## feature: only active in debug builds when explicitly requested.

var _rng := RandomNumberGenerator.new()
var _move: float = 1.0
var _t: float = 0.0


static func enabled() -> bool:
	return OS.is_debug_build() and OS.get_cmdline_user_args().has("--bot")


func _init() -> void:
	_rng.randomize()


func read_input(inp: PlayerInput, world: World) -> void:
	_t += 1.0 / 60.0
	if _t > 1.2:
		_t = 0.0
		_move = [-1.0, 0.0, 1.0][_rng.randi_range(0, 2)]
	var lp: Player = world.local_player()
	if lp != null and world.map != null:
		# Steer away from the map edges.
		if lp.global_position.x < 8.0:
			_move = 1.0
		elif lp.global_position.x > world.map.width() - 8.0:
			_move = -1.0
	inp.move_x = _move
	inp.down = false
	inp.jump_pressed = _rng.randf() < 0.03
	inp.jump_held = inp.jump_pressed
	inp.attack_held = _rng.randf() < 0.5
	# Aim at the nearest other living player.
	inp.aim_x = 0.0
	inp.aim_y = 0.0
	if lp != null:
		var best: Vector3 = Vector3.ZERO
		var best_d: float = INF
		for o: Player in world.alive_players():
			if o != lp and o.chest().distance_to(lp.chest()) < best_d:
				best_d = o.chest().distance_to(lp.chest())
				best = o.chest() - lp.chest()
		if best_d < INF:
			var dn: Vector3 = best.normalized()
			inp.aim_x = dn.x
			inp.aim_y = dn.y
	inp.pickup_pressed = _rng.randf() < 0.05
	inp.throw_pressed = _rng.randf() < 0.003
