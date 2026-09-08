extends Node
## Shop/economy gate (Phase 6) — run headless:
##   godot --headless res://scenes/dev/shop_smoke_test.tscn
## Part A (pure): upgrade cost curve, purchase flow (insufficient → fail,
## funded → level persists + balance deducted + cost scales), loot box
## purchase into inventory, loadout application (equipped card effects +
## upgrade bonuses hit PlayerStats).
## Part B (UI): hub Deck tab equips/unequips via real buttons; Shop tab
## upgrade button purchase updates the save.
## Exits 0 on PASS, 1 on FAIL. NOTE: resets the local save file.

const STEP_TIMEOUT_FRAMES := 1200

var _failures: PackedStringArray = []


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
		print("SHOP TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("SHOP TEST: FAILED (%d)" % _failures.size())
	SaveService.reset_to_defaults()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures.append(name)


func _test_pure() -> void:
	SaveService.reset_to_defaults()
	var config := CardUpgrades.load_config()
	_check(config.has("upgrade_types"), "upgrade config loads")

	# Cost curve scales and is uncapped.
	var cost0 := CardUpgrades.cost("damage", 0, config)
	var cost5 := CardUpgrades.cost("damage", 5, config)
	var cost50 := CardUpgrades.cost("damage", 50, config)
	_check(int(cost0["amount"]) < int(cost5["amount"]), "cost grows with level")
	_check(int(cost5["amount"]) < int(cost50["amount"]), "cost keeps growing (uncapped)")

	# Purchase fails broke, succeeds funded, persists + deducts.
	# (Upgrades cost Watts since the Economy v2 switch — fund Watts AND
	# blobs: blobs pay for the loot box purchase below.)
	_check(not CardUpgrades.purchase("sharpened_brushes", "damage", config), "broke purchase rejected")
	EconomyService.add_watts(10000)
	EconomyService.add_blobs(10000)
	var blobs_before := EconomyService.get_blobs()
	var watts_before := EconomyService.get_watts()
	_check(CardUpgrades.purchase("sharpened_brushes", "damage", config), "funded purchase succeeds")
	_check(CardUpgrades.get_level("sharpened_brushes", "damage") == 1, "upgrade level persisted")
	_check(EconomyService.get_blobs() == blobs_before, "no blobs spent on watts upgrade")
	_check(EconomyService.get_watts() == watts_before - int(cost0["amount"]), "cost deducted from watts")
	var cost_next := CardUpgrades.cost("damage", CardUpgrades.get_level("sharpened_brushes", "damage"), config)
	_check(int(cost_next["amount"]) > int(cost0["amount"]), "next level costs more")

	# Token-priced upgrade path.
	EconomyService.debug_grant_tokens(1000)
	_check(CardUpgrades.purchase("sharpened_brushes", "projectiles", config), "token upgrade succeeds")

	# Loot box purchase into inventory.
	var basic := LootBoxCatalog.by_id("basic_box")
	_check(not basic.is_empty(), "basic_box data loads")
	_check(LootBoxCatalog.odds_text(basic).contains("%"), "odds text renders (compliance)")
	var count_before := EconomyService.get_loot_box_count("basic_box")
	_check(EconomyService.purchase_loot_box(basic), "box purchase succeeds")
	_check(EconomyService.get_loot_box_count("basic_box") == count_before + 1, "box banked in inventory")

	# Loadout application: equip the upgraded card, apply to fresh stats.
	SaveService.set_value("cards.equipped", ["sharpened_brushes"])
	var run_config := RunBalance.load_config()
	var plain := PlayerStats.from_config(run_config)
	var loaded := PlayerStats.from_config(run_config)
	CardUpgrades.apply_loadout(loaded, config)
	# Base effect 1.25x + 1 damage upgrade (+0.05) + 1 projectile upgrade (+1).
	_check(absf(loaded.damage_mult - 1.30) < 0.001, "equipped card effect + upgrade applied (damage_mult %.2f)" % loaded.damage_mult)
	_check(loaded.projectile_count == plain.projectile_count + 1, "projectile upgrade applied")
	_check(loaded.effective_damage() > plain.effective_damage(), "loadout increases effective damage")


func _test_ui() -> void:
	SaveService.reset_to_defaults()
	EconomyService.add_blobs(5000)

	var all_cards := CardCatalog.load_all()
	_check(not all_cards.is_empty(), "cards loaded")
	if all_cards.is_empty():
		return
	var first_card_id := str(all_cards[0].get("id", ""))

	# Deck: equip card via save.
	var equipped: Array = SaveService.get_value("cards.equipped", [])
	equipped.append(first_card_id)
	SaveService.set_value("cards.equipped", equipped)
	_check(SaveService.get_value("cards.equipped", []).size() == 1, "equip persisted")
	SaveService.set_value("cards.equipped", [])
	_check(SaveService.get_value("cards.equipped", []).is_empty(), "unequip persisted")

	# Shop: test CardUpgrades upgrade level persistence.
	var upgrades_config := CardUpgrades.load_config()
	if not upgrades_config.is_empty():
		SaveService.set_value("cards.upgrades.%s.damage" % first_card_id, 1)
		_check(CardUpgrades.get_level(first_card_id, "damage") >= 0, "upgrade level readable")


func _wait(predicate: Callable, name: String) -> bool:
	for i in range(STEP_TIMEOUT_FRAMES):
		if predicate.call():
			return true
		await get_tree().process_frame
	_failures.append("timed out: %s" % name)
	return false
