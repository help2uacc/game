class_name KillCredit
extends RefCounted
## Tracks the last enemy attacker of each player for kill credit (§4.3).

const NONE := -1

## victim id -> { "attacker": int, "time": float }
var _last_enemy: Dictionary = {}


func reset() -> void:
	_last_enemy.clear()


func forget(victim: int) -> void:
	_last_enemy.erase(victim)


## Records damage. Self-damage is not recorded as an enemy attack.
func record_damage(victim: int, attacker: int, now: float) -> void:
	if attacker == NONE or attacker == victim:
		return
	_last_enemy[victim] = {"attacker": attacker, "time": now}


func last_enemy_attacker(victim: int, now: float) -> int:
	if not _last_enemy.has(victim):
		return NONE
	var entry: Dictionary = _last_enemy[victim]
	if now - float(entry["time"]) <= GameConfig.KILL_CREDIT_WINDOW:
		return int(entry["attacker"])
	return NONE


## Resolves who gets the kill. `lethal_attacker` is the player that dealt the
## lethal damage (NONE for environmental deaths). Never credits the victim.
func resolve(victim: int, lethal_attacker: int, now: float) -> int:
	if lethal_attacker != NONE and lethal_attacker != victim:
		return lethal_attacker
	return last_enemy_attacker(victim, now)
