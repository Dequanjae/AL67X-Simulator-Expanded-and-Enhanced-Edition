extends PanelContainer

const RARITY_COLORS := {
	"common": Color(0.75, 0.75, 0.75),
	"rare": Color(0.35, 0.65, 1.0),
	"epic": Color(0.75, 0.4, 1.0),
	"legendary": Color(1.0, 0.75, 0.25),
}

var stats: PlayerStats

var _all_cards: Array = []
var _pending := 0
var _options: Array = []
var _rng := RandomNumberGenerator.new()

@onready var _buttons: Array[Button] = [
	$Box/Option1, $Box/Option2, $Box/Option3,
]


func _ready() -> void:
	visible = false
	_rng.randomize()
	_all_cards = CardCatalog.load_all()
	for i in range(_buttons.size()):
		_buttons[i].pressed.connect(_on_option_pressed.bind(i))
	EventBus.player_leveled_up.connect(_on_player_leveled_up)


func _on_player_leveled_up(_new_level: int) -> void:
	_pending += 1
	if not visible:
		_present()


func _present() -> void:
	var owned: Array = SaveService.get_value("cards.owned", {}).keys()
	var pool := CardCatalog.level_up_pool(_all_cards, owned)
	_options = CardCatalog.roll_options(pool, 3, _rng)
	if _options.is_empty():
		_pending = 0
		return
	for i in range(_buttons.size()):
		if i < _options.size():
			var card: Dictionary = _options[i]
			var rarity := str(card.get("rarity", "common"))
			_buttons[i].text = "%s\n%s" % [str(card.get("name", "?")), str(card.get("description", ""))]
			_buttons[i].modulate = RARITY_COLORS.get(rarity, Color.WHITE)
			_buttons[i].visible = true
		else:
			_buttons[i].visible = false
	visible = true
	get_tree().paused = true
	EventBus.card_choice_presented.emit(_options.map(func(c: Dictionary) -> String: return str(c.get("id", ""))))


func _on_option_pressed(index: int) -> void:
	if index >= _options.size():
		return
	var card: Dictionary = _options[index]
	if stats != null:
		stats.apply_effect(card.get("effect", {}))
	EventBus.card_chosen.emit(str(card.get("id", "")))
	_pending -= 1
	if _pending > 0:
		_present()
	else:
		visible = false
		get_tree().paused = false
