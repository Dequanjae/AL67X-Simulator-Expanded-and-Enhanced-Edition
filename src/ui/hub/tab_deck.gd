extends VBoxContainer
## Hub tab: Player/Deck — manage the equipped 6-card stack. Lists base +
## owned cards; tap to equip/unequip. Persists to cards.equipped. Shows
## per-card shop upgrade levels.

const DECK_SIZE := 6

var _catalog: Array = []
var _upgrade_config: Dictionary = {}

@onready var _equipped_label: Label = $EquippedLabel
@onready var _list: VBoxContainer = $Scroll/CardList


func _ready() -> void:
	_catalog = CardCatalog.load_all()
	_upgrade_config = CardUpgrades.load_config()
	EventBus.save_loaded.connect(_refresh)
	EventBus.card_unlocked.connect(func(_id: String) -> void: _refresh())
	EventBus.purchase_completed.connect(func(_id: String) -> void: _refresh())
	_refresh()


func _available_cards() -> Array:
	var owned: Array = SaveService.get_value("cards.owned", {}).keys()
	return _catalog.filter(func(c: Dictionary) -> bool:
		return bool(c.get("base", false)) or owned.has(str(c.get("id", ""))))


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var equipped: Array = SaveService.get_value("cards.equipped", [])
	_equipped_label.text = "Equipped: %d / %d" % [equipped.size(), DECK_SIZE]
	for card in _available_cards():
		var card_id := str(card["id"])
		var is_equipped: bool = equipped.has(card_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 84)
		button.add_theme_font_size_override("font_size", 22)
		var upgrade_bits: PackedStringArray = []
		for upgrade_type in CardUpgrades.types_for_card(card, _upgrade_config):
			var level := CardUpgrades.get_level(card_id, str(upgrade_type))
			if level > 0:
				upgrade_bits.append("%s+%d" % [str(upgrade_type).left(3), level])
		var suffix := ""
		if not upgrade_bits.is_empty():
			suffix = "  [%s]" % ", ".join(upgrade_bits)
		var count := int(SaveService.get_value("cards.owned.%s.count" % card_id, 0))
		if count > 1:
			suffix += "  x%d" % count
		button.text = "%s %s (%s) — %s%s" % [
			"[E]" if is_equipped else "[  ]",
			str(card.get("name", "?")), str(card.get("rarity", "?")),
			str(card.get("description", "")), suffix,
		]
		if is_equipped:
			button.modulate = Color(0.65, 1.0, 0.7)
		button.pressed.connect(_on_card_pressed.bind(card_id))
		_list.add_child(button)


func _on_card_pressed(card_id: String) -> void:
	var equipped: Array = SaveService.get_value("cards.equipped", [])
	if equipped.has(card_id):
		equipped.erase(card_id)
	elif equipped.size() < DECK_SIZE:
		equipped.append(card_id)
	else:
		return  # stack full
	SaveService.set_value("cards.equipped", equipped)
	EventBus.deck_changed.emit(equipped)
	_refresh()
