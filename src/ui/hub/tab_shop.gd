extends VBoxContainer
## Hub tab: Shop — Allan the shop bender's store (retro presentation; shop
## theme music plumbing lands in Phase 10).
## Sections:
##  - Loot boxes: purchased into inventory (opening flow: Phase 8), costs +
##    displayed drop odds from data/loot_boxes/*.json (compliance).
##  - Card upgrades (spec Section 12): flat uncapped per-card upgrades,
##    scaling cost curve from data/balance/card_upgrades.json.
##  - AL67X Tokens: debug grant — SWAP-POINT for real-money purchase.

var _boxes: Array = []
var _catalog: Array = []
var _upgrade_config: Dictionary = {}
var _selected_card := ""

@onready var _box_list: VBoxContainer = $Scroll/Content/BoxList
@onready var _card_select: OptionButton = $Scroll/Content/CardSelect
@onready var _upgrade_list: VBoxContainer = $Scroll/Content/UpgradeList
@onready var _debug_tokens_button: Button = $Scroll/Content/DebugTokensButton
@onready var _result_label: Label = $Scroll/Content/ResultLabel


func _ready() -> void:
	_boxes = LootBoxCatalog.load_all()
	_catalog = CardCatalog.load_all()
	_upgrade_config = CardUpgrades.load_config()
	_debug_tokens_button.pressed.connect(_on_debug_tokens)
	_card_select.item_selected.connect(_on_card_selected)
	EventBus.save_loaded.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_build_box_section()
	_build_card_select()
	_build_upgrade_section()


# --- Loot boxes -------------------------------------------------------------

func _build_box_section() -> void:
	for child in _box_list.get_children():
		child.queue_free()
	for box in _boxes:
		var box_id := str(box["id"])
		var box_cost: Dictionary = box.get("cost", {})
		var currency := "AL67X" if str(box_cost.get("currency", "")) == "tokens" else "Blobs"
		var owned := EconomyService.get_loot_box_count(box_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var buy_button := Button.new()
		buy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy_button.custom_minimum_size = Vector2(0, 96)
		buy_button.add_theme_font_size_override("font_size", 20)
		buy_button.text = "%s — %d %s\nOdds: %s" % [
			str(box.get("name", "?")), int(box_cost.get("amount", 0)), currency,
			LootBoxCatalog.odds_text(box),
		]
		buy_button.pressed.connect(_on_buy_box.bind(box_id))
		row.add_child(buy_button)
		var open_button := Button.new()
		open_button.name = "Open_%s" % box_id
		open_button.custom_minimum_size = Vector2(160, 96)
		open_button.add_theme_font_size_override("font_size", 20)
		open_button.text = "OPEN (%d)" % owned
		open_button.disabled = owned <= 0
		open_button.pressed.connect(_on_open_box.bind(box_id))
		row.add_child(open_button)
		_box_list.add_child(row)


func _on_buy_box(box_id: String) -> void:
	var box := LootBoxCatalog.by_id(box_id)
	if EconomyService.purchase_loot_box(box):
		_result_label.text = "%s purchased!" % box.get("name", "?")
	else:
		_result_label.text = "Not enough %s." % ("AL67X Tokens" if str(box.get("cost", {}).get("currency", "")) == "tokens" else "Blobs")
	_refresh()


func _on_open_box(box_id: String) -> void:
	var result := LootBoxCatalog.open(box_id)
	if not bool(result.get("ok", false)):
		_result_label.text = "No %s to open." % box_id
		_refresh()
		return
	var reveal := get_tree().get_first_node_in_group("card_reveal")
	if reveal != null:
		reveal.show_card(result)
	_result_label.text = ""
	_refresh()


# --- Card upgrades ----------------------------------------------------------

func _upgradeable_cards() -> Array:
	var owned: Array = SaveService.get_value("cards.owned", {}).keys()
	return _catalog.filter(func(c: Dictionary) -> bool:
		return bool(c.get("base", false)) or owned.has(str(c.get("id", ""))))


func _build_card_select() -> void:
	var cards := _upgradeable_cards()
	var previous := _selected_card
	_card_select.clear()
	var selected_index := 0
	for i in range(cards.size()):
		var card: Dictionary = cards[i]
		_card_select.add_item("%s (%s)" % [str(card.get("name", "?")), str(card.get("rarity", "?"))])
		_card_select.set_item_metadata(i, str(card["id"]))
		if str(card["id"]) == previous:
			selected_index = i
	if cards.is_empty():
		_selected_card = ""
		return
	_card_select.select(selected_index)
	_selected_card = str(_card_select.get_item_metadata(selected_index))


func _on_card_selected(index: int) -> void:
	_selected_card = str(_card_select.get_item_metadata(index))
	_build_upgrade_section()


func _build_upgrade_section() -> void:
	for child in _upgrade_list.get_children():
		child.queue_free()
	if _selected_card == "":
		return
	var card: Dictionary = {}
	for c in _catalog:
		if str(c["id"]) == _selected_card:
			card = c
			break
	if card.is_empty():
		return
	for upgrade_type in CardUpgrades.types_for_card(card, _upgrade_config):
		var type_id := str(upgrade_type)
		var type_cfg: Dictionary = _upgrade_config.get("upgrade_types", {}).get(type_id, {})
		var level := CardUpgrades.get_level(_selected_card, type_id)
		var price := CardUpgrades.cost(type_id, level, _upgrade_config)
		var currency := "AL67X" if str(price["currency"]) == "tokens" else "Blobs"
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 76)
		button.add_theme_font_size_override("font_size", 20)
		button.text = "%s  Lv %d → %d   (%d %s)" % [
			str(type_cfg.get("name", type_id)), level, level + 1,
			int(price["amount"]), currency,
		]
		button.pressed.connect(_on_buy_upgrade.bind(type_id))
		_upgrade_list.add_child(button)


func _on_buy_upgrade(upgrade_type: String) -> void:
	if CardUpgrades.purchase(_selected_card, upgrade_type, _upgrade_config):
		_result_label.text = "Upgrade purchased!"
	else:
		var price := CardUpgrades.cost(upgrade_type, CardUpgrades.get_level(_selected_card, upgrade_type), _upgrade_config)
		_result_label.text = "Not enough %s." % ("AL67X Tokens" if str(price["currency"]) == "tokens" else "Blobs")
	_refresh()


# --- Tokens -----------------------------------------------------------------

func _on_debug_tokens() -> void:
	# SWAP-POINT: this debug button stands in for the real-money token
	# purchase UI (Play Billing / Stripe / Square). See EconomyService.
	EconomyService.purchase_tokens("debug_pack_100", 100)
	_result_label.text = "+100 AL67X Tokens (debug grant)"
	_refresh()
