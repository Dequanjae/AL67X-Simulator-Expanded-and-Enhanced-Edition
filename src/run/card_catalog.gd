class_name CardCatalog
extends RefCounted
## Folder-scanned card loader (spec Sections 8/13). Cards are plain JSON
## files in data/cards/<rarity>/ — the folder IS the rarity. No manifest:
## adding/rebalancing a card is a file drop/edit, zero code changes.

const RARITY_FOLDERS: Array[String] = ["common", "rare", "epic", "legendary"]


static func load_all() -> Array:
	var cards: Array = []
	for rarity in RARITY_FOLDERS:
		for path in JsonData.list_files("res://data/cards/%s" % rarity, "json"):
			var card: Variant = JsonData.load_json(path)
			if card is Dictionary and card.has("id"):
				card["rarity"] = rarity
				cards.append(card)
	return cards


## Cards always available in the level-up pool for every player.
static func base_cards(all_cards: Array) -> Array:
	return all_cards.filter(func(c: Dictionary) -> bool: return bool(c.get("base", false)))


## Level-up pool: base cards + owned loot-box cards (only owned non-base
## cards are eligible — spec Section 8).
static func level_up_pool(all_cards: Array, owned_ids: Array) -> Array:
	return all_cards.filter(func(c: Dictionary) -> bool:
		return bool(c.get("base", false)) or owned_ids.has(str(c.get("id", ""))))


## Rolls `count` DISTINCT options from the pool, weighted by each card's
## explicit `weight` odds field.
static func roll_options(pool: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var remaining := pool.duplicate()
	var options: Array = []
	while options.size() < count and not remaining.is_empty():
		var total := 0.0
		for card in remaining:
			total += float(card.get("weight", 1))
		var roll := rng.randf() * total
		for i in range(remaining.size()):
			roll -= float(remaining[i].get("weight", 1))
			if roll <= 0.0:
				options.append(remaining[i])
				remaining.remove_at(i)
				break
	return options
