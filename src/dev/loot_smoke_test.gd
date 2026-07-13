extends Node
## Loot gate (Phase 8) — run headless:
##   godot --headless res://scenes/dev/loot_smoke_test.tscn
## Part A (pure): opening consumes inventory, seeded rolls respect the box's
## rarity table, cards bank into cards.owned with duplicate counts,
## card_unlocked fires exactly once per card, owned cards enter the
## level-up pool, victory + map-pickup box rewards.
## Part B (UI): shop OPEN button pulls a card and shows the reveal overlay.
## Exits 0 on PASS, 1 on FAIL. NOTE: resets the local save file.

const STEP_TIMEOUT_FRAMES := 1200
const PULLS := 60

var _failures: PackedStringArray = []
var _unlocks: PackedStringArray = []


func _ready() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var placeholder := Node.new()
	placeholder.name = "TestPlaceholderScene"
	get_tree().root.add_child(placeholder)
	get_tree().set_current_scene(placeholder)
	_run()


func _run() -> void:
	_test_pure()
	await _test_ui()
	if _failures.is_empty():
		print("LOOT TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("LOOT TEST: FAILED (%d)" % _failures.size())
	SaveService.reset_to_defaults()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures.append(name)


func _test_pure() -> void:
	SaveService.reset_to_defaults()
	EventBus.card_unlocked.connect(func(id: String) -> void: _unlocks.append(id))

	# Opening with none owned fails cleanly.
	var result := LootBoxCatalog.open("basic_box")
	_check(not bool(result["ok"]) and str(result["reason"]) == "none_owned", "opening with empty inventory fails")
	_check(not bool(LootBoxCatalog.open("no_such_box").get("ok", true)), "unknown box rejected")

	# Seeded bulk pulls: every roll honors the box's rarity table and every
	# pull lands in the owned pool.
	var box := LootBoxCatalog.by_id("basic_box")
	var allowed_rarities: Array = box["drops"].map(func(d: Dictionary) -> String: return str(d["rarity"]))
	EconomyService.add_loot_box("basic_box", PULLS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var rarities_seen: Dictionary = {}
	var total_cards := 0
	for i in range(PULLS):
		result = LootBoxCatalog.open("basic_box", rng)
		_check(bool(result["ok"]), "pull %d succeeds" % i)
		if not bool(result["ok"]):
			break
		var rarity := str(result["rarity"])
		if not allowed_rarities.has(rarity):
			_failures.append("pull rolled rarity outside the box table: %s" % rarity)
		rarities_seen[rarity] = int(rarities_seen.get(rarity, 0)) + 1
	_check(EconomyService.get_loot_box_count("basic_box") == 0, "all boxes consumed")
	_check(rarities_seen.size() >= 2, "multiple rarities appear across %d pulls" % PULLS)
	var owned: Dictionary = SaveService.get_value("cards.owned", {})
	for card_id in owned:
		total_cards += int(owned[card_id].get("count", 0))
	_check(total_cards == PULLS, "every pull banked a card (%d/%d)" % [total_cards, PULLS])

	# card_unlocked fired exactly once per distinct card.
	var distinct: Dictionary = {}
	for id in _unlocks:
		_check(not distinct.has(id), "card_unlocked fired twice for %s" % id)
		distinct[id] = true
	_check(distinct.size() == owned.size(), "one unlock signal per distinct card")

	# Owned non-base cards join the level-up pool.
	var catalog := CardCatalog.load_all()
	var pool := CardCatalog.level_up_pool(catalog, owned.keys())
	var pool_ids: Array = pool.map(func(c: Dictionary) -> String: return str(c["id"]))
	for card_id in owned:
		var card: Dictionary = {}
		for c in catalog:
			if str(c["id"]) == str(card_id):
				card = c
		if not card.is_empty() and not bool(card.get("base", false)):
			_check(pool_ids.has(str(card_id)), "owned loot card %s enters level-up pool" % card_id)

	# Victory reward: run_ended(victory) banks a box.
	var before := EconomyService.get_loot_box_count("basic_box")
	EventBus.run_ended.emit({"level": 1, "victory": true, "blobs_banked": 0, "duration_sec": 1.0, "reason": "boss_defeated"})
	_check(EconomyService.get_loot_box_count("basic_box") == before + 1, "victory grants a loot box")
	EventBus.run_ended.emit({"level": 1, "victory": false, "blobs_banked": 0, "duration_sec": 1.0, "reason": "ascend"})
	_check(EconomyService.get_loot_box_count("basic_box") == before + 1, "defeat grants nothing")

	# Map pickup: loot_box_collected banks the box.
	EventBus.loot_box_collected.emit("basic_box")
	_check(EconomyService.get_loot_box_count("basic_box") == before + 2, "map pickup banks a box")
	EventBus.loot_box_collected.emit("not_a_real_box")
	_check(EconomyService.get_loot_box_count("basic_box") == before + 2, "unknown pickup id ignored")

	# Premium box rolls only its own table (seeded).
	SaveService.reset_to_defaults()
	EconomyService.add_loot_box("premium_box", 20)
	var premium := LootBoxCatalog.by_id("premium_box")
	var premium_rarities: Array = premium["drops"].map(func(d: Dictionary) -> String: return str(d["rarity"]))
	rng.seed = 99
	for i in range(20):
		result = LootBoxCatalog.open("premium_box", rng)
		if bool(result["ok"]) and not premium_rarities.has(str(result["rarity"])):
			_failures.append("premium pull outside its table: %s" % result["rarity"])


func _test_ui() -> void:
	# The shop + chest-opening popup are now HTML/JS (web_ui/hub/shop +
	# web_ui/shared/chest), which can't render under --headless. This
	# drives the same UIBridge entry point the real "OPEN" button/message
	# reaches ("open_chest") to verify the GDScript-side contract.
	SaveService.reset_to_defaults()
	EconomyService.add_loot_box("basic_box", 1)

	var catalog := UIBridge.simulate_message_with_reply(JSON.stringify({"type": "request_shop_catalog"}))
	var boxes: Array = catalog.get("boxes", [])
	var basic_listed := boxes.any(func(b: Dictionary) -> bool: return str(b.get("id", "")) == "basic_box")
	_check(basic_listed, "shop catalog lists basic_box")

	var result := UIBridge.simulate_message_with_reply(JSON.stringify({"type": "open_chest", "box_id": "basic_box"}))
	_check(bool(result.get("ok", false)), "chest_opened reply reports ok")
	_check(EconomyService.get_loot_box_count("basic_box") == 0, "UI open consumed the box")
	_check(not (SaveService.get_value("cards.owned", {}) as Dictionary).is_empty(), "UI open banked a card")

	# Opening again with none owned fails cleanly through the same path.
	var empty_result := UIBridge.simulate_message_with_reply(JSON.stringify({"type": "open_chest", "box_id": "basic_box"}))
	_check(not bool(empty_result.get("ok", true)), "second open with no boxes left fails cleanly")


func _wait(predicate: Callable, name: String) -> bool:
	for i in range(STEP_TIMEOUT_FRAMES):
		if predicate.call():
			return true
		await get_tree().process_frame
	_failures.append("timed out: %s" % name)
	return false
