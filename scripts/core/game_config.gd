class_name GameConfig
extends RefCounted
## Gameplay constants taken verbatim from PRD.md. Weapon stats live in
## res://data/weapons/*.tres, item values in res://data/items/*.tres.

# --- Networking (§5) ---
const NET_PROTOCOL_VERSION := 1
const GAME_PORT := 47820
const DISCOVERY_PORT := 47821
const MAX_PLAYERS := 8
const MIN_PLAYERS := 2
const DISCOVERY_INTERVAL := 2.0
const DISCOVERY_HOST_TIMEOUT := 6.0
const CONNECT_TIMEOUT := 5.0
const RECONNECT_WINDOW := 60.0
const RECONNECT_RETRY_INTERVAL := 2.0
const SNAPSHOT_RATE := 30.0
const INTERP_DELAY := 0.1
const MAP_LOAD_TIMEOUT := 10.0
const PING_INTERVAL := 1.0

# --- Match & round (§4) ---
const DEFAULT_ROUNDS := 12
const MIN_ROUNDS := 4
const MAX_ROUNDS := 99
const ROUND_TIME := 300.0
const COUNTDOWN_TIME := 3.0
const ROUND_RESULTS_TIME := 6.0
const KILL_CREDIT_WINDOW := 5.0
const LOW_TIME_WARNING := 30.0

# --- Player (§6.4) ---
const MAX_HP := 100
const MAX_ARMOR := 50
const RUN_SPEED := 7.0
const GROUND_ACCEL := 60.0
const AIR_ACCEL := 35.0
const GRAVITY := 30.0
const MAX_FALL_SPEED := 25.0
const JUMP_VELOCITY := 11.0
const DOUBLE_JUMP_VELOCITY := 10.0
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.10
const KILL_LINE_OFFSET := 10.0
const KNOCKBACK_UP_FACTOR := 0.3
const KNOCKBACK_CONTROL := 0.3
const PLAYER_RADIUS := 0.3
const PLAYER_HEIGHT := 1.8
const CHEST_HEIGHT := 1.2
const DROP_DOWN_THRESHOLD := 0.6

# --- Combat (§7) ---
const PICKUP_RADIUS := 1.0
const THROW_SPEED := 14.0
const THROW_DAMAGE := 15
const THROW_KNOCKBACK := 6.0
const GROUND_WEAPON_DESPAWN := 30.0
const DESPAWN_BLINK_TIME := 3.0
const SELF_DAMAGE_FACTOR := 0.5

# --- Spawning (§7.5) ---
const START_WEAPONS := 3
const WEAPON_SPAWN_INTERVAL := 8.0
const MAX_GROUND_WEAPONS := 6
const FIRST_ITEM_TIME := 30.0
const ITEM_SPAWN_INTERVAL := 20.0
const MAX_GROUND_ITEMS := 2
const PICKUP_FREE_RADIUS := 1.5
const SPAWN_POP_TIME := 0.25

# --- Hazards (§10.1) ---
const SPIKE_DAMAGE := 34
const SPIKE_INVULNERABILITY := 0.5
const CRATE_HP := 30
const JUMP_PAD_VELOCITY := 20.0
const ONE_WAY_THICKNESS := 0.25

# --- Map limits (§10.1) ---
const MAP_MIN_WIDTH := 70
const MAP_MAX_WIDTH := 100
const MAP_MIN_HEIGHT := 30
const MAP_MAX_HEIGHT := 45
const MAP_MIN_SPAWNS := 8
const MAP_MIN_WEAPON_POINTS := 10
const MAP_MIN_ITEM_POINTS := 3
const SPAWN_FLOOR_MAX_DROP := 6

# --- Camera (§10.4) ---
const CAMERA_FOV := 40.0
const CAMERA_DISTANCE := 30.0
const CAMERA_TILT_DEG := -6.0
const CAMERA_LERP := 8.0
const CAMERA_LOOK_AHEAD := 2.0
const CAMERA_DEAD_ZONE_Y := 1.0
const CAMERA_MARGIN := 2.0

# --- Weapon ids ---
enum WeaponId { NONE = 0, PISTOL = 1, SMG = 2, SHOTGUN = 3, SNIPER = 4, ROCKET = 5, GRENADE = 6 }
const WEAPON_KEYS: PackedStringArray = ["none", "pistol", "smg", "shotgun", "sniper", "rocket_launcher", "grenades"]

# --- Item ids ---
enum ItemId { HEALTH = 0, ARMOR = 1 }
const ITEM_KEYS: PackedStringArray = ["health_pack", "armor"]

# --- Death / kill feed causes ---
enum Cause { PUNCH = 0, PISTOL = 1, SMG = 2, SHOTGUN = 3, SNIPER = 4, ROCKET = 5, GRENADE = 6, THROWN = 7, FALL = 8, LAVA = 9, SPIKES = 10, DISCONNECT = 11 }


static func is_environmental(cause: int) -> bool:
	return cause == Cause.FALL or cause == Cause.LAVA or cause == Cause.SPIKES or cause == Cause.DISCONNECT
