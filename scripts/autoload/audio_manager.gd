extends Node
## Audio playback (PRD §11.5): buses Master -> Music, SFX; UI sounds via
## AudioStreamPlayer, in-world sounds via AudioStreamPlayer3D; at most 4
## simultaneous voices of the same SFX.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const MAX_VOICES_PER_SFX := 4
const POOL_2D := 12
const POOL_3D := 24
const MUSIC_FADE := 0.6

var _streams: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
## AudioStreamPlayer(3D) -> sfx name currently playing
var _voice_name: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current: String = ""
var _music_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	for i: int in range(POOL_2D):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool_2d.append(p)
	for i: int in range(POOL_3D):
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.unit_size = 18.0
		p3.max_distance = 60.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_pool_3d.append(p3)
	_music_a = AudioStreamPlayer.new()
	_music_a.bus = "Music"
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.bus = "Music"
	add_child(_music_b)
	Settings.changed.connect(apply_volumes)
	apply_volumes()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001))


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), _db(Settings.master_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _db(Settings.music_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), _db(Settings.sfx_volume))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), Settings.master_volume <= 0.001)


func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_streams[path] = s
	return s


func _active_voices(sfx_name: String) -> int:
	var n: int = 0
	for p: Node in _voice_name.keys():
		if _voice_name[p] == sfx_name and _is_playing(p):
			n += 1
	return n


## Max 4 simultaneous voices per SFX (§11.5): at the limit the oldest voice
## of that SFX is stopped so the newest shot is always heard (v1.3).
func _steal_if_full(sfx_name: String) -> void:
	if _active_voices(sfx_name) < MAX_VOICES_PER_SFX:
		return
	var oldest: Node = null
	var best_pos: float = -1.0
	for p: Node in _voice_name.keys():
		if _voice_name[p] != sfx_name or not _is_playing(p):
			continue
		var pos: float = (p as AudioStreamPlayer).get_playback_position() if p is AudioStreamPlayer \
				else (p as AudioStreamPlayer3D).get_playback_position()
		if pos > best_pos:
			best_pos = pos
			oldest = p
	if oldest is AudioStreamPlayer:
		(oldest as AudioStreamPlayer).stop()
	elif oldest is AudioStreamPlayer3D:
		(oldest as AudioStreamPlayer3D).stop()


func _is_playing(p: Node) -> bool:
	if p is AudioStreamPlayer:
		return (p as AudioStreamPlayer).playing
	return (p as AudioStreamPlayer3D).playing


## UI / non-positional sound.
func play_ui(sfx_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _stream(SFX_DIR + sfx_name + ".wav")
	if stream == null:
		return
	_steal_if_full(sfx_name)
	for p: AudioStreamPlayer in _pool_2d:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = pitch
			p.volume_db = volume_db
			p.play()
			_voice_name[p] = sfx_name
			return


## Positional in-world sound (distance attenuation).
func play_at(sfx_name: String, pos: Vector3, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _stream(SFX_DIR + sfx_name + ".wav")
	if stream == null:
		return
	_steal_if_full(sfx_name)
	for p: AudioStreamPlayer3D in _pool_3d:
		if not p.playing:
			p.stream = stream
			p.global_position = pos
			p.pitch_scale = pitch
			p.volume_db = volume_db
			p.play()
			_voice_name[p] = sfx_name
			return


func play_music(track: String) -> void:
	if track == _music_current:
		return
	_music_current = track
	var stream: AudioStream = _stream(MUSIC_DIR + track + ".wav") if not track.is_empty() else null
	if stream is AudioStreamWAV and track != "results_jingle":
		var wav: AudioStreamWAV = stream
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
	var old: AudioStreamPlayer = _music_a
	var new_player: AudioStreamPlayer = _music_b
	if _music_tween != null:
		_music_tween.kill()
	_music_a = new_player
	_music_b = old
	if old.playing:
		var fade_out: Tween = create_tween()
		fade_out.tween_property(old, "volume_db", -40.0, MUSIC_FADE)
		fade_out.tween_callback(old.stop)
	if stream != null:
		new_player.stream = stream
		new_player.volume_db = -40.0
		new_player.play()
		_music_tween = create_tween()
		_music_tween.tween_property(new_player, "volume_db", 0.0, MUSIC_FADE)


func stop_music() -> void:
	play_music("")


func vibrate(ms: int) -> void:
	if Settings.vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


## Stops everything and drops cached streams (shutdown / test cleanup).
func release_all() -> void:
	for p: AudioStreamPlayer in _pool_2d:
		p.stop()
		p.stream = null
	for p3: AudioStreamPlayer3D in _pool_3d:
		p3.stop()
		p3.stream = null
	for m: AudioStreamPlayer in [_music_a, _music_b]:
		m.stop()
		m.stream = null
	if _music_tween != null:
		_music_tween.kill()
	_music_current = ""
	_streams.clear()
	_voice_name.clear()
