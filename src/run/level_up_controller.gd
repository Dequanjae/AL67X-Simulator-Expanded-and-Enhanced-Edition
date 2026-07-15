class_name LevelUpController
extends Node
## LevelUpController — 1-of-N card choice on level-up (auto-shooter
## roguelite style). Presents 3 card options in a native Godot popup panel.
## Tree is paused while the popup is open.

## Assigned by RunController.
var stats: PlayerStats

var _all_cards: Array = []
var _pending := 0
var _options: Array = []
var _rng := RandomNumberGenerator.new()
var _popup: Panel


func _ready() -> void:
	_rng.randomize()
	_all_cards = CardCatalog.load_all()
	EventBus.player_leveled_up.connect(_on_player_leveled_up)


func _on_player_leveled_up(_new_level: int) -> void:
	_pending += 1
	if _pending == 1:
		_present()


func _present() -> void:
	var owned: Array = SaveService.get_value("cards.owned", {}).keys()
	var pool := CardCatalog.level_up_pool(_all_cards, owned)
	_options = CardCatalog.roll_options(pool, 3, _rng)
	if _options.is_empty():
		_pending = 0
		return
	get_tree().paused = true
	_build_popup()
	EventBus.card_choice_presented.emit(_options.map(func(c: Dictionary) -> String: return str(c.get("id", ""))))


func _build_popup() -> void:
	_popup = Panel.new()
	_popup.size = Vector2(1280, 720)
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.72)
	_popup.add_theme_stylebox_override("panel", bg)
	add_child(_popup)

	var title := Label.new()
	title.text = "CHOOSE A CARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(1280 / 2 - 120, 720 / 2 - 120)
	title.size = Vector2(240, 30)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#ffd400"))
	_popup.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.position = Vector2(1280 / 2 - 260, 720 / 2 - 70)
	hbox.size = Vector2(520, 140)
	hbox.add_theme_constant_override("separation", 12)
	_popup.add_child(hbox)

	var i := 0
	for card in _options:
		var btn := _make_card_button(card, i)
		btn.pressed.connect(func(card_id: String = str(card.get("id", ""))) -> void:
			_on_card_chosen(card_id))
		hbox.add_child(btn)
		i += 1


func _make_card_button(card: Dictionary, index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 140)
	btn.size = Vector2(160, 140)
	btn.text = str(card.get("name", "Card %d" % (index + 1)))
	var desc := str(card.get("description", ""))
	if not desc.is_empty():
		btn.text += "\n" + desc

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fffaf0")
	style.border_color = Color("#1c1c1c")
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_color_override("font_color", Color("#1c1c1c"))
	btn.add_theme_font_size_override("font_size", 14)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return btn


func _on_card_chosen(card_id: String) -> void:
	var card: Dictionary = {}
	for option in _options:
		if str(option.get("id", "")) == card_id:
			card = option
			break
	if card.is_empty():
		return
	if stats != null:
		stats.apply_effect(card.get("effect", {}))
	EventBus.card_chosen.emit(card_id)
	_pending -= 1

	if _popup:
		_popup.queue_free()
		_popup = null

	if _pending > 0:
		_present()
	else:
		get_tree().paused = false
