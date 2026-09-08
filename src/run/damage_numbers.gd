class_name DamageNumbers
extends Node3D
## Pooled floating combat text: damage numbers on enemy hits + big popup
## words for powerups ("SUCC!", "FREEZE!", "GOON MODE!"...). Label3D pool,
## one tween per pop, billboarded.

const POOL_SIZE := 28

var _labels: Array[Label3D] = []
var _next := 0
var _rng := RandomNumberGenerator.new()
## Runtime load (NOT preload): a parse-time preload of a font that failed to
## import in a fresh CI environment kills this whole script at load -> black
## screen (same failure class as the July run_controller bug). Runtime load
## + null check degrades to the default font instead.
var _font: Font = load("res://assets/UI/fonts/Clash-Bold.ttf")


func _ready() -> void:
	_rng.randomize()
	for i in range(POOL_SIZE):
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		# alpha_cut MUST stay 0 (transparent pass). With DISCARD (1) the label
		# renders in the OPAQUE pass, where the unshaded floor draws after it
		# and paints over it -> "numbers under the floor".
		label.alpha_cut = 0
		if _font != null:
			label.font = _font
		label.fixed_size = false
		label.font_size = 64
		label.outline_size = 14
		label.pixel_size = 0.01
		label.visible = false
		add_child(label)
		_labels.append(label)
	EventBus.enemy_hit.connect(_on_enemy_hit)


func _on_enemy_hit(_enemy_id: String, damage: float, world_pos: Vector3) -> void:
	# One decimal of precision ("12.5"), whole numbers stay clean ("12").
	var text := ("%.1f" % damage) if absf(damage - roundf(damage)) > 0.049 else str(int(roundf(damage)))
	pop(world_pos, text, Color(1.0, 0.95, 0.6), 1.0)


## Big flashy word popup (powerups etc.).
func announce(world_pos: Vector3, text: String, color := Color(1.0, 0.8, 0.2)) -> void:
	pop(world_pos + Vector3(0, 0.8, 0), text, color, 2.4)


func pop(world_pos: Vector3, text: String, color: Color, scale_mult := 1.0) -> void:
	if not GameSettings.damage_numbers():
		return
	var label := _labels[_next]
	_next = (_next + 1) % POOL_SIZE
	label.text = text
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 1)
	label.global_position = world_pos + Vector3(_rng.randf_range(-0.3, 0.3), 1.2, _rng.randf_range(-0.2, 0.2))
	label.visible = true
	# Juice: punch-in with overshoot, arc drift, wobble, fade.
	label.scale = Vector3.ONE * 0.2
	label.rotation.z = 0.0
	var drift := Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(1.3, 1.9), 0)
	var wobble := _rng.randf_range(-0.18, 0.18)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector3.ONE * scale_mult * 1.25, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "rotation:z", wobble, 0.16)
	tween.chain().set_parallel(true)
	tween.tween_property(label, "scale", Vector3.ONE * scale_mult, 0.12)
	tween.tween_property(label, "global_position", label.global_position + drift, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "rotation:z", -wobble * 0.5, 0.6)
	tween.tween_property(label, "modulate", Color(color.r, color.g, color.b, 0.0), 0.55).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void: label.visible = false)
