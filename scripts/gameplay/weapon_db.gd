class_name WeaponDB
extends RefCounted
## Access to WeaponData / ItemData resources by id.

const PUNCH_ID := 0

static var _weapons: Dictionary = {}
static var _items: Dictionary = {}


static func weapon(id: int) -> WeaponData:
	if _weapons.is_empty():
		for key: String in ["punch", "pistol", "smg", "shotgun", "sniper", "rocket_launcher", "grenades"]:
			var w: WeaponData = load("res://data/weapons/%s.tres" % key)
			_weapons[w.id] = w
	return _weapons.get(id) as WeaponData


static func item(id: int) -> ItemData:
	if _items.is_empty():
		for key: String in ["health_pack", "armor"]:
			var it: ItemData = load("res://data/items/%s.tres" % key)
			_items[it.id] = it
	return _items.get(id) as ItemData


## Weapon spawn weights (§7.3): id -> weight.
static func weapon_weights() -> Dictionary:
	var d: Dictionary = {}
	for id: int in range(1, 7):
		d[id] = weapon(id).spawn_weight
	return d


## Item spawn weights (§7.4): id -> weight.
static func item_weights() -> Dictionary:
	return {GameConfig.ItemId.HEALTH: item(GameConfig.ItemId.HEALTH).spawn_weight,
			GameConfig.ItemId.ARMOR: item(GameConfig.ItemId.ARMOR).spawn_weight}
