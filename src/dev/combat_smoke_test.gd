extends Node
## Combat gate (Phase 4) — run headless:
##   godot --headless res://scenes/dev/combat_smoke_test.tscn
## Exercises the full combat loop in the REAL run scene:
##  enemies spawn from the curve → auto-fire kills one (enemy_killed) →
##  forced level-up presents the 1-of-3 menu (paused) → choice applies a
##  stat effect and unpauses → real death (hp→0 via contact) freezes + shows
##  the death panel → ad-continue revives → timer forced to 0 → boss warning
##  → boss spawns → boss killed → level unlock + victory banking at hub.
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
	await _flow()
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("COMBAT TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("COMBAT TEST: FAILED (%d)" % _failures.size())
	SaveService.reset_to_defaults()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _flow() -> void:
	var tree := get_tree()
	SaveService.reset_to_defaults()
	for signal_name in ["boss_incoming", "boss_spawned", "boss_defeated", "enemy_killed", "player_died", "player_revived", "card_chosen", "level_unlocked"]:
		EventBus.connect(signal_name, _recorder(signal_name))

	await tree.create_timer(0.5).timeout
	SceneManager.change_scene("res://scenes/run/run.tscn", {"speed": 4.0, "wait_time": 0.05})
	if not await _wait(func() -> bool: return tree.current_scene != null and tree.current_scene.name == "Run" and not SceneManager.is_transitioning, "run scene loads"):
		return
	var run := tree.current_scene
	var horde: HordeSystem = run.get_node("Horde")
	var player: Node3D = run.get_node("Player")

	# 1. Enemies spawn from the curve.
	if not await _wait(func() -> bool: return horde.active_enemy_count() > 0, "enemies spawn"):
		return

	# 2. Auto-fire kills an enemy (enemies chase into attack range).
	if not await _wait(func() -> bool: return "enemy_killed" in _events, "auto-attack kills an enemy"):
		return

	# 3. Forced level-up → menu appears, tree pauses. Presentation moved to
	# HTML (web_ui/hud) which can't render under --headless; drive the
	# LevelUpController directly (same object the real HTML popup's
	# "card_choice" message reaches via WebViewHost.ipc_message).
	run.debug_grant_xp(999.0)
	var level_up: LevelUpController = run.get_node("LevelUpController")
	if not await _wait(func() -> bool: return tree.paused and not level_up._options.is_empty(), "level-up menu presents + pauses"):
		return
	var stats: PlayerStats = run._stats
	var damage_before := stats.effective_damage()
	var speed_before := stats.speed_mult
	var interval_before := stats.fire_interval
	var proj_before := stats.projectile_count
	var hearts_before := stats.max_hearts
	# May chain multiple pending level-ups; resolve them all.
	for i in range(64):
		if level_up._options.is_empty():
			break
		level_up._on_card_choice_message(str(level_up._options[0].get("id", "")))
		await tree.process_frame
	if not await _wait(func() -> bool: return not tree.paused, "menu closes + unpauses"):
		return
	_check("card_chosen" in _events, "card_chosen emitted")
	var changed := stats.effective_damage() != damage_before or stats.speed_mult != speed_before \
		or stats.fire_interval != interval_before or stats.projectile_count != proj_before \
		or stats.max_hearts != hearts_before
	_check(changed, "card effect changed a stat")

	# 4. Real death via contact damage: drop hp, stand on an enemy.
	stats.hearts = 1
	stats.shield = 0
	horde.grant_player_iframes(0.0)
	var enemy_pos := horde._nearest_enemy(Vector2(player.global_position.x, player.global_position.z), 999.0)
	if enemy_pos == Vector2.INF:
		_failures.append("no enemy available for death test")
		return
	player.global_position = Vector3(enemy_pos.x, 0, enemy_pos.y)
	# Death panel presentation also moved to HTML — the pause + player_died
	# event are the real, checkable contract.
	if not await _wait(func() -> bool: return "player_died" in _events and tree.paused, "death freezes + shows panel"):
		return

	# 5. Ad-continue revives (once per run). Drives the same ipc_message
	# path the real HTML button uses.
	run._on_web_ipc_message(JSON.stringify({"type": "ad_continue"}))
	if not await _wait(func() -> bool: return "player_revived" in _events and not tree.paused, "ad continue revives"):
		return
	_check(stats.hearts > 0, "revive restores hearts")

	# 6. Timer → boss phase → boss spawn → kill → victory.
	# Test-only: make the player effectively invincible so re-swarming
	# can't interrupt the boss verification.
	stats.max_hearts = 99
	stats.hearts = 99
	horde.grant_player_iframes(9999.0)
	run._survival_remaining = 0.05
	if not await _wait(func() -> bool: return "boss_incoming" in _events, "boss warning triggers at timer end"):
		return
	if not await _wait(func() -> bool: return "boss_spawned" in _events and horde.has_boss(), "boss spawns after warning"):
		return
	# Stand next to the boss (offset TOWARD arena center — edge spawns would
	# otherwise strand the player outside the walls) so it is the nearest
	# auto-fire target.
	var boss_pos: Vector2 = horde._types[horde._boss_type]["pos"][horde._boss_slot]
	var inward := (Vector2.ZERO - boss_pos).normalized() if boss_pos.length() > 0.1 else Vector2.RIGHT
	var stand := boss_pos + inward * 1.5
	player.global_position = Vector3(stand.x, 0, stand.y)
	horde.debug_set_boss_hp(0.5)
	if not await _wait(func() -> bool: return "boss_defeated" in _events, "boss killed by auto-fire"):
		return
	if not await _wait(func() -> bool: return tree.current_scene != null and tree.current_scene.name == "Hub" and not SceneManager.is_transitioning, "victory returns to hub"):
		return
	_check("level_unlocked" in _events, "level unlock emitted")
	_check(int(SaveService.get_value("progress.highest_level_unlocked", 1)) == 2, "level 2 persisted")


func _recorder(signal_name: String) -> Callable:
	return func(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
		if not (signal_name in _events):
			_events.append(signal_name)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures.append(name)


func _wait(predicate: Callable, name: String) -> bool:
	for i in range(STEP_TIMEOUT_FRAMES):
		if predicate.call():
			return true
		await get_tree().process_frame
	_failures.append("timed out: %s" % name)
	return false
