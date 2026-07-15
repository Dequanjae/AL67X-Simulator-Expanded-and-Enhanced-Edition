extends Control
## Full-screen "NEW ALLAN!" reveal overlay (spec Section 6): over-the-top
## unlock moment — pops the new skin with a scale-in punch and prompts an
## immediate equip. Listens to EventBus.allan_unlocked.
## Phase 10 hooks the unlock audio sting; Phase 12 cranks the VFX further.

var _allan_id := ""

@onready var _portrait: TextureRect = $Center/Box/Portrait
@onready var _name_label: Label = $Center/Box/NameLabel
@onready var _equip_button: Button = $Center/Box/EquipButton
@onready var _later_button: Button = $Center/Box/LaterButton
@onready var _center: CenterContainer = $Center


func _ready() -> void:
	visible = false
	add_to_group("modal_overlay")
	_equip_button.pressed.connect(_on_equip)
	_later_button.pressed.connect(_close)
	EventBus.allan_unlocked.connect(_on_allan_unlocked)


func _on_allan_unlocked(allan_id: String) -> void:
	_allan_id = allan_id
	var entry := AllanSprites.entry(allan_id)
	if entry.is_empty():
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = AllanSprites.sheet_texture(allan_id)
	atlas.region = AllanSprites.frame_rect(0)
	_portrait.texture = atlas
	_name_label.text = "%s — Tier %d" % [str(entry.get("name", "?")), int(entry.get("tier", 1))]
	visible = true
	# Over-the-top scale-in punch.
	_center.pivot_offset = _center.size * 0.5
	_center.scale = Vector2(0.2, 0.2)
	var tween := create_tween()
	tween.tween_property(_center, "scale", Vector2(1.12, 1.12), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_center, "scale", Vector2.ONE, 0.12)


func _on_equip() -> void:
	FusionSystem.equip(_allan_id)
	_close()


func _close() -> void:
	visible = false
