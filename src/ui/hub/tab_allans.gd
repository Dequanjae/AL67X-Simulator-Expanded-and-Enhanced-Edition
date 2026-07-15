extends HBoxContainer
## Hub tab: Allans — fusion grid + energy + skin management (spec Section 6).
## CANDY-CRUSH INTERACTION: drag a tile onto an orthogonal neighbor to SWAP
## them; any 3 same-tier Allans aligned in a row/column auto-merge into 1
## Allan of tier+1 (1 energy per merge, cascades included). Tiles render
## the actual skin sprites (cached thumbnails, not full sheets).

var _config: Dictionary = {}
var _drag_index := -1
var _tiles: Array[TextureRect] = []
var _grid_width := 4
var _tick_accum := 0.0

@onready var _portrait: TextureRect = $LeftBox/Header/Portrait
@onready var _equipped_label: Label = $LeftBox/Header/HeaderBox/EquippedLabel
@onready var _owned_label: Label = $LeftBox/Header/HeaderBox/OwnedLabel
@onready var _energy_label: Label = $LeftBox/EnergyRow/EnergyLabel
@onready var _refill_button: Button = $LeftBox/EnergyRow/RefillButton
@onready var _grid: GridContainer = $Grid
@onready var _owned_row: HBoxContainer = $LeftBox/OwnedScroll/OwnedRow
@onready var _status_label: Label = $LeftBox/StatusLabel


func _ready() -> void:
	_config = FusionSystem.load_config()
	_grid_width = int(_config.get("grid_width", 4))
	_grid.columns = _grid_width
	_build_grid_tiles()
	_refill_button.pressed.connect(_on_refill)
	EventBus.save_loaded.connect(_refresh_all)
	EventBus.allan_equipped.connect(func(_id: String) -> void: _refresh_all())
	EventBus.allan_unlocked.connect(func(_id: String) -> void: _refresh_all())
	EventBus.fusion_energy_changed.connect(func(_c: int, _m: int) -> void: _refresh_energy())
	FusionSystem.sync_energy(_config)
	_status_label.text = "Drag to swap — line up 3 matching Allans!"
	_refresh_all()


func _process(delta: float) -> void:
	if not visible:
		return
	_tick_accum += delta
	if _tick_accum >= 1.0:
		_tick_accum = 0.0
		FusionSystem.sync_energy(_config)
		_refresh_energy()


# ---------------------------------------------------------------------------
# Swipe-chain input (touch + mouse-as-touch)
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _overlay_open():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_drag(_tile_at(event.position))
		else:
			_end_drag()
	elif event is InputEventScreenDrag and _drag_index >= 0:
		var over := _tile_at(event.position)
		if over >= 0 and over != _drag_index:
			_drag_to(over)


func _overlay_open() -> bool:
	for overlay in get_tree().get_nodes_in_group("modal_overlay"):
		if overlay.visible:
			return true
	return false


func _tile_at(screen_point: Vector2) -> int:
	for i in range(_tiles.size()):
		if _tiles[i].get_global_rect().has_point(screen_point):
			return i
	return -1


func _begin_drag(index: int) -> void:
	_drag_index = index
	_refresh_grid()


## Candy-crush move: dragging onto an ORTHOGONAL neighbor swaps the tiles,
## then any aligned 3-runs auto-merge (middle tile becomes tier+1).
func _drag_to(index: int) -> void:
	if _drag_index < 0 or not FusionSystem.are_adjacent(_drag_index, index, _grid_width):
		return
	FusionSystem.swap_tiles(_drag_index, index, _config)
	_drag_index = -1
	var results := FusionSystem.resolve_matches(_config)
	if results.is_empty():
		_status_label.text = "Line up 3 matching Allans!"
		_refresh_all()
		return
	var best_tier := 0
	for result in results:
		best_tier = maxi(best_tier, int(result.get("new_tier", 0)))
	_status_label.text = "Fused into Tier %d!" % best_tier
	if FusionSystem.get_energy() < 1:
		_status_label.text += "  (out of energy)"
	_refresh_all()
	# Merge juice: punch the result tiles.
	for result in results:
		var index_hit := int(result.get("result_index", -1))
		if index_hit >= 0 and index_hit < _tiles.size():
			var tile := _tiles[index_hit]
			tile.pivot_offset = tile.size * 0.5
			tile.scale = Vector2(0.3, 0.3)
			var tween := create_tween()
			tween.tween_property(tile, "scale", Vector2(1.25, 1.25), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(tile, "scale", Vector2.ONE, 0.1)


func _end_drag() -> void:
	if _drag_index >= 0:
		_drag_index = -1
		_refresh_grid()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _build_grid_tiles() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_tiles.clear()
	for i in range(FusionSystem.grid_size(_config)):
		var tile := TextureRect.new()
		tile.custom_minimum_size = Vector2(0, 92)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_child(tile)
		_tiles.append(tile)


func _refresh_all() -> void:
	_refresh_header()
	_refresh_energy()
	_refresh_grid()
	_refresh_owned_row()


func _refresh_header() -> void:
	var equipped_id := str(SaveService.get_value("allans.equipped", "player1"))
	var entry := AllanSprites.entry(equipped_id)
	if not entry.is_empty():
		_portrait.texture = AllanSprites.tier_thumbnail(int(entry.get("tier", 1)), 150)
		_equipped_label.text = "%s (Tier %d)" % [str(entry.get("name", "?")), int(entry.get("tier", 1))]
	var owned: Array = SaveService.get_value("allans.owned", [])
	_owned_label.text = "Owned: %d / %d" % [owned.size(), AllanSprites.registry().get("allans", []).size()]


func _refresh_energy() -> void:
	var energy := FusionSystem.get_energy()
	var energy_max := int(_config.get("energy_max", 5))
	var next := FusionSystem.seconds_to_next_energy(_config)
	if next < 0:
		_energy_label.text = "Energy: %d / %d (full)" % [energy, energy_max]
	else:
		@warning_ignore("integer_division")
		_energy_label.text = "Energy: %d / %d (+1 in %d:%02d)" % [energy, energy_max, next / 60, next % 60]
	_refill_button.text = "Refill — %d AL67X" % int(_config.get("token_refill_cost", 20))
	_refill_button.disabled = energy >= energy_max


func _refresh_grid() -> void:
	var grid := FusionSystem.get_grid(_config)
	for i in range(_tiles.size()):
		var tier := int(grid[i])
		var tile := _tiles[i]
		tile.texture = AllanSprites.tier_thumbnail(tier)
		if i == _drag_index:
			tile.modulate = Color(1.35, 1.35, 0.9)
			tile.scale = Vector2(1.08, 1.08)
		else:
			tile.modulate = Color.WHITE
			tile.scale = Vector2.ONE
		tile.pivot_offset = tile.size * 0.5
		tile.tooltip_text = "Tier %d" % tier


func _refresh_owned_row() -> void:
	for child in _owned_row.get_children():
		child.queue_free()
	var owned: Array = SaveService.get_value("allans.owned", [])
	var equipped_id := str(SaveService.get_value("allans.equipped", "player1"))
	for allan in AllanSprites.registry().get("allans", []):
		var allan_id := str(allan.get("id", ""))
		if not owned.has(allan_id):
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(84, 72)
		button.icon = AllanSprites.tier_thumbnail(int(allan.get("tier", 1)), 56)
		button.expand_icon = true
		if allan_id == equipped_id:
			button.modulate = Color(0.65, 1.0, 0.7)
		button.tooltip_text = str(allan.get("name", "?"))
		button.pressed.connect(func() -> void: FusionSystem.equip(allan_id))
		_owned_row.add_child(button)


func _on_refill() -> void:
	if FusionSystem.refill_with_tokens(_config):
		_status_label.text = "Energy refilled!"
	else:
		_status_label.text = "Not enough AL67X Tokens."
	_refresh_energy()
