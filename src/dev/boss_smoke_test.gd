extends Node
## Boss/pattern gate (Phase 5) — run headless:
##   godot --headless res://scenes/dev/boss_smoke_test.tscn
## Part A (pure): BossCatalog composition — cycling, deterministic remixing
## (later cycles borrow patterns from other bosses), interval tightening,
## hp growth, pattern cap.
## Part B (runtime): real run scene — boss spawns from data, executes its
## pattern modules (enemy projectiles appear), projectiles hurt the player,
## boss death ends the run with victory + unlock.
## Exits 0 on PASS, 1 on FAIL. NOTE: resets the local save file.

const STEP_TIMEOUT_FRAMES := 3600

var _failures: PackedStringArray = []
var _events: PackedStringArray = []


func _ready() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var placeholder := Node.new()
	placeholder.name = "TestPlaceholderScene"
	get_tree().root.add_child(placeholder)
	get_tree().set_current_scene(placeholder)
	Engine.time_scale = 3.0
	_run()


func _run() -> void:
	_test_composition()
	await _test_runtime()
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("BOSS TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("BOSS TEST: FAILED (%d)" % _failures.size())
	SaveService.reset_to_defaults()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures.append(name)


# ---------------------------------------------------------------------------
# Part A: composition rule
# ---------------------------------------------------------------------------

func _test_composition() -> void:
	var bosses := BossCatalog.load_all()
	_check(bosses.size() >= 3, "at least 3 boss data files load (got %d)" % bosses.size())
	if bosses.is_empty():
		return
	var n := bosses.size()

	# Cycle 0: bosses appear in file order with their own patterns only.
	for level in range(1, n + 1):
		var composed := BossCatalog.compose_for_level(level, bosses)
		_check(composed["id"] == bosses[level - 1]["id"], "L%d uses boss %d in cycle order" % [level, level - 1])
		_check(composed["patterns"].size() == bosses[level - 1]["patterns"].size(), "L%d has no borrowed patterns in cycle 0" % level)

	# Cycle 1: same boss id, but with one borrowed pattern from the next boss.
	var base := BossCatalog.compose_for_level(1, bosses)
	var remixed := BossCatalog.compose_for_level(1 + n, bosses)
	_check(remixed["id"] == base["id"], "cycle 1 keeps the boss identity")
	_check(remixed["patterns"].size() == base["patterns"].size() + 1, "cycle 1 borrows exactly one pattern")
	if remixed["patterns"].size() > base["patterns"].size():
		var borrowed: Dictionary = remixed["patterns"].back()
		_check(borrowed.has("_borrowed_from") and borrowed["_borrowed_from"] == bosses[1]["id"], "borrowed pattern credits its donor boss")

	# Cycle 1: intervals tighten, hp grows.
	var base_interval := float(base["patterns"][0].get("interval", 0.0))
	var remixed_interval := float(remixed["patterns"][0].get("interval", 0.0))
	_check(remixed_interval < base_interval, "cycle 1 tightens pattern intervals")
	_check(float(remixed.get("hp_mult", 1.0)) > float(base.get("hp_mult", 1.0)), "cycle 1 grows boss hp")

	# Determinism + pattern cap far into the endless curve.
	var deep_a := BossCatalog.compose_for_level(1 + n * 30, bosses)
	var deep_b := BossCatalog.compose_for_level(1 + n * 30, bosses)
	_check(str(deep_a) == str(deep_b), "composition is deterministic")
	_check(deep_a["patterns"].size() <= BossCatalog.MAX_PATTERNS, "pattern count capped")

	# Every referenced enemy_base and pattern type must be valid.
	var enemy_ids := EnemyCatalog.load_all().map(func(e: Dictionary) -> String: return str(e["id"]))
	var known_patterns := ["radial_burst", "aimed_volley", "charge_dash", "summon_minions"]
	for boss in bosses:
		_check(enemy_ids.has(str(boss.get("enemy_base", ""))), "%s enemy_base exists" % boss["id"])
		for pattern in boss.get("patterns", []):
			_check(known_patterns.has(str(pattern.get("type", ""))), "%s pattern type '%s' is code-backed" % [boss["id"], pattern.get("type", "")])


# ---------------------------------------------------------------------------
# Part B: runtime
# ---------------------------------------------------------------------------

func _test_runtime() -> void:
	var tree := get_tree()
	SaveService.reset_to_defaults()
	for signal_name in ["boss_spawned", "boss_defeated", "player_hit", "level_unlocked"]:
		EventBus.connect(signal_name, _recorder(signal_name))

	await tree.create_timer(0.5).timeout
	SceneManager.change_scene("res://scenes/run/run.tscn", {"speed": 4.0, "wait_time": 0.05})
	if not await _wait(func() -> bool: return tree.current_scene != null and tree.current_scene.name == "Run" and not SceneManager.is_transitioning, "run scene loads"):
		return
	var run := tree.current_scene
	var horde: HordeSystem = run.get_node("Horde")
	var player: Node3D = run.get_node("Player")
	var stats: PlayerStats = run._stats

	# Keep the player alive through the whole boss verification, and push
	# the XP threshold out of reach so level-up menus can't pause the tree
	# mid-test.
	stats.max_hearts = 99
	stats.hearts = 99
	stats.level = 99

	# Force the boss phase immediately.
	run._survival_remaining = 0.05
	if not await _wait(func() -> bool: return "boss_spawned" in _events and horde.has_boss(), "boss spawns from data"):
		return
	_check(horde.boss_name() == "boss_yes_king", "level 1 boss is first in cycle (got %s)" % horde.boss_name())
	_check(horde._boss_patterns.size() == 2, "boss carries its 2 data patterns")

	# Pattern modules execute: enemy projectiles appear.
	if not await _wait(func() -> bool: return horde._eproj_count > 0, "boss patterns fire enemy projectiles"):
		return

	# Enemy projectiles hurt the player: stand still near the boss.
	# (Boss made unkillable during this check so the run can't end early.)
	horde.debug_set_boss_hp(1000000.0)
	var hearts_before := stats.hearts
	horde.grant_player_iframes(0.0)
	var boss_pos: Vector2 = horde.boss_position()
	# Offset TOWARD the arena center — the boss can spawn clamped at the
	# arena edge, and an outward offset would strand the player outside the
	# walls where nothing can reach him.
	var inward := (Vector2.ZERO - boss_pos).normalized() if boss_pos.length() > 0.1 else Vector2.RIGHT
	var stand := boss_pos + inward * 3.0
	player.global_position = Vector3(stand.x, 0, stand.y)
	if not await _wait(func() -> bool: return stats.hearts < hearts_before, "enemy projectiles damage the player"):
		printerr("DIAG: events=%s hp=%.1f/%.1f boss=%s eproj=%d paused=%s scene=%s iframe=%.2f" % [
			str(_events), float(stats.hearts), float(hearts_before), str(horde.has_boss()) if is_instance_valid(horde) else "freed",
			horde._eproj_count if is_instance_valid(horde) else -1,
			str(tree.paused), tree.current_scene.name if tree.current_scene else "none",
			horde._player_iframe if is_instance_valid(horde) else -1.0,
		])
		return

	# Kill the boss → victory + unlock.
	boss_pos = horde.boss_position()
	inward = (Vector2.ZERO - boss_pos).normalized() if boss_pos.length() > 0.1 else Vector2.RIGHT
	stand = boss_pos + inward * 1.5
	player.global_position = Vector3(stand.x, 0, stand.y)
	horde.debug_set_boss_hp(0.5)
	if not await _wait(func() -> bool: return "boss_defeated" in _events, "boss killed"):
		return
	if not await _wait(func() -> bool: return tree.current_scene != null and tree.current_scene.name == "Hub" and not SceneManager.is_transitioning, "victory returns to hub"):
		return
	_check("level_unlocked" in _events, "level unlock emitted")
	_check(int(SaveService.get_value("progress.highest_level_unlocked", 1)) == 2, "level 2 persisted")


func _recorder(signal_name: String) -> Callable:
	return func(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
		if not (signal_name in _events):
			_events.append(signal_name)


func _wait(predicate: Callable, name: String) -> bool:
	for i in range(STEP_TIMEOUT_FRAMES):
		if predicate.call():
			return true
		await get_tree().process_frame
	_failures.append("timed out: %s" % name)
	return false
