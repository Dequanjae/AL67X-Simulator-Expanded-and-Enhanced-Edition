class_name LevelUpController
extends Node
## LevelUpController — 1-of-N card choice on level-up (auto-shooter
## roguelite style). Same contract as before the UI overhaul (still rolls
## options, applies the chosen effect, emits card_choice_presented /
## card_chosen, still pauses the tree) — only the PRESENTATION moved to
## HTML (the shared web_ui/shared/card_select popup, reused as-is).
##
## Card_choice_presented is already rebroadcast to every mounted webview by
## UIBridge as "card_choices". The inbound pick, though, needs to apply a
## real gameplay effect (PlayerStats.apply_effect) that UIBridge has no
## business knowing about — so this listens directly to the run's
## WebViewHost.ipc_message signal for "card_choice" (same pattern
## hub.gd uses for "start_run"/"sign_in") instead of going through
## UIBridge's generic routing.

## Assigned by RunController.
var stats: PlayerStats

var _all_cards: Array = []
var _pending := 0
var _options: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_all_cards = CardCatalog.load_all()
	EventBus.player_leveled_up.connect(_on_player_leveled_up)


## Call from RunController: connect this to the run's WebViewHost so the
## HTML card-select popup's pick reaches _on_card_choice_message.
func bind_web_view(web: WebViewHost) -> void:
	web.ipc_message.connect(_on_ipc_message)


func _on_ipc_message(message: String) -> void:
	var data: Variant = JSON.parse_string(message)
	if data is Dictionary and str(data.get("type", "")) == "card_choice":
		_on_card_choice_message(str(data.get("card_id", "")))


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
	EventBus.card_choice_presented.emit(_options.map(func(c: Dictionary) -> String: return str(c.get("id", ""))))


func _on_card_choice_message(card_id: String) -> void:
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
	if _pending > 0:
		_present()
	else:
		get_tree().paused = false
