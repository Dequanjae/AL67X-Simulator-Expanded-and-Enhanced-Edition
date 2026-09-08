extends Node
## EconomyService — the ONLY writer of permanent currency balances (autoload).
##
## Two currencies (never conflate):
##  - Blobs/Shawarmas (soft): earned in runs (banked at run end), spent on
##    card upgrades, lesser loot boxes, vendor purchases.
##  - AL67X Tokens (hard): earned via rewarded ads or real-money purchase,
##    spent on energy skips, premium loot boxes.
##
## All balance changes flow through here so EventBus.blobs_changed /
## tokens_changed stay authoritative for UI.


func _ready() -> void:
	# Free map loot boxes bank straight into inventory (spec Section 5:
	# rare findable spawns, separate from purchased boxes).
	EventBus.loot_box_collected.connect(func(box_id: String) -> void:
		if not LootBoxCatalog.by_id(box_id).is_empty():
			add_loot_box(box_id)
	)
	# Beating a level earns a box (spec Section 8: "earned from beating
	# levels"). Box id is balance data.
	EventBus.run_ended.connect(func(summary: Dictionary) -> void:
		if bool(summary.get("victory", false)):
			var config := RunBalance.load_config()
			var box_id := str(config.get("run_rewards", {}).get("victory_loot_box", "basic_box"))
			if not LootBoxCatalog.by_id(box_id).is_empty():
				add_loot_box(box_id)
	)


func get_blobs() -> int:
	return int(SaveService.get_value("economy.blobs", 0))


func get_tokens() -> int:
	return int(SaveService.get_value("economy.tokens", 0))


## Watts (time currency): lazily loads WattsService, which does offline
## accrual math (stored + elapsed * rate, capped). See watts_service.gd.
func get_watts() -> int:
	return WattsService.get_watts()


func spend_watts(amount: int) -> bool:
	var ok: bool = WattsService.spend_watts(amount)
	if not ok and amount > 0:
		EventBus.purchase_failed.emit("watts", "insufficient_watts")
	return ok


func add_watts(amount: int) -> void:
	WattsService.add_watts(amount)



func add_blobs(amount: int) -> void:
	if amount == 0:
		return
	var balance := maxi(0, get_blobs() + amount)
	SaveService.set_value("economy.blobs", balance)
	EventBus.blobs_changed.emit(balance)


func add_tokens(amount: int) -> void:
	if amount == 0:
		return
	var balance := maxi(0, get_tokens() + amount)
	SaveService.set_value("economy.tokens", balance)
	EventBus.tokens_changed.emit(balance)



## Gems (premium currency): no earn source yet — the top bar is wired so
## grants/purchases can land later without UI changes.
func get_gems() -> int:
	return int(SaveService.get_value("economy.gems", 0))


func add_gems(amount: int) -> void:
	if amount == 0:
		return
	var balance := maxi(0, get_gems() + amount)
	SaveService.set_value("economy.gems", balance)
	EventBus.gems_changed.emit(balance)


func spend_gems(amount: int) -> bool:
	if amount < 0 or get_gems() < amount:
		return false
	add_gems(-amount)
	return true


## Returns false (and changes nothing) if the balance is insufficient.
func spend_blobs(amount: int) -> bool:
	if amount < 0 or get_blobs() < amount:
		return false
	add_blobs(-amount)
	return true


func spend_tokens(amount: int) -> bool:
	if amount < 0 or get_tokens() < amount:
		return false
	add_tokens(-amount)
	return true


# ---------------------------------------------------------------------------
# Loot box inventory (unopened boxes; opening flow lands in Phase 8)
# ---------------------------------------------------------------------------

func get_loot_box_count(box_id: String) -> int:
	return int(SaveService.get_value("economy.loot_boxes.%s" % box_id, 0))


func add_loot_box(box_id: String, amount := 1) -> void:
	SaveService.set_value("economy.loot_boxes.%s" % box_id, get_loot_box_count(box_id) + amount)


## Returns false if none in inventory (used by the Phase 8 opening flow).
func consume_loot_box(box_id: String) -> bool:
	var count := get_loot_box_count(box_id)
	if count <= 0:
		return false
	SaveService.set_value("economy.loot_boxes.%s" % box_id, count - 1)
	return true


## Buys one box (cost from its data file) into inventory.
func purchase_loot_box(box: Dictionary) -> bool:
	var box_id := str(box.get("id", ""))
	var box_cost: Dictionary = box.get("cost", {})
	var paid: bool
	if str(box_cost.get("currency", "blobs")) == "tokens":
		paid = spend_tokens(int(box_cost.get("amount", 0)))
	else:
		paid = spend_blobs(int(box_cost.get("amount", 0)))
	if not paid:
		EventBus.purchase_failed.emit(box_id, "insufficient_%s" % box_cost.get("currency", "blobs"))
		return false
	add_loot_box(box_id)
	EventBus.purchase_completed.emit(box_id)
	return true


# ---------------------------------------------------------------------------
# SWAP-POINT (real credentials required later): AL67X Token purchases.
#
# This debug grant is the Phase-1 stand-in for the real-money purchase flow.
# When monetization is scoped, replace the BODY of purchase_tokens() with
# Google Play Billing (or Stripe/Square if distribution stays off-Play) —
# callers must not change. debug_grant_tokens() stays available behind a
# dev-menu/debug flag.
# ---------------------------------------------------------------------------

## Purchase entry point used by real UI. Currently routes to the debug grant.
func purchase_tokens(pack_id: String, token_amount: int) -> void:
	# SWAP-POINT: replace with real billing. Grant only after store confirms.
	debug_grant_tokens(token_amount)
	EventBus.purchase_completed.emit(pack_id)


func debug_grant_tokens(amount: int) -> void:
	add_tokens(amount)
