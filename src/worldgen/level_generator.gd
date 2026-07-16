class_name LevelGenerator
extends RefCounted
## Bridge to the Rust level generator (LevelGeneratorRs in addons/rust/).
## Theme loading (JSON discovery + sorting) stays in GDScript since it's not
## performance-critical. Generation is delegated to the Rust extension.

const MIN_REACHABLE_RATIO := 0.93

static func generate(level: int, theme: Dictionary) -> Dictionary:
	if ClassDB.class_exists("LevelGeneratorRs"):
		return ClassDB.instantiate("LevelGeneratorRs").generate(level, theme)
	push_error("LevelGenerator: LevelGeneratorRs not available")
	return {"ok": false, "level": level, "theme_id": str(theme.get("id", "?")), "arena_size": Vector2.ZERO, "props": [], "walkable_points": PackedVector3Array(), "reachable_ratio": 0.0, "player_spawn": Vector3.ZERO, "attempts": 0}

static func load_themes() -> Array:
	var themes: Array = []
	for path in JsonData.list_files("res://data/levels", "json"):
		var theme: Variant = JsonData.load_json(path)
		if theme is Dictionary and theme.has("generation"):
			themes.append(theme)
	themes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(a.get("order", 9999))
		var ob := int(b.get("order", 9999))
		if oa != ob:
			return oa < ob
		return str(a.get("id", "")) < str(b.get("id", "")))
	return themes

static func theme_for_level(level: int, themes: Array) -> Dictionary:
	if themes.is_empty():
		return {}
	return themes[(level - 1) % themes.size()]
