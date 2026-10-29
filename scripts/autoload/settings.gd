extends Node
## Persistent settings (§9.9), stored in user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

enum Quality { LOW = 0, MEDIUM = 1, HIGH = 2 }

## HUD elements that can be toggled (§9.6).
const HUD_ELEMENTS: PackedStringArray = [
	"health", "weapon", "round", "timer", "alive", "scoreboard", "kill_feed",
	"offscreen", "ping", "fps", "damage_numbers", "countdown",
]
const HUD_LABELS: Dictionary = {
	"health": "HP / Armor bars",
	"weapon": "Weapon + ammo",
	"round": "Round counter",
	"timer": "Round timer",
	"alive": "Alive counter",
	"scoreboard": "Mini scoreboard",
	"kill_feed": "Kill feed",
	"offscreen": "Off-screen indicators",
	"ping": "Ping",
	"fps": "FPS counter",
	"damage_numbers": "Damage numbers",
	"countdown": "Countdown",
}

var player_name: String = ""
var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var joystick_sensitivity: float = 1.0
var vibration: bool = true
var quality: int = Quality.MEDIUM
var hud_scale: float = 1.0
var hud: Dictionary = {}


func _ready() -> void:
	reset_to_defaults(false)
	load_settings()


func default_hud() -> Dictionary:
	var d: Dictionary = {}
	for e: String in HUD_ELEMENTS:
		d[e] = e != "fps"  # FPS counter off by default (§9.6)
	return d


func reset_to_defaults(keep_name: bool = true) -> void:
	if not keep_name:
		player_name = ""
	master_volume = 1.0
	music_volume = 1.0
	sfx_volume = 1.0
	joystick_sensitivity = 1.0
	vibration = true
	quality = Quality.MEDIUM
	hud_scale = 1.0
	hud = default_hud()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = str(cfg.get_value("player", "name", player_name))
	if not Rules.is_valid_name(player_name):
		player_name = ""
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	joystick_sensitivity = clampf(float(cfg.get_value("controls", "sensitivity", joystick_sensitivity)), 0.5, 1.5)
	vibration = bool(cfg.get_value("controls", "vibration", vibration))
	quality = clampi(int(cfg.get_value("graphics", "quality", quality)), Quality.LOW, Quality.HIGH)
	hud_scale = clampf(float(cfg.get_value("hud", "scale", hud_scale)), 0.8, 1.2)
	for e: String in HUD_ELEMENTS:
		hud[e] = bool(cfg.get_value("hud", e, hud[e]))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "sensitivity", joystick_sensitivity)
	cfg.set_value("controls", "vibration", vibration)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("hud", "scale", hud_scale)
	for e: String in HUD_ELEMENTS:
		cfg.set_value("hud", e, hud[e])
	cfg.save(PATH)


## Call after changing any value: persists and notifies listeners.
func apply() -> void:
	save_settings()
	changed.emit()


func hud_enabled(element: String) -> bool:
	return bool(hud.get(element, true))


func has_player_name() -> bool:
	return Rules.is_valid_name(player_name)


# --- Quality preset helpers (§9.9) ---

func render_scale() -> float:
	return 0.75 if quality == Quality.LOW else 1.0


func particle_factor() -> float:
	match quality:
		Quality.LOW:
			return 0.3
		Quality.MEDIUM:
			return 0.6
	return 1.0


func background_decorations() -> bool:
	return quality != Quality.LOW


func parallax_enabled() -> bool:
	return quality == Quality.HIGH


func remote_blob_shadows() -> bool:
	return quality != Quality.LOW
