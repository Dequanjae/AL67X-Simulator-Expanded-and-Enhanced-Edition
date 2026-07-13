class_name EnemyCatalog
extends RefCounted
## Folder-scanned enemy definitions (spec Section 13): a new enemy is a new
## JSON file in data/enemies/ (stats + sprite + pattern refs) — code only
## needed for genuinely new attack-pattern modules.


static func load_all() -> Array:
	var enemies: Array = []
	for path in JsonData.list_files("res://data/enemies", "json"):
		var enemy: Variant = JsonData.load_json(path)
		if enemy is Dictionary and enemy.has("id"):
			enemies.append(enemy)
	return enemies


static func eligible_for_level(all_enemies: Array, level: int) -> Array:
	return all_enemies.filter(func(e: Dictionary) -> bool: return int(e.get("min_level", 1)) <= level)


static func xp_map(all_enemies: Array) -> Dictionary:
	var out: Dictionary = {}
	for enemy in all_enemies:
		out[str(enemy["id"])] = float(enemy.get("xp", 1))
	return out
