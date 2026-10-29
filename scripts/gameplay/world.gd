class_name World
extends Node3D
## The playfield of one round: map, players, pickups, projectiles, camera.
## `authority == true` (host or offline sandbox): runs the simulation.
## `authority == false` (client): renders interpolated snapshots.

signal player_died(victim: int, killer: int, cause: int)

var authority: bool = true
var map: GameMap
var camera: CameraRig
var players: Dictionary = {}  # pid -> Player
var inputs: Dictionary = {}  # pid -> PlayerInput (latest received)
var local_pid: int = -1
var frozen: bool = false  # countdown: players can't move
var sim_time: float = 0.0
var particle_factor: float = 1.0

var _players_root: Node3D
var _effects_root: Node3D


func _ready() -> void:
	_players_root = Node3D.new()
	_players_root.name = "Players"
	add_child(_players_root)
	_effects_root = Node3D.new()
	_effects_root.name = "Effects"
	add_child(_effects_root)
	camera = CameraRig.new()
	camera.name = "Camera"
	add_child(camera)
	particle_factor = Settings.particle_factor()


func load_map(map_id: String) -> bool:
	var md: MapData = GameMap.load_map(map_id)
	if not md.is_valid():
		push_error("Invalid map %s: %s" % [map_id, str(md.validate())])
		return false
	load_map_data(md)
	return true


## Builds the map from already parsed data (no validation; used by tests).
func load_map_data(md: MapData) -> void:
	map = GameMap.new()
	add_child(map)
	move_child(map, 0)
	map.build(md, Settings.background_decorations(), Settings.parallax_enabled(), particle_factor)
	camera.map_size = Vector2(map.width(), map.height())
	camera.set_sky(map.theme.bg_top, map.theme.bg_bottom)


func add_player(pid: int, color_id: int, player_name: String, is_local: bool) -> Player:
	var p := Player.new()
	_players_root.add_child(p)
	p.setup(pid, color_id, player_name, is_local)
	p.landed.connect(_on_player_landed)
	p.jumped.connect(_on_player_jumped)
	players[pid] = p
	inputs[pid] = PlayerInput.new()
	if is_local:
		local_pid = pid
		camera.target = p
	elif not Settings.remote_blob_shadows():
		p.stickman.shadow_enabled = false
	return p


func remove_player(pid: int) -> void:
	if players.has(pid):
		(players[pid] as Player).queue_free()
		players.erase(pid)
		inputs.erase(pid)


func get_player(pid: int) -> Player:
	return players.get(pid) as Player


func local_player() -> Player:
	return get_player(local_pid)


func set_input(pid: int, inp: PlayerInput) -> void:
	if inputs.has(pid):
		(inputs[pid] as PlayerInput).copy_from(inp)


func alive_players() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in players.values():
		if p.alive:
			out.append(p)
	return out


func _physics_process(delta: float) -> void:
	if map == null:
		return
	if authority:
		_server_step(delta)


func _server_step(delta: float) -> void:
	sim_time += delta
	for m: MovingPlatform in map.movers:
		m.server_step(delta)
	for p: Player in players.values():
		if not p.alive:
			continue
		var inp: PlayerInput = inputs[p.pid]
		var edges: Dictionary = p.consume_edges(inp)
		if frozen:
			var idle := PlayerInput.new()
			p.simulate_movement(idle, false, delta, map)
		else:
			p.simulate_movement(inp, edges["jump"], delta, map)
		_check_kill_line(p)


func _check_kill_line(p: Player) -> void:
	if p.global_position.y < map.kill_line_y():
		kill_player(p, -1, GameConfig.Cause.FALL)


func kill_player(p: Player, killer: int, cause: int) -> void:
	if not p.alive:
		return
	p.alive = false
	p.hp = 0
	p.velocity = Vector3.ZERO
	p.collision_layer = 0
	p.stickman.play(Stickman.Anim.DEATH)
	player_died.emit(p.pid, killer, cause)


func _process(delta: float) -> void:
	for p: Player in players.values():
		p.update_visuals(delta)


func _on_player_landed(p: Player) -> void:
	p.stickman.play(Stickman.Anim.LAND)
	AudioManager.play_at("land", p.global_position, 1.0, -6.0)


func _on_player_jumped(p: Player, double: bool) -> void:
	if double:
		p.stickman.play(Stickman.Anim.DOUBLE_JUMP)
		AudioManager.play_at("double_jump", p.global_position)
	else:
		AudioManager.play_at("jump", p.global_position)
