extends Node
## UIBridge — the ONE JS <-> GDScript messaging layer for the HTML/CSS UI
## (mirrors web_ui/shared/bridge.js's contract — keep both in sync when
## adding a message type). Owns ZERO game/economy logic: it only routes
## typed messages to the real systems (EconomyService, AmpsService,
## FusionSystem, ...) and rebroadcasts EventBus signals to every mounted
## WebView via post_message(). Every screen's WebViewHost registers itself
## here instead of hand-rolling its own ipc plumbing.

var _views: Array = []  # WebViewHost instances currently mounted
var _fusion_config: Dictionary = {}
var _card_upgrade_config: Dictionary = {}


func _ready() -> void:
	_fusion_config = FusionSystem.load_config()
	_card_upgrade_config = CardUpgrades.load_config()
	EventBus.blobs_changed.connect(func(v: int) -> void: broadcast("blobs_changed", {"balance": v}))
	EventBus.tokens_changed.connect(func(v: int) -> void: broadcast("tokens_changed", {"balance": v}))
	EventBus.amps_changed.connect(func(cur: int, max_v: int) -> void:
		broadcast("amps_changed", {"current": cur, "max": max_v, "next_tick_sec": AmpsService.seconds_to_next()}))
	EventBus.allan_unlocked.connect(func(id: String) -> void:
		broadcast("allan_unlocked", {"allan_id": id})
		broadcast("allan_collection", _build_allan_collection()))
	EventBus.allan_equipped.connect(func(id: String) -> void:
		broadcast("allan_equipped", {"allan_id": id})
		broadcast("allan_collection", _build_allan_collection()))
	EventBus.card_unlocked.connect(func(id: String) -> void: broadcast("card_unlocked", {"card_id": id}))
	EventBus.card_choice_presented.connect(func(options: Array) -> void: broadcast("card_choices", {"options": options}))
	EventBus.blob_collected.connect(func(amount: int) -> void:
		broadcast("toast_blobs", {"amount": amount, "new_total": EconomyService.get_blobs()}))
	EventBus.purchase_completed.connect(func(id: String) -> void: broadcast("purchase_result", {"ok": true, "item_id": id}))
	EventBus.purchase_failed.connect(func(id: String, reason: String) -> void:
		broadcast("purchase_result", {"ok": false, "item_id": id, "reason": reason}))
	EventBus.save_loaded.connect(func() -> void: broadcast_full_state())


# ---------------------------------------------------------------------------
# View registry / outbound
# ---------------------------------------------------------------------------

## Called by WebViewHost once its webview is ready to receive messages.
func register_view(view) -> void:
	if not _views.has(view):
		_views.append(view)


func unregister_view(view) -> void:
	_views.erase(view)


## Sends a typed message to every currently mounted webview.
func broadcast(type: String, payload: Dictionary = {}) -> void:
	var json := JSON.stringify(_merged(type, payload))
	for view in _views:
		if is_instance_valid(view):
			view.post_message(json)


func broadcast_full_state() -> void:
	broadcast("state_sync", _build_full_state())


func _build_full_state() -> Dictionary:
	AmpsService.sync()
	return {
		"blobs": EconomyService.get_blobs(),
		"tokens": EconomyService.get_tokens(),
		"amps": AmpsService.get_current(),
		"amps_max": AmpsService.get_max(),
		"amps_next_tick_sec": AmpsService.seconds_to_next(),
		"level": int(SaveService.get_value("progress.highest_level_unlocked", 1)),
		"unseen_news": _build_whats_new(false).get("unseen_count", 0),
	}


func _merged(type: String, payload: Dictionary) -> Dictionary:
	var out := payload.duplicate()
	out["type"] = type
	return out


# ---------------------------------------------------------------------------
# Inbound
# ---------------------------------------------------------------------------

## Wired to every WebViewHost's `ipc_message`. `view` identifies which
## mounted webview sent it (used to reply directly, e.g. the initial state
## sync, instead of broadcasting to every screen unnecessarily).
func handle_message(message: String, view = null) -> void:
	var parsed: Variant = JSON.parse_string(message)
	if not (parsed is Dictionary) or not parsed.has("type"):
		push_warning("UIBridge: malformed message: %s" % message)
		return
	_route(parsed, view)


## Test-only entry point (no WebView required) — drives the exact same
## routing real screens use, so headless gates can verify the GDScript
## side without a rendered webview (godot_wry cannot run under --headless).
func simulate_message(message: String) -> void:
	handle_message(message, null)


## Test-only: like simulate_message(), but for request/reply-style messages
## (ready, request_state, request_shop_catalog, request_settings,
## request_whats_new, request_merge_state, request_allan_collection, plus
## broadcast-style replies like open_chest/merge_swap) — returns the parsed
## reply payload instead of requiring a real WebView. Registers the fake
## view for the duration of the call so both direct replies (view.
## post_message) AND broadcast() (open_chest, merge_swap, ...) reach it.
func simulate_message_with_reply(message: String) -> Dictionary:
	var fake := _TestView.new()
	register_view(fake)
	handle_message(message, fake)
	unregister_view(fake)
	if fake.last_message.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(fake.last_message)
	return parsed if parsed is Dictionary else {}


class _TestView:
	var last_message := ""
	func post_message(json: String) -> void:
		last_message = json


func _route(data: Dictionary, view) -> void:
	var type := str(data.get("type", ""))
	match type:
		"ready", "request_state":
			if view != null:
				register_view(view)
				view.post_message(JSON.stringify(_merged("state_sync", _build_full_state())))
		"request_shop_catalog":
			if view != null:
				view.post_message(JSON.stringify(_merged("shop_catalog", _build_shop_catalog())))
		"request_settings":
			if view != null:
				view.post_message(JSON.stringify(_merged("settings_state", _build_settings_state())))
		"request_whats_new":
			if view != null:
				view.post_message(JSON.stringify(_merged("whats_new_entries", _build_whats_new(false))))
		"request_merge_state":
			if view != null:
				view.post_message(JSON.stringify(_merged("merge_state", _build_merge_state())))
		"request_allan_collection":
			if view != null:
				view.post_message(JSON.stringify(_merged("allan_collection", _build_allan_collection())))
		"request_deck":
			if view != null:
				view.post_message(JSON.stringify(_merged("deck_state", _build_deck_state())))
		"toggle_equip_card":
			_handle_toggle_equip_card(str(data.get("card_id", "")))
		"open_news":
			broadcast("whats_new_entries", _build_whats_new(true))
		"open_mail":
			pass  # SWAP-POINT: no mailbox/inbox system exists yet
		"nav_change":
			pass  # audio/analytics hook point only; no state change
		"start_run":
			pass  # scene swap handled by the hub host script listening for this
		"debug_add_blobs":
			EconomyService.add_blobs(int(data.get("amount", 0)))
		"spend_amps":
			var ok := AmpsService.spend(int(data.get("amount", 1)), str(data.get("reason", "")))
			if view != null:
				view.post_message(JSON.stringify({"type": "spend_amps_result", "ok": ok}))
		"refill_amps_with_tokens":
			AmpsService.refill_with_tokens()
		"purchase_loot_box":
			_handle_purchase_loot_box(str(data.get("box_id", "")))
		"open_chest":
			_handle_open_chest(str(data.get("box_id", "")))
		"purchase_upgrade":
			CardUpgrades.purchase(str(data.get("card_id", "")), str(data.get("upgrade_type", "")), _card_upgrade_config)
			broadcast("shop_catalog", _build_shop_catalog())
		"purchase_tokens":
			EconomyService.purchase_tokens(str(data.get("pack_id", "")), int(data.get("token_amount", 0)))
		"merge_swap":
			_handle_merge_swap(int(data.get("a", -1)), int(data.get("b", -1)))
		"equip_allan":
			FusionSystem.equip(str(data.get("allan_id", "")))
		"card_choice", "dev_boss_win", "dev_die", "ad_continue", "ascend_continue", \
		"pause_toggle", "quit_to_hub":
			pass  # run-scene-specific: handled by run_controller.gd / LevelUpController
			# listening directly to the run's WebViewHost.ipc_message signal
			# (same pattern hub.gd uses for start_run/sign_in) — these need
			# gameplay context (PlayerStats, RunController) UIBridge doesn't
			# have and shouldn't reach into.
		"settings_change":
			_handle_settings_change(data)
		"sign_out":
			SaveService.detach_cloud()
		"open_url":
			OS.shell_open(str(data.get("url", "")))
		"whats_new_seen":
			SaveService.set_value("meta.whats_new_last_seen", str(data.get("entry_id", "")))
		_:
			push_warning("UIBridge: unknown message type '%s'" % type)


func _handle_merge_swap(a: int, b: int) -> void:
	var width := int(_fusion_config.get("grid_width", 4))
	if not FusionSystem.are_adjacent(a, b, width):
		return
	if not FusionSystem.swap_tiles(a, b, _fusion_config):
		return
	var results := FusionSystem.resolve_matches(_fusion_config)
	var payload := _build_merge_state()
	payload["merges"] = results
	broadcast("merge_state", payload)


func _build_merge_state() -> Dictionary:
	return {
		"grid": FusionSystem.get_grid(_fusion_config),
		"width": int(_fusion_config.get("grid_width", 4)),
		"height": int(_fusion_config.get("grid_height", 4)),
		"merges": [],
	}


func _build_allan_collection() -> Dictionary:
	var equipped_id := str(SaveService.get_value("allans.equipped", "player1"))
	var owned: Array = SaveService.get_value("allans.owned", [])
	var registry: Array = AllanSprites.registry().get("allans", [])
	var owned_entries: Array = []
	for allan in registry:
		if owned.has(str(allan.get("id", ""))):
			owned_entries.append(allan)
	return {"equipped_id": equipped_id, "owned": owned_entries, "total": registry.size()}


const DECK_SIZE := 6

## Deck ("Cards" nav tab): base cards + owned loot-box cards, tap to
## equip/unequip up to DECK_SIZE. Ported unchanged from the old
## tab_deck.gd Control screen — only the presentation moved to HTML.
func _build_deck_state() -> Dictionary:
	var catalog := CardCatalog.load_all()
	var owned: Array = SaveService.get_value("cards.owned", {}).keys()
	var available := catalog.filter(func(c: Dictionary) -> bool:
		return bool(c.get("base", false)) or owned.has(str(c.get("id", ""))))
	var equipped: Array = SaveService.get_value("cards.equipped", [])
	var cards: Array = []
	for card in available:
		var card_id := str(card.get("id", ""))
		var out_card: Dictionary = card.duplicate(true)
		out_card["equipped"] = equipped.has(card_id)
		out_card["count"] = int(SaveService.get_value("cards.owned.%s.count" % card_id, 0))
		cards.append(out_card)
	return {"cards": cards, "equipped": equipped, "deck_size": DECK_SIZE}


func _handle_toggle_equip_card(card_id: String) -> void:
	if card_id.is_empty():
		return
	var equipped: Array = SaveService.get_value("cards.equipped", [])
	if equipped.has(card_id):
		equipped.erase(card_id)
	elif equipped.size() < DECK_SIZE:
		equipped.append(card_id)
	else:
		return  # stack full
	SaveService.set_value("cards.equipped", equipped)
	EventBus.deck_changed.emit(equipped)
	broadcast("deck_state", _build_deck_state())


func _handle_open_chest(box_id: String) -> void:
	var result := LootBoxCatalog.open(box_id)
	result["box_id"] = box_id
	broadcast("chest_opened", result)


## Buying a box hands off straight into the chest-opening popup (spec: no
## separate "now go open it" step) — purchase into inventory, then
## immediately consume + roll it so the popup has real contents to reveal.
func _handle_purchase_loot_box(box_id: String) -> void:
	var box := LootBoxCatalog.by_id(box_id)
	if box.is_empty():
		return
	if not EconomyService.purchase_loot_box(box):
		return
	_handle_open_chest(box_id)


func _build_shop_catalog() -> Dictionary:
	var boxes: Array = []
	for box in LootBoxCatalog.load_all():
		var b: Dictionary = box.duplicate(true)
		b["odds_text"] = LootBoxCatalog.odds_text(box)
		boxes.append(b)

	var owned_cards: Dictionary = SaveService.get_value("cards.owned", {})
	var upgrades: Array = []
	for card in CardCatalog.load_all():
		var card_id := str(card.get("id", ""))
		# Base cards are always upgradeable; loot cards need to be owned
		# first (matches the old tab_shop.gd/tab_deck.gd availability rule).
		if not (bool(card.get("base", false)) or owned_cards.has(card_id)):
			continue
		var types := CardUpgrades.types_for_card(card, _card_upgrade_config)
		var per_type: Array = []
		for upgrade_type in types:
			var level := CardUpgrades.get_level(card_id, upgrade_type)
			per_type.append({
				"type": upgrade_type,
				"level": level,
				"cost": CardUpgrades.cost(upgrade_type, level, _card_upgrade_config),
			})
		upgrades.append({"card_id": card_id, "name": card.get("name", card_id), "rarity": card.get("rarity", "common"), "upgrades": per_type})

	return {"boxes": boxes, "upgrades": upgrades, "tokens": EconomyService.get_tokens(), "blobs": EconomyService.get_blobs()}


func _build_settings_state() -> Dictionary:
	var out := {}
	for key in GameSettings.DEFAULTS:
		out[key] = GameSettings.get_value(key)
	out["save_mode"] = str(SaveService.get_value("meta.save_mode", ""))
	return out


## Newest-first feed (spec: append new entries to the FRONT). Unseen =
## everything before the last-seen id. `force_all` (News icon tapped
## explicitly) always returns up to 5 most recent regardless of seen state.
func _build_whats_new(force_all: bool) -> Dictionary:
	var parsed: Variant = JsonData.load_json("res://data/whats_new.json")
	var entries: Array = (parsed.get("entries", []) if parsed is Dictionary else [])
	var last_seen := str(SaveService.get_value("meta.whats_new_last_seen", ""))
	var unseen: Array = []
	for entry in entries:
		if str(entry.get("id", "")) == last_seen:
			break
		unseen.append(entry)
	var shown: Array = entries if force_all else unseen
	if shown.size() > 5:
		shown = shown.slice(0, 5)
	return {"entries": shown, "unseen_count": unseen.size()}


func _handle_settings_change(data: Dictionary) -> void:
	var key := str(data.get("key", ""))
	if key.is_empty():
		return
	GameSettings.set_value(key, data.get("value"))
