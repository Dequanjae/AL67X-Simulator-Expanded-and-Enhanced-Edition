class_name LootBoxCatalog
extends RefCounted
## LootBoxCatalog v2 — folder-scanned loot box definitions (data/loot_boxes/
## *.json) with explicit drop-rate weights (store compliance) + the opening
## flow: consume 1 from inventory → roll cards from the drop table → grant
## flat currency rewards → bank into cards.owned. First-ever copy emits
## card_unlocked.
##
## open() now returns TWO cards plus currency rewards per box JSON:
##   {ok, reason?, cards: [card, card], rarities: [r, r], duplicates: [],
##    rewards: {blobs, tokens}}


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


## Rarity roll per the box's drop table (explicit weights).
static func _roll_rarity(box: Dictionary, rng: RandomNumberGenerator) -> String:
	var drops: Array = box.get("drops", [])
	var total := 0.0
	for drop in drops:
		total += float(drop.get("weight", 0))
	if total <= 0.0:
		return "common"
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


## Opens one box: rolls `rewards.cards` cards (default 1, now 2 in the box
## JSONs), grants flat currency bonuses, banks everything. The box is NOT
## consumed on failure (empty pool) — same safety as v1.
static func open(box_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var box := by_id(box_id)
	if box.is_empty():
		return {"ok": false, "reason": "unknown_box"}
	if not EconomyService.consume_loot_box(box_id):
		return {"ok": false, "reason": "none_owned"}

	var rewards: Dictionary = box.get("rewards", {})
	var num_cards := maxi(1, int(rewards.get("cards", 1)))

	var cards: Array[Dictionary] = []
	var rarities: Array = []
	var duplicates: Array = []
	for i in range(num_cards):
		var rarity := _roll_rarity(box, rng)
		var card := _roll_card(rarity, rng)
		if card.is_empty():
			continue
		var card_id := str(card["id"])
		var count := int(SaveService.get_value("cards.owned.%s.count" % card_id, 0))
		var duplicate := count > 0
		SaveService.set_value("cards.owned.%s.count" % card_id, count + 1)
		if SaveService.get_value("cards.owned.%s.upgrades" % card_id, null) == null:
			SaveService.set_value("cards.owned.%s.upgrades" % card_id, {})
		if not duplicate:
			EventBus.card_unlocked.emit(card_id)
		cards.append(card)
		rarities.append(rarity)
		duplicates.append(duplicate)

	if cards.is_empty():
		# Should never happen with a sane catalog; don't eat the box.
		EconomyService.add_loot_box(box_id)
		return {"ok": false, "reason": "empty_pool"}

	# Flat currency bonuses granted on open (data-driven, both optional).
	var bonus_blobs := int(rewards.get("blobs", 0))
	var bonus_tokens := int(rewards.get("tokens", 0))
	if bonus_blobs != 0:
		EconomyService.add_blobs(bonus_blobs)
	if bonus_tokens != 0:
		EconomyService.add_tokens(bonus_tokens)

	return {
		"ok": true,
		"cards": cards,
		"rarities": rarities,
		"duplicates": duplicates,
		"rewards": {"blobs": bonus_blobs, "tokens": bonus_tokens},
		"box": box,
	}