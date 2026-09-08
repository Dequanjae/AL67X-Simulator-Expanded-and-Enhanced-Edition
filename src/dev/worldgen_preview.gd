@tool
class_name WorldgenPreview
extends Node3D
## In-editor worldgen preview tool — open scenes/tools/worldgen_preview.tscn
## and tweak the layout LIVE with sliders:
##   level, variant, algorithm, arena width/depth, prop density, min
##   clearance, spawn clear radius.
## Runs the REAL Rust LevelGeneratorRs + LevelBuilder at editor time, so
## what you see is exactly what a run generates for those parameters.
## Variant offsets the generation level (each +1 = a different deterministic
## layout; it also bumps the engine's per-level arena growth slightly —
## the live arena readout in the stats line shows the effective size).
## NOTE: no autoloads run at @tool time — data loads via JsonData (plain IO).

const ALGORITHMS: Array[String] = ["scatter", "aisles", "clusters", "rings", "dungeon"]

@export var level := 1:
	set(v):
		level = clampi(v, 1, 99)
		_regen()
## Different deterministic layouts for the same params (0-12; higher = a
## slightly larger grown arena, shown live in the stats line).
@export_range(0, 12) var variant := 0:
	set(v):
		variant = v
		_regen()
@export_range(0.0, 0.12, 0.002) var prop_density := 0.03:
	set(v):
		prop_density = v
		_regen()
@export_range(20.0, 120.0, 2.0) var arena_width := 44.0:
	set(v):
		arena_width = v
		_regen()
@export_range(20.0, 120.0, 2.0) var arena_depth := 40.0:
	set(v):
		arena_depth = v
		_regen()
@export_range(2.5, 8.0, 0.1) var min_clearance := 3.4:
	set(v):
		min_clearance = v
		_regen()
@export_range(2.0, 10.0, 0.5) var spawn_clear_radius := 4.5:
	set(v):
		spawn_clear_radius = v
		_regen()

var _ui_ready := false
var _regen_queued := false
var _algo := "scatter"

@onready var _level_slider: HSlider = $UI/Panel/Controls/LevelRow/LevelSlider
@onready var _variant_slider: HSlider = $UI/Panel/Controls/VariantRow/VariantSlider
@onready var _algo_option: OptionButton = $UI/Panel/Controls/AlgoRow/AlgoOption
@onready var _arena_w_slider: HSlider = $UI/Panel/Controls/ArenaWRow/ArenaWSlider
@onready var _arena_d_slider: HSlider = $UI/Panel/Controls/ArenaDRow/ArenaDSlider
@onready var _density_slider: HSlider = $UI/Panel/Controls/DensityRow/DensitySlider
@onready var _clearance_slider: HSlider = $UI/Panel/Controls/ClearanceRow/ClearanceSlider
@onready var _spawn_clear_slider: HSlider = $UI/Panel/Controls/SpawnClearRow/SpawnClearSlider
@onready var _rebuild_button: Button = $UI/Panel/Controls/RebuildRow/RebuildButton
@onready var _stats_label: Label = $UI/Panel/Controls/StatsLabel


func _ready() -> void:
	_algo_option.clear()
	for algo in ALGORITHMS:
		_algo_option.add_item(algo)
	_algo_option.selected = 0

	_level_slider.value_changed.connect(func(v: float) -> void:
		level = int(v))
	_variant_slider.value_changed.connect(func(v: float) -> void:
		variant = int(v))
	_algo_option.item_selected.connect(func(i: int) -> void:
		_algo = ALGORITHMS[i]
		_regen())
	_arena_w_slider.value_changed.connect(func(v: float) -> void:
		arena_width = v)
	_arena_d_slider.value_changed.connect(func(v: float) -> void:
		arena_depth = v)
	_density_slider.value_changed.connect(func(v: float) -> void:
		prop_density = v)
	_clearance_slider.value_changed.connect(func(v: float) -> void:
		min_clearance = v)
	_spawn_clear_slider.value_changed.connect(func(v: float) -> void:
		spawn_clear_radius = v)
	_rebuild_button.pressed.connect(func() -> void: _regen())

	_sync_ui_from_vars()
	_ui_ready = true
	_regen()


## Coalesce rapid slider changes into one deferred rebuild per frame.
func _regen() -> void:
	if not _ui_ready or _regen_queued:
		return
	_regen_queued = true
	_do_regen.call_deferred()


func _do_regen() -> void:
	_regen_queued = false
	var builder: Node = get_node_or_null("PreviewRoot/Builder")
	if builder == null:
		return
	var theme := _theme_from_params()
	var gen_level := level + variant
	var layout := _generate(gen_level, theme)
	if not layout.get("ok", false):
		_stats_label.text = "LevelGeneratorRs unavailable — is the Rust extension loaded?"
		return
	# Builder.build() clears its own children first.
	builder.build(layout, theme)
	var arena: Vector2 = layout["arena_size"]
	_stats_label.text = "%s  gen lvl %d  arena %.0fx%.0f  props %d  reachable %.2f" % [
		_algo, gen_level, arena.x, arena.y,
		layout.get("props", []).size(), float(layout.get("reachable_ratio", 0.0))]
	print("WORLDGEN PREVIEW: %s" % _stats_label.text)


func _generate(lvl: int, theme: Dictionary) -> Dictionary:
	if not ClassDB.class_exists("LevelGeneratorRs"):
		push_warning("LevelGeneratorRs not available")
		return {"ok": false}
	return ClassDB.instantiate("LevelGeneratorRs").generate(lvl, theme)


## Load a real theme file for its colors + props, then override the
## generation block with the slider values (keeps prop meshes authentic).
func _theme_from_params() -> Dictionary:
	var theme := {}
	for path in JsonData.list_files("res://data/levels", "json"):
		var t: Variant = JsonData.load_json(path)
		if t is Dictionary and str(t.get("id", "")) == "shop_aisles":
			theme = t
			break
	if theme.is_empty():
		theme = {
			"id": "preview",
			"colors": {"floor": "#4d4a43", "floor_alt": "#45423c", "wall": "#54616e", "accent": "#7fa8c9"},
			"props": [{"shape": "box", "size": [1.0, 1.0, 1.0], "color": "#8B7355", "weight": 1}],
		}
	theme["generation"] = {
		"algorithm": _algo,
		"arena_size": [arena_width, arena_depth],
		"prop_density": prop_density,
		"min_clearance": min_clearance,
		"spawn_clear_radius": spawn_clear_radius,
	}
	return theme


func _sync_ui_from_vars() -> void:
	_level_slider.value = float(level)
	_variant_slider.value = float(variant)
	_arena_w_slider.value = arena_width
	_arena_d_slider.value = arena_depth
	_density_slider.value = prop_density
	_clearance_slider.value = min_clearance
	_spawn_clear_slider.value = spawn_clear_radius