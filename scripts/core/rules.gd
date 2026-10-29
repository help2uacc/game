class_name Rules
extends RefCounted
## Pure, side-effect free game rules (unit tested in tests/).


## Damage applies to armor first, the remainder to HP (§6.5).
## Returns Vector2i(new_hp, new_armor).
static func apply_damage(hp: int, armor: int, damage: int) -> Vector2i:
	if damage <= 0:
		return Vector2i(hp, armor)
	var absorbed: int = mini(armor, damage)
	var new_armor: int = armor - absorbed
	var new_hp: int = maxi(0, hp - (damage - absorbed))
	return Vector2i(new_hp, new_armor)


static func heal(hp: int, amount: int) -> int:
	return mini(GameConfig.MAX_HP, hp + amount)


static func add_armor(armor: int, amount: int) -> int:
	return mini(GameConfig.MAX_ARMOR, armor + amount)


## Rounds setting is clamped to 4–99 (§4.1).
static func clamp_rounds(rounds: int) -> int:
	return clampi(rounds, GameConfig.MIN_ROUNDS, GameConfig.MAX_ROUNDS)


## A round ends when <= 1 player is alive or the timer reaches 0 (§4.2).
static func should_round_end(alive_count: int, time_left: float) -> bool:
	return alive_count <= 1 or time_left <= 0.0


## Returns the ids with the highest value in `scores` (id -> int).
## One id = winner, several = DRAW (§4.1, §4.2).
static func top_scorers(scores: Dictionary) -> Array[int]:
	var best: int = -1
	var result: Array[int] = []
	for id: Variant in scores.keys():
		var value: int = int(scores[id])
		if value > best:
			best = value
			result.clear()
			result.append(int(id))
		elif value == best:
			result.append(int(id))
	result.sort()
	return result


static func is_draw(winners: Array[int]) -> bool:
	return winners.size() != 1


## First free colour id, or -1 if all are taken (§6.2).
static func first_free_color(taken: Array[int]) -> int:
	for c: int in range(Palette.COLOR_COUNT):
		if not taken.has(c):
			return c
	return -1


static func can_take_color(color_id: int, taken_by_others: Array[int]) -> bool:
	return color_id >= 0 and color_id < Palette.COLOR_COUNT and not taken_by_others.has(color_id)


## Player name: 1–12 chars, letters/digits/space/_/- (§9.2).
static func is_valid_name(player_name: String) -> bool:
	if player_name.length() < 1 or player_name.length() > 12:
		return false
	if player_name.strip_edges().is_empty():
		return false
	for i: int in range(player_name.length()):
		var ch: String = player_name[i]
		var code: int = ch.unicode_at(0)
		var ok: bool = (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
				or ch == " " or ch == "_" or ch == "-"
		if not ok:
			return false
	return true


## Removes invalid characters and truncates; falls back to `fallback`.
static func sanitize_name(player_name: String, fallback: String) -> String:
	var out: String = ""
	for i: int in range(player_name.length()):
		var ch: String = player_name[i]
		if is_valid_name(ch) or ch == " ":
			out += ch
		if out.length() >= 12:
			break
	if not is_valid_name(out):
		return fallback
	return out


static func default_player_name(rng: RandomNumberGenerator) -> String:
	return "Player%04d" % rng.randi_range(0, 9999)


## Picks a key from a weights dictionary (key -> weight).
static func weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var total: float = 0.0
	for k: Variant in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		return null
	var roll: float = rng.randf() * total
	for k: Variant in weights.keys():
		roll -= float(weights[k])
		if roll < 0.0:
			return k
	return weights.keys().back()


## Explosion damage with linear falloff from centre to edge value (§7.3).
static func falloff_damage(distance: float, radius: float, center_damage: float, edge_damage: float) -> int:
	if distance > radius:
		return 0
	var t: float = clampf(distance / radius, 0.0, 1.0)
	return int(round(lerpf(center_damage, edge_damage, t)))
