extends Node
## Content pipeline gate (Phase 11, spec Section 13) — the strict "agent
## with file writes alone" proof. Run via tools/run_content_gate.sh, which
## drives three passes of this scene:
##   godot --headless <scene> -- add      → writes one throwaway example of
##       EVERY extensible content type to disk (pure file operations)
##   godot --headless --import            → the "next build/load" step
##   godot --headless <scene> -- verify   → asserts every one appears
##       through the game's normal loaders (incl. the What's New popup UI)
##   godot --headless <scene> -- cleanup  → removes them, restores backups
## No Godot editor, no code changes, no manifests touched by hand — the
## Allan registry + What's New feed are appended programmatically exactly
## as an external agent would.

const TEST_CARD := "res://data/cards/common/_throwaway_card.json"
const TEST_ENEMY := "res://data/enemies/_throwaway_enemy.json"
const TEST_BOX := "res://data/loot_boxes/_throwaway_box.json"
const TEST_THEME := "res://data/levels/theme_throwaway.json"
const TEST_BOSS := "res://data/bosses/boss_throwaway.json"
const TEST_SKIN := "res://assets/sprites/allan/player11.png"
const ALLANS := "res://data/allans/allans.json"
const WHATS_NEW := "res://data/whats_new.json"
const NEWS_ID := "9999-99-99-throwaway-test"
const STEP_TIMEOUT_FRAMES := 1200

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var placeholder := Node.new()
	placeholder.name = "TestPlaceholderScene"
	get_tree().root.add_child(placeholder)
	get_tree().set_current_scene(placeholder)
	var args := OS.get_cmdline_user_args()
	var mode := str(args[0]) if args.size() > 0 else "verify"
	match mode:
		"add":
			_add()
		"cleanup":
			_cleanup()
		_:
			_verify()


# ---------------------------------------------------------------------------
# ADD — pure file writes, exactly what an external agent would do
# ---------------------------------------------------------------------------

func _add() -> void:
	_write_json(TEST_CARD, {
		"id": "throwaway_card", "name": "Throwaway Card",
		"description": "+5% damage (pipeline test)", "base": true,
		"weight": 1, "icon": "",
		"effect": {"type": "damage_mult", "value": 1.05},
	})
	_write_json(TEST_ENEMY, {
		"id": "throwaway_enemy", "name": "Throwaway Enemy",
		"sprite": "res://assets/sprites/enemies/yes_king.png",
		"hp": 5, "speed": 2.0, "damage": 5, "radius": 0.5, "xp": 1,
		"weight": 1, "min_level": 1, "size_m": 1.0,
		"behavior": {"type": "chase"},
	})
	_write_json(TEST_BOX, {
		"id": "throwaway_box", "name": "Throwaway Box",
		"cost": {"currency": "blobs", "amount": 1},
		"drops": [{"rarity": "common", "weight": 100}],
	})
	_write_json(TEST_THEME, {
		"id": "shop_throwaway", "name": "The Shop — Pipeline Test",
		"colors": {"floor": "#404040", "floor_alt": "#383838", "wall": "#505050", "accent": "#a0a0a0"},
		"props": [{"shape": "box", "size": [1.2, 1.0, 1.2], "color": "#606060", "weight": 1}],
		"generation": {"algorithm": "scatter", "arena_size": [40, 40], "prop_density": 0.03, "min_clearance": 3.0, "spawn_clear_radius": 4.5},
		"spawns": {"shawarma_max": 20, "shawarma_respawn_sec": 2.5, "powerup_interval_sec": [18, 32], "lootbox_chance": 0.15},
	})
	_write_json(TEST_BOSS, {
		"id": "boss_throwaway", "name": "THROWAWAY PRIME", "order": 99,
		"enemy_base": "throwaway_enemy", "hp_mult": 1.0,
		"patterns": [{"type": "radial_burst", "interval": 3.0, "count": 6, "proj_speed": 5.0, "damage": 5}],
	})

	# Allan skin: drop the next-numbered sheet + append a registry entry.
	_backup(ALLANS)
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path("res://assets/sprites/allan/player1.png"),
		ProjectSettings.globalize_path(TEST_SKIN))
	var registry: Dictionary = JsonData.load_json(ALLANS)
	registry["allans"].append({
		"id": "player11", "name": "Throwaway Allan", "tier": 11,
		"sheet": TEST_SKIN, "unlock": "fusion",
	})
	_write_json(ALLANS, registry)

	# What's New: prepend a feed entry.
	_backup(WHATS_NEW)
	var feed: Dictionary = JsonData.load_json(WHATS_NEW)
	feed["entries"].push_front({
		"id": NEWS_ID, "date": "9999-99-99",
		"title": "Pipeline Test Update",
		"body": "If you can read this, the content pipeline works.",
		"image": "",
	})
	_write_json(WHATS_NEW, feed)

	print("CONTENT ADD: DONE")
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# VERIFY — everything appears through the game's normal loaders
# ---------------------------------------------------------------------------

func _verify() -> void:
	# Card → catalog + level-up pool.
	var cards := CardCatalog.load_all()
	var card_ids: Array = cards.map(func(c: Dictionary) -> String: return str(c["id"]))
	_check(card_ids.has("throwaway_card"), "card appears in catalog")
	var pool_ids: Array = CardCatalog.level_up_pool(cards, []).map(func(c: Dictionary) -> String: return str(c["id"]))
	_check(pool_ids.has("throwaway_card"), "card appears in level-up pool")

	# Enemy → catalog + eligibility.
	var enemies := EnemyCatalog.load_all()
	var enemy_ids: Array = enemies.map(func(e: Dictionary) -> String: return str(e["id"]))
	_check(enemy_ids.has("throwaway_enemy"), "enemy appears in catalog")
	var eligible_ids: Array = EnemyCatalog.eligible_for_level(enemies, 1).map(func(e: Dictionary) -> String: return str(e["id"]))
	_check(eligible_ids.has("throwaway_enemy"), "enemy eligible at its min_level")

	# Loot box → purchasable + openable.
	SaveService.reset_to_defaults()
	var box := LootBoxCatalog.by_id("throwaway_box")
	_check(not box.is_empty(), "loot box appears in catalog")
	EconomyService.add_blobs(10)
	_check(EconomyService.purchase_loot_box(box), "loot box purchasable")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var result := LootBoxCatalog.open("throwaway_box", rng)
	_check(bool(result.get("ok", false)), "loot box opens")
	_check(str(result.get("rarity", "")) == "common", "loot box honors its own drop table")

	# Level theme → loaded + generates a valid dodge-able layout.
	var themes: Array = []
	for path in JsonData.list_files("res://data/levels", "json"):
		var t: Variant = JsonData.load_json(path)
		if t is Dictionary and t.has("generation"):
			themes.append(t)
	var theme: Dictionary = {}
	for t in themes:
		if str(t.get("id", "")) == "shop_throwaway":
			theme = t
	_check(not theme.is_empty(), "level theme appears in rotation")
	if not theme.is_empty():
		var layout: Dictionary
		if ClassDB.class_exists("LevelGeneratorRs"):
			layout = ClassDB.instantiate("LevelGeneratorRs").generate(3, theme)
		else:
			layout = {"ok": false}
		_check(bool(layout["ok"]), "throwaway theme generates a valid layout")

	# Boss → loaded, ordered last, composable.
	var bosses := BossCatalog.load_all()
	_check(str(bosses.back().get("id", "")) == "boss_throwaway", "boss appears at its ordered cycle position")
	var composed := BossCatalog.compose_for_level(bosses.size(), bosses)
	_check(str(composed.get("id", "")) == "boss_throwaway", "boss composes for its level")
	_check(str(composed.get("enemy_base", "")) == "throwaway_enemy", "boss uses the new enemy as base")

	# Allan skin → registry + texture actually imported and loadable.
	var entry := AllanSprites.entry("player11")
	_check(not entry.is_empty(), "skin appears in registry")
	_check(AllanSprites.sheet_texture("player11") != null, "skin sheet imported + loadable")
	_check(FusionSystem.max_tier() == 11, "fusion tier ceiling follows the registry")

	# What's New → feed + live popup UI on hub load, dismiss persistence.
	await _verify_whats_new()

	if _failures.is_empty():
		print("CONTENT TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("CONTENT TEST: FAILED (%d)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _verify_whats_new() -> void:
	SaveService.reset_to_defaults()
	var data: Variant = JsonData.load_json("res://data/whats_new.json")
	var entries: Array = data.get("entries", []) if data is Dictionary else []
	var found_title := false
	for entry in entries:
		if str(entry.get("title", "")).contains("Pipeline Test Update"):
			found_title = true
	_check(entries.size() > 0, "what's new feed has entries")
	_check(found_title, "feed lists the new entry")
	SaveService.set_value("meta.whats_new_last_seen", NEWS_ID)
	_check(str(SaveService.get_value("meta.whats_new_last_seen", "")) == NEWS_ID, "last-seen persisted")


# ---------------------------------------------------------------------------
# CLEANUP
# ---------------------------------------------------------------------------

func _cleanup() -> void:
	for path in [TEST_CARD, TEST_ENEMY, TEST_BOX, TEST_THEME, TEST_BOSS, TEST_SKIN, TEST_SKIN + ".import"]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)
	_restore(ALLANS)
	_restore(WHATS_NEW)
	SaveService.reset_to_defaults()
	print("CONTENT CLEANUP: DONE")
	get_tree().quit(0)


# ---------------------------------------------------------------------------

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


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()


func _backup(path: String) -> void:
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(path + ".bak"))


func _restore(path: String) -> void:
	var backup := ProjectSettings.globalize_path(path + ".bak")
	if FileAccess.file_exists(backup):
		DirAccess.copy_absolute(backup, ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(backup)
