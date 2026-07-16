extends Node
## Worldgen gate (Phase 3) — run headless:
##   godot --headless res://scenes/dev/worldgen_smoke_test.tscn
## Validates across many levels and every theme/algorithm:
##  - generation succeeds within attempt budget,
##  - dodge-ability: reachable ratio >= threshold, ample walkable space,
##  - clear player spawn, props respect arena bounds,
##  - determinism (same level → identical layout),
##  - mechanical variation (different levels → different layouts).
## Exits 0 on PASS, 1 on FAIL.

const LEVELS_TO_TEST := 24

var _failures: PackedStringArray = []


func _ready() -> void:
	await get_tree().process_frame
	_run_tests()
	if _failures.is_empty():
		print("WORLDGEN TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("WORLDGEN TEST: FAILED (%d)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures.append(name)


func _generate(level: int, theme: Dictionary) -> Dictionary:
	if not ClassDB.class_exists("LevelGeneratorRs"):
		return {"ok": false}
	return ClassDB.instantiate("LevelGeneratorRs").generate(level, theme)


func _load_themes() -> Array:
	var themes: Array = []
	for path in JsonData.list_files("res://data/levels", "json"):
		var t: Variant = JsonData.load_json(path)
		if t is Dictionary and t.has("generation"):
			themes.append(t)
	themes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(a.get("order", 9999))
		var ob := int(b.get("order", 9999))
		if oa != ob:
			return oa < ob
		return str(a.get("id", "")) < str(b.get("id", "")))
	return themes


func _run_tests() -> void:
	var MIN_REACHABLE_RATIO := 0.93
	var themes: Array = _load_themes()
	_check(themes.size() >= 4, "at least 4 theme files load (got %d)" % themes.size())

	var algorithms_seen: Dictionary = {}
	for level in range(1, LEVELS_TO_TEST + 1):
		var theme: Dictionary = {}
		if not themes.is_empty():
			theme = themes[(level - 1) % themes.size()]
		algorithms_seen[str(theme.get("generation", {}).get("algorithm", "?"))] = true
		var tag := "L%d/%s" % [level, theme.get("id", "?")]
		var layout := _generate(level, theme)

		_check(layout["ok"], "%s: generation validated (ratio %.3f, attempts %d)" % [tag, layout["reachable_ratio"], layout["attempts"]])
		_check(layout["reachable_ratio"] >= MIN_REACHABLE_RATIO, "%s: reachable ratio %.3f" % [tag, layout["reachable_ratio"]])
		_check(layout["walkable_points"].size() >= 200, "%s: ample walkable space (%d cells)" % [tag, layout["walkable_points"].size()])
		_check(layout["props"].size() > 0, "%s: has props" % tag)

		var spawn_clear := float(theme["generation"].get("spawn_clear_radius", 4.5))
		var arena: Vector2 = layout["arena_size"]
		var half := arena * 0.5
		for prop in layout["props"]:
			var pos := Vector2(float(prop["pos"][0]), float(prop["pos"][1]))
			if pos.length() < spawn_clear:
				_failures.append("%s: prop inside spawn clearing at %s" % [tag, pos])
			if absf(pos.x) > half.x - 1.0 or absf(pos.y) > half.y - 1.0:
				_failures.append("%s: prop out of bounds at %s (arena %s)" % [tag, pos, arena])

		var layout2 := _generate(level, theme)
		var same: bool = layout2["props"].size() == layout["props"].size()
		if same and layout["props"].size() > 0:
			same = str(layout["props"][0]) == str(layout2["props"][0]) and str(layout["props"].back()) == str(layout2["props"].back())
		_check(same, "%s: deterministic layout" % tag)

	_check(algorithms_seen.size() >= 4, "all 4 algorithms exercised (saw %s)" % str(algorithms_seen.keys()))

	var theme0: Dictionary = {}
	if not themes.is_empty():
		theme0 = themes[0]
	var a := _generate(1, theme0)
	var b := _generate(1 + themes.size(), theme0)
	var differs: bool = a["props"].size() != b["props"].size() or (a["props"].size() > 0 and str(a["props"][0]) != str(b["props"][0]))
	_check(differs, "levels on the same theme produce different layouts")
