class_name CardUpgrades
extends RefCounted
## Card upgrade system (spec Section 12): flat, uncapped, per-card stat
## upgrades bought in the Shop. Cost curve + per-level bonuses are DATA
## (data/balance/card_upgrades.json). Upgrade levels persist in the save
## under cards.owned[card_id].upgrades[type]; equipped cards apply their
## base effect + upgrade bonuses to PlayerStats at run start.


static func load_config() -> Dictionary:
	var parsed: Variant = JsonData.load_json("res://data/balance/card_upgrades.json")
	return parsed if parsed is Dictionary else {}


## Which upgrade types a card offers (card JSON may override via "upgrades").
static func types_for_card(card: Dictionary, config: Dictionary) -> Array:
	var all_types: Array = config.get("upgrade_types", {}).keys()
	var declared: Variant = card.get("upgrades", null)
	if declared is Array:
		return declared.filter(func(t: Variant) -> bool: return all_types.has(str(t)))
	return all_types


static func get_level(card_id: String, upgrade_type: String) -> int:
	return int(SaveService.get_value("cards.owned.%s.upgrades.%s" % [card_id, upgrade_type], 0))


## Cost of buying the NEXT level given the current one. Uncapped.
static func cost(upgrade_type: String, current_level: int, config: Dictionary) -> Dictionary:
	var type_cfg: Dictionary = config.get("upgrade_types", {}).get(upgrade_type, {})
	var base := float(type_cfg.get("cost_base", 50))
	var growth := float(type_cfg.get("cost_growth", 1.25))
	return {
		"currency": str(type_cfg.get("currency", "blobs")),
		"amount": int(ceilf(base * pow(growth, float(current_level)))),
	}


## Attempts the purchase: spends currency, increments the persisted level.
## Returns true on success. Emits purchase_completed / purchase_failed.
static func purchase(card_id: String, upgrade_type: String, config: Dictionary) -> bool:
	var item_id := "upgrade_%s_%s" % [card_id, upgrade_type]
	var level := get_level(card_id, upgrade_type)
	var price := cost(upgrade_type, level, config)
	var paid: bool
	if str(price["currency"]) == "tokens":
		paid = EconomyService.spend_tokens(int(price["amount"]))
	elif str(price["currency"]) == "watts":
		paid = EconomyService.spend_watts(int(price["amount"]))
	else:
		paid = EconomyService.spend_blobs(int(price["amount"]))
	if not paid:
		EventBus.purchase_failed.emit(item_id, "insufficient_%s" % price["currency"])
		return false
	SaveService.set_value("cards.owned.%s.upgrades.%s" % [card_id, upgrade_type], level + 1)
	EventBus.purchase_completed.emit(item_id)
	return true


## Applies the equipped 6-card stack (base effects + upgrade bonuses) to
## fresh run stats. Called by RunController at run start.
static func apply_loadout(stats: PlayerStats, config: Dictionary) -> void:
	var catalog := CardCatalog.load_all()
	var by_id: Dictionary = {}
	for card in catalog:
		by_id[str(card["id"])] = card
	var upgrade_types: Dictionary = config.get("upgrade_types", {})
	var equipped: Array = SaveService.get_value("cards.equipped", [])
	for card_id in equipped:
		var card: Dictionary = by_id.get(str(card_id), {})
		if card.is_empty():
			continue
		stats.apply_effect(card.get("effect", {}))
		for upgrade_type in types_for_card(card, config):
			var level := get_level(str(card_id), str(upgrade_type))
			if level <= 0:
				continue
			var per_level: Dictionary = upgrade_types.get(upgrade_type, {}).get("per_level", {})
			if per_level.is_empty():
				continue
			# All *_add per-level effects are linear — apply value × level.
			var scaled := per_level.duplicate()
			scaled["value"] = float(per_level.get("value", 0)) * float(level)
			stats.apply_effect(scaled)
