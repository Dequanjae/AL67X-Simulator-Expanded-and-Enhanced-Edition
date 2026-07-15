extends Control
## Full-screen "CARD UNLOCKED!" reveal for loot box pulls. Same over-the-top
## language as the Allan reveal: dim, rarity-colored punch-in card, tap to
## dismiss. Found via the "card_reveal" group (shop tab calls show_card()).
## Phase 10 hooks the audio sting.

const RARITY_COLORS := {
	"common": Color(0.78, 0.78, 0.78),
	"rare": Color(0.35, 0.65, 1.0),
	"epic": Color(0.75, 0.4, 1.0),
	"legendary": Color(1.0, 0.75, 0.25),
}

@onready var _title_label: Label = $Center/Box/TitleLabel
@onready var _name_label: Label = $Center/Box/NameLabel
@onready var _desc_label: Label = $Center/Box/DescLabel
@onready var _count_label: Label = $Center/Box/CountLabel
@onready var _close_button: Button = $Center/Box/CloseButton
@onready var _center: CenterContainer = $Center


func _ready() -> void:
	visible = false
	add_to_group("card_reveal")
	add_to_group("modal_overlay")
	_close_button.pressed.connect(func() -> void: visible = false)


func show_card(result: Dictionary) -> void:
	var card: Dictionary = result.get("card", {})
	var rarity := str(result.get("rarity", card.get("rarity", "common")))
	var color: Color = RARITY_COLORS.get(rarity, Color.WHITE)
	_title_label.text = "DUPLICATE!" if bool(result.get("duplicate", false)) else "CARD UNLOCKED!"
	_name_label.text = "%s (%s)" % [str(card.get("name", "?")), rarity]
	_name_label.add_theme_color_override("font_color", color)
	_desc_label.text = str(card.get("description", ""))
	_count_label.text = "Owned: x%d" % int(result.get("count", 1))
	visible = true
	_center.pivot_offset = _center.size * 0.5
	_center.scale = Vector2(0.2, 0.2)
	var tween := create_tween()
	tween.tween_property(_center, "scale", Vector2(1.12, 1.12), 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_center, "scale", Vector2.ONE, 0.1)
