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
	# Never present over the death panel or a run that already ended —
	# _end_run force-unpauses and swaps the scene; presenting then races
	# the scene change and leaves a half-torn UI. The run is over; the
	# pending choice is simply dropped.
	if get_tree().current_scene == null or not is_instance_valid(get_tree().current_scene):
		_pending -= 1
		return
	var rc = get_tree().current_scene.get_node_or_null("RunController")
	if rc != null and ("_ended" in rc) and bool(rc.get("_ended")):
		_pending -= 1
		return
	if not visible:
		_present()


func _present() -> void:
	# Arbitration: exactly one pause-owner. If the death panel owns the
	# pause (hearts hit 0 while a level-up was pending), the death flow
	# unpauses on its own buttons — we defer instead of fighting it.
	if _death_owns_pause():
		return
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

## Death wants the screen: hide and drop pending choices WITHOUT applying
## any card. (The old code called _on_option_pressed(-1) — GDScript's
## negative indexing made that APPLY the last card on death.)
func dismiss_for_death() -> void:
	_pending = 0
	visible = false


## Re-present a pending choice if one was deferred (e.g. revive via ad).
func present_if_pending() -> void:
	if _pending > 0 and not visible and not _death_owns_pause():
		_present()


## True when the death panel (or another end-of-run overlay) is up.
func _death_owns_pause() -> bool:
	var scene := get_tree().current_scene
	if scene == null or not is_instance_valid(scene):
		return true
	var dp = scene.get_node_or_null("HUD/DeathPanel")
	if dp != null and (dp as Control).visible:
		return true
	var ao = scene.get_node_or_null("HUD/AscendOverlay")
	if ao != null and (ao as Control).visible:
		return true
	return false
