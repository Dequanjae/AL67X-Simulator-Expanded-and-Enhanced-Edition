class_name LootBoxCatalog
extends RefCounted
## Folder-scanned loot box definitions (data/loot_boxes/*.json) with
## explicit drop-rate weights (store compliance) + the opening flow:
## consume 1 from inventory → roll rarity by the box's weights → uniform
## card within that rarity (non-base cards preferred) → bank into
## cards.owned. First-ever copy emits card_unlocked.


static func load_all() -> Array:
	var boxes: Array = []
	for path in JsonData.list_files("res://data/loot_boxes", "json"):
		var box: Variant = JsonData.load_json(path)
		if box is Dictionary and box.has("id"):
			boxes.append(box)
	boxes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", "")))
	return boxes


static func by_id(box_id: String) -> Dictionary:
	for box in load_all():
		if str(box.get("id", "")) == box_id:
			return box
	return {}


## Human-readable odds line for compliance display, e.g.
## "common 70% / rare 25% / epic 5%".
static func odds_text(box: Dictionary) -> String:
	var drops: Array = box.get("drops", [])
	var total := 0.0
	for drop in drops:
		total += float(drop.get("weight", 0))
	if total <= 0.0:
		return ""
	var parts: PackedStringArray = []
	for drop in drops:
		parts.append("%s %d%%" % [str(drop.get("rarity", "?")), roundi(100.0 * float(drop.get("weight", 0)) / total)])
	return " / ".join(parts)


## Opens one box from inventory. Returns:
## {ok, reason?, card?, rarity?, duplicate?, count?}
static func open(box_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var box := by_id(box_id)
	if box.is_empty():
		return {"ok": false, "reason": "unknown_box"}
	if not EconomyService.consume_loot_box(box_id):
		return {"ok": false, "reason": "none_owned"}

	var rarity := _roll_rarity(box, rng)
	var card := _roll_card(rarity, rng)
	if card.is_empty():
		# Should never happen with a sane catalog; don't eat the box.
		EconomyService.add_loot_box(box_id)
		return {"ok": false, "reason": "empty_pool"}

	var card_id := str(card["id"])
	var count := int(SaveService.get_value("cards.owned.%s.count" % card_id, 0))
	var duplicate := count > 0
	SaveService.set_value("cards.owned.%s.count" % card_id, count + 1)
	if SaveService.get_value("cards.owned.%s.upgrades" % card_id, null) == null:
		SaveService.set_value("cards.owned.%s.upgrades" % card_id, {})
	if not duplicate:
		EventBus.card_unlocked.emit(card_id)
	return {"ok": true, "card": card, "rarity": rarity, "duplicate": duplicate, "count": count + 1}


static func _roll_rarity(box: Dictionary, rng: RandomNumberGenerator) -> String:
	var drops: Array = box.get("drops", [])
	var total := 0.0
	for drop in drops:
		total += float(drop.get("weight", 0))
	var roll := rng.randf() * total
	for drop in drops:
		roll -= float(drop.get("weight", 0))
		if roll <= 0.0:
			return str(drop.get("rarity", "common"))
	return "common"


## Uniform pick within the rarity; non-base cards preferred so pulls feel
## like acquisitions, not repeats of the default kit.
static func _roll_card(rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	var all_cards := CardCatalog.load_all()
	var candidates := all_cards.filter(func(c: Dictionary) -> bool: return str(c.get("rarity", "")) == rarity)
	var non_base := candidates.filter(func(c: Dictionary) -> bool: return not bool(c.get("base", false)))
	if not non_base.is_empty():
		candidates = non_base
	if candidates.is_empty():
		candidates = all_cards
	if candidates.is_empty():
		return {}
	return candidates[rng.randi_range(0, candidates.size() - 1)]
