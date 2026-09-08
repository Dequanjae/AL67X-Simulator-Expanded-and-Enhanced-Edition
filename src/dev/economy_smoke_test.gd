extends Node
## Economy gate (watts + loot v2) — run headless:
##   godot --headless res://scenes/dev/economy_smoke_test.tscn
## A (pure): watts seeding/accrual/cap/spend; loot v2 grants 2 cards +
## bonus currencies; watts-denominated upgrades purchasable.
## B (UI): BoxOpenPopup frames (motor under housing), tap->housing falls,
## rewards show 2 cards + bonuses; hub top bar has 3 currency rows.
## Exits 0 on PASS, 1 on FAIL. Resets the local save file.

const STEP_TIMEOUT_FRAMES := 1800
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
	_test_watts()
	_test_gems()
	await _test_loot_v2()
	await _test_popup_ui()
	if _failures.is_empty():
		print("ECONOMY TEST: PASS")
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		print("ECONOMY TEST: FAILED (%d)" % _failures.size())
	SaveService.reset_to_defaults()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(cond: bool, name: String) -> void:
	if not cond:
		_failures.append(name)


func _test_watts() -> void:
	SaveService.reset_to_defaults()
	var cfg := WattsService.config()
	var start := int(cfg.get("start", 30))
	var cap := int(cfg.get("cap", 480))
	var w1 := EconomyService.get_watts()
	_check(w1 == start, "first watts read seeds start (%d)" % w1)
	# accrual: simulate time passing by rewinding the sync point
	var synced: float = SaveService.get_value("economy.watts_synced_hours", 0.0)
	SaveService.set_value("economy.watts_synced_hours", synced - 0.5)  # -30min
	var w2 := EconomyService.get_watts()
	_check(w2 >= w1, "watts accrue with time (%d -> %d)" % [w1, w2])
	_check(w2 <= cap, "watts respect cap")
	# spend
	_check(EconomyService.spend_watts(5), "watts spendable")
	_check(EconomyService.get_watts() == w2 - 5, "watts balance after spend")
	_check(not EconomyService.spend_watts(100000), "overdraft rejected")
	# cap clamp: push sync far back
	SaveService.set_value("economy.watts_synced_hours", synced - 1000.0)
	_check(EconomyService.get_watts() == cap, "accrual clamps at cap")
	# watts-denominated upgrade purchase
	var up_cfg: Dictionary = CardUpgrades.load_config()
	var card_id := "overclocked_rotor"
	SaveService.set_value("cards.owned.%s.count" % card_id, 1)
	SaveService.set_value("cards.owned.%s.upgrades" % card_id, {})
	EconomyService.add_watts(500)
	var level_before := CardUpgrades.get_level(card_id, "damage")
	_check(CardUpgrades.purchase(card_id, "damage", up_cfg), "damage upgrade purchasable with watts")
	_check(CardUpgrades.get_level(card_id, "damage") == level_before + 1, "watts upgrade persisted")


## Gems (premium currency): balance persists, clamps at 0, spends cleanly.
func _test_gems() -> void:
	SaveService.reset_to_defaults()
	_check(EconomyService.get_gems() == 0, "gems start at 0")
	EconomyService.add_gems(250)
	_check(EconomyService.get_gems() == 250, "gems granted")
	var seen: Array[int] = []
	EventBus.gems_changed.connect(func(v: int) -> void: seen.append(v))
	EconomyService.add_gems(50)
	_check(seen.has(300), "gems_changed emitted with new balance")
	_check(EconomyService.spend_gems(100), "gems spendable")
	_check(EconomyService.get_gems() == 200, "gems balance after spend")
	_check(not EconomyService.spend_gems(9999), "overdraft rejected")
	_check(EconomyService.get_gems() == 200, "overdraft changes nothing")




func _test_loot_v2() -> void:
	SaveService.reset_to_defaults()
	EconomyService.add_loot_box("basic_box", 1)
	var blobs_before := EconomyService.get_blobs()
	var tokens_before := EconomyService.get_tokens()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var result := LootBoxCatalog.open("basic_box", rng)
	_check(bool(result.get("ok", false)), "box opens")
	var cards: Array = result.get("cards", [])
	_check(cards.size() == 2, "box grants 2 cards (%d)" % cards.size())
	var rarities: Array = result.get("rarities", [])
	for r in rarities:
		_check(["common", "rare", "epic"].has(r), "rarity in box table: %s" % r)
	var rewards: Dictionary = result.get("rewards", {})
	_check(int(rewards.get("blobs", 0)) == 40, "basic box grants +40 blobs")
	_check(int(rewards.get("tokens", 0)) == 2, "basic box grants +2 tokens")
	_check(EconomyService.get_blobs() == blobs_before + 40, "bonus blobs banked")
	_check(EconomyService.get_tokens() == tokens_before + 2, "bonus tokens banked")
	_check(EconomyService.get_loot_box_count("basic_box") == 0, "box consumed")
	# both cards banked with duplicate flags
	var owned: Dictionary = SaveService.get_value("cards.owned", {})
	var total := 0
	for id in owned:
		total += int(owned[id].get("count", 0))
	_check(total == 2, "both pulls banked (%d)" % total)


func _test_popup_ui() -> void:
	# Popup exists in the hub scene, frames load, flow animates.
	var hub: PackedScene = load("res://scenes/hub/hub.tscn")
	var instance := hub.instantiate()
	get_tree().root.add_child(instance)
	await get_tree().process_frame
	var popup = instance.get_node_or_null("BoxOpenPopup")
	_check(popup != null, "BoxOpenPopup node exists in hub scene")
	if popup == null:
		return
	_check(popup.get_script() != null and popup.get_script().resource_path.contains("box_open_popup"), "popup script attached")
	# frame textures: motor (frame 2) and housing (frame 3) from the sheet
	for rarity in ["common", "rare", "epic", "legendary", "uncommon"]:
		var tex: AtlasTexture = BoxOpenPopup.frame_texture(rarity, 1)
		_check(tex != null and tex.get_width() > 0, "frame 2 texture loads for %s" % rarity)
	# simulate an open result and drive the flow
	EconomyService.add_loot_box("premium_box", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var result := LootBoxCatalog.open("premium_box", rng)
	popup.open_with_result(result)
	await get_tree().process_frame
	_check(popup.visible, "popup visible after open")
	var motor: TextureRect = popup.get_node("Center/Popup/VB/BoxArt/Motor")
	var housing: TextureRect = popup.get_node("Center/Popup/VB/BoxArt/Housing")
	_check(motor.texture != null, "motor frame shown")
	_check(housing.visible, "housing covers motor before tap")
	popup._reveal()
	for i in range(150):
		await get_tree().process_frame
	_check(not housing.visible or housing.modulate.a < 0.5, "housing falls after tap")
	var rewards_box = popup.get_node("Center/Popup/VB/RewardsBox")
	_check(rewards_box.visible, "rewards shown after housing drops")
	var cards_label: Label = rewards_box.get_node("CardsLabel")
	_check(cards_label.text.contains("["), "cards listed: %s" % cards_label.text)
	# top bar rows
	_check(instance.get_node_or_null("SafeArea/Layout/TopBar/TopBarBox/WattsRow/WattsLabel") != null, "watts row in top bar")
	_check(instance.get_node_or_null("SafeArea/Layout/TopBar/TopBarBox/BlobsRow/BlobsIcon") != null, "blob icon in top bar")
	_check(instance.get_node_or_null("SafeArea/Layout/TopBar/TopBarBox/BlobsRow/BlobsLabel") != null, "blobs row in top bar")