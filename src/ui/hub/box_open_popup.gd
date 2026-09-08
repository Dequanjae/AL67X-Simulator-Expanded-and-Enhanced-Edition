class_name BoxOpenPopup
extends Control
## Box-opening popup — the motor loot box flow (user spec, 2026-09-08):
##   shop/earn → tap box (frame 1 art) → popup: closed motor (frame 2)
##   covered by the housing (frame 3) → tap → housing FALLS off screen
##   revealing the motor → rewards line up (2 cards + bonus Blobs/AL67X
##   Tokens) → tap again to dismiss.
## Frame cuts (all sheets identical): f1 x[0,407) f2 x[467,875) f3 x[951,1318).
## Sprite sheet: assets/sprites/Motor-LootBox/<ArtRarity>/Motor-box<N>.png
## Art rarity folders: Common Uncommon Rare Epic Legandary (user spelling).

const RARITY_COLORS := {
	"common": Color(0.78, 0.78, 0.78),
	"uncommon": Color(0.4, 0.85, 0.45),
	"rare": Color(0.35, 0.65, 1.0),
	"epic": Color(0.75, 0.4, 1.0),
	"legendary": Color(1.0, 0.75, 0.25),
}
## art folder per rarity id (box JSON art_rarity) — user's folder names
const ART_FOLDERS := {
	"common": ["Common", 0],
	"uncommon": ["Uncommon", 1],
	"rare": ["Rare", 2],
	"epic": ["Epic", 3],
	"legendary": ["Legandary", 4],
}
const FRAMES := [
	Rect2(0, 0, 407, 539),
	Rect2(467, 0, 408, 539),
	Rect2(951, 148, 367, 368),
]
const FALL_TIME := 0.7

var _result: Dictionary = {}
var _opened := false
var _dismissing := false

@onready var _dim: ColorRect = $Dim
@onready var _popup: Control = $Center/Popup
@onready var _motor: TextureRect = $Center/Popup/VB/BoxArt/Motor
@onready var _housing: TextureRect = $Center/Popup/VB/BoxArt/Housing
@onready var _tap_hint: Label = $Center/Popup/VB/TapHint
@onready var _rewards_box: VBoxContainer = $Center/Popup/VB/RewardsBox
@onready var _cards_label: Label = $Center/Popup/VB/RewardsBox/CardsLabel
@onready var _currency_label: Label = $Center/Popup/VB/RewardsBox/CurrencyLabel
@onready var _close_button: Button = $Center/Popup/VB/RewardsBox/CloseButton

## Sheet path for a rarity id, e.g. "epic" -> .../Epic/Motor-box3.png
static func sheet_path(art_rarity: String) -> String:
	var entry: Array = ART_FOLDERS.get(String(art_rarity).to_lower(), ART_FOLDERS["common"])
	return "res://assets/sprites/Motor-LootBox/%s/Motor-box%d.png" % [entry[0], entry[1]]


static func frame_texture(art_rarity: String, frame: int) -> AtlasTexture:
	var sheet: Texture2D = load(sheet_path(art_rarity))
	var tex := AtlasTexture.new()
	tex.atlas = sheet
	tex.region = FRAMES[frame]
	return tex


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("box_open_popup")
	_dim.gui_input.connect(_on_dim_input)
	_close_button.pressed.connect(_dismiss)


## result = LootBoxCatalog.open() dict. Shows closed box; first tap drops
## the housing, second dismisses.
func open_with_result(result: Dictionary) -> void:
	_result = result
	_opened = false
	_dismissing = false
	var box: Dictionary = result.get("box", {})
	var art_rarity := str(box.get("art_rarity", "common"))
	# motor (frame 2) sits UNDER the housing (frame 3) — both centered so
	# the cover aligns with the reveal.
	_motor.texture = frame_texture(art_rarity, 1)
	_housing.texture = frame_texture(art_rarity, 2)
	_housing.visible = true
	_housing.position = Vector2.ZERO
	_housing.rotation = 0.0
	_housing.modulate.a = 1.0
	_rewards_box.visible = false
	_tap_hint.text = "TAP TO OPEN"
	_tap_hint.visible = true
	visible = true
	_popup.pivot_offset = _popup.size * 0.5
	_popup.scale = Vector2(0.2, 0.2)
	var tween := create_tween()
	tween.tween_property(_popup, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_popup, "scale", Vector2.ONE, 0.1)


func _on_dim_input(event: InputEvent) -> void:
	if _dismissing:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _opened:
			_reveal()
		else:
			_dismiss()


## Housing falls off screen with spin + fade, rewards pop in.
func _reveal() -> void:
	_opened = true
	_tap_hint.visible = false
	AudioDirector.play_sfx("box_open")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_housing, "position:y", _housing.position.y + 900.0, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_housing, "rotation", 2.5, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_housing, "modulate:a", 0.0, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(FALL_TIME).timeout
	_show_rewards()


func _show_rewards() -> void:
	var cards: Array = _result.get("cards", [])
	var rarities: Array = _result.get("rarities", [])
	var duplicates: Array = _result.get("duplicates", [])
	var parts: PackedStringArray = []
	for i in range(cards.size()):
		var card: Dictionary = cards[i]
		var rarity := str(rarities[i]) if i < rarities.size() else "common"
		var dupe := bool(duplicates[i]) if i < duplicates.size() else false
		var tag := "DUP" if dupe else "NEW"
		parts.append("%s: %s [%s]" % [tag, str(card.get("name", "?")), rarity.to_upper()])
	_cards_label.text = "\n".join(parts)
	var rewards: Dictionary = _result.get("rewards", {})
	_currency_label.text = "+%d Blobs   +%d AL67X Tokens" % [
		int(rewards.get("blobs", 0)), int(rewards.get("tokens", 0))]
	_rewards_box.visible = true
	_rewards_box.modulate.a = 0.0
	_rewards_box.scale = Vector2(0.6, 0.6)
	var tw := create_tween()
	tw.tween_property(_rewards_box, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(_rewards_box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _dismiss() -> void:
	if _dismissing:
		return
	_dismissing = true
	var tw := create_tween()
	tw.tween_property(_popup, "modulate:a", 0.0, 0.18)
	tw.tween_callback(_on_dismiss_done)


func _on_dismiss_done() -> void:
	visible = false
	_popup.modulate.a = 1.0
	_dismissing = false
