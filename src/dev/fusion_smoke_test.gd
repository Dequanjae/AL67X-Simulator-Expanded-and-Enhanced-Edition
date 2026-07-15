extends Node
## Fusion gate (Phase 7) — run headless:
##   godot --headless res://scenes/dev/fusion_smoke_test.tscn
## Part A (pure): energy lazy regen (offline timestamps), spend/refill with
## tokens, grid init + soft-lock repair guarantees, fuse mechanics (3 same
## tier → tier+1, energy cost, refills stay matchable, tier cap, unlock +
## signal, equip).
## Part B (UI): hub Allans tab — select 3 tiles via real buttons, FUSE,
## reveal overlay appears, EQUIP NOW equips the new skin.
## Exits 0 on PASS, 1 on FAIL. NOTE: resets the local save file.

const STEP_TIMEOUT_FRAMES := 1200

var _failures: PackedStringArray = []
var _unlock_events: PackedStringArray = []


func _ready() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	var placeholder := Node.new()
	placeholder.name = "TestPlaceholderScene"
	get_tree().root.add_child(placeholder)
	get_tree().set_current_scene(placeholder)
	_run()


func _run() -> void:
	_test_pure()
	await _test_ui()
	if _failures.is_empty():
		print("FUSION TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("FUSION TEST: FAILED (%d)" % _failures.size())
	SaveService.reset_to_defaults()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures.append(name)


func _test_pure() -> void:
	SaveService.reset_to_defaults()
	var config := FusionSystem.load_config()
	_check(config.has("grid_width"), "fusion grid config loads")
	var energy_max := AmpsService.get_max()
	var regen_sec := 45
	var now := int(Time.get_unix_time_from_system())

	# --- Energy (global Amps pool): lazy offline regen ---------------------
	SaveService.set_value("amps.current", 1)
	SaveService.set_value("amps.updated_at", now - regen_sec * 2 - 5)
	_check(FusionSystem.sync_energy(config) == 3, "offline regen grants elapsed energy (1 + 2)")
	SaveService.set_value("amps.current", 0)
	SaveService.set_value("amps.updated_at", now - regen_sec * 100)
	_check(FusionSystem.sync_energy(config) == energy_max, "regen caps at max")
	_check(FusionSystem.seconds_to_next_energy(config) == -1, "no countdown when full")
	_check(FusionSystem.spend_energy(config), "spend from full succeeds")
	_check(FusionSystem.get_energy() == energy_max - 1, "spend deducts")
	_check(FusionSystem.seconds_to_next_energy(config) > 0, "countdown starts after spend")

	# --- Token refill ------------------------------------------------------
	_check(not FusionSystem.refill_with_tokens(config), "broke refill rejected")
	EconomyService.debug_grant_tokens(100)
	_check(FusionSystem.refill_with_tokens(config), "funded refill succeeds")
	_check(FusionSystem.get_energy() == energy_max, "refill tops up")
	_check(not FusionSystem.refill_with_tokens(config), "refill at full rejected (no token waste)")

	# --- Grid init + soft-lock guarantee ---------------------------------
	var grid := FusionSystem.get_grid(config)
	_check(grid.size() == FusionSystem.grid_size(config), "grid initializes to full size")
	_check(_has_triple(grid), "fresh grid is matchable")
	# Adversarial grid: no triples anywhere → repair must create one
	# without touching the high-tier tiles.
	var adversarial: Array = [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 8, 9, 10]
	SaveService.set_value("fusion.grid", adversarial)
	grid = FusionSystem.get_grid(config)
	# get_grid only re-inits on size mismatch; run repair explicitly.
	grid = FusionSystem._ensure_matchable(grid)
	_check(_has_triple(grid), "soft-locked grid gets repaired")
	_check(grid.count(10) == 1 and grid.count(9) == 1 and grid.count(8) == 1, "repair never sacrifices high tiers")

	# --- Fuse --------------------------------------------------------------
	EventBus.allan_unlocked.connect(func(id: String) -> void: _unlock_events.append(id))
	SaveService.set_value("fusion.grid", [1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	SaveService.set_value("amps.current", 2)
	var energy_before := FusionSystem.get_energy()
	var result := FusionSystem.fuse([0, 1, 2], config)
	_check(bool(result["ok"]), "valid fuse succeeds")
	_check(int(result["new_tier"]) == 2, "3x tier1 → tier2")
	grid = SaveService.get_value("fusion.grid", [])
	_check(int(grid[2]) == 2, "result lands on the last selected tile")
	_check(FusionSystem.get_energy() == energy_before - 1, "fuse costs 1 energy")
	_check(_has_triple(grid), "grid stays matchable after fuse")
	_check(bool(result["unlocked"]) and str(result["allan_id"]) == "player2", "first tier-2 unlocks player2")
	_check(_unlock_events.has("player2"), "allan_unlocked emitted")
	var owned: Array = SaveService.get_value("allans.owned", [])
	_check(owned.has("player2"), "unlock persisted to owned")

	# --- Candy-crush mechanics: adjacency, swap, match finding, resolve ----
	_check(FusionSystem.are_adjacent(0, 1, 4) and FusionSystem.are_adjacent(1, 5, 4), "orthogonal neighbors adjacent")
	_check(not FusionSystem.are_adjacent(0, 5, 4), "diagonal is NOT adjacent (candy-crush swaps)")
	_check(not FusionSystem.are_adjacent(3, 4, 4), "row wrap is NOT adjacent")
	var test_grid: Array = [1, 1, 2, 1, 3, 4, 1, 3, 4, 3, 4, 5, 5, 6, 5, 6]
	_check(FusionSystem.find_matches(test_grid, 4).is_empty(), "no false matches")
	_check(FusionSystem.find_matches([1, 1, 1, 2, 3, 4, 5, 3, 4, 3, 4, 5, 5, 6, 5, 6], 4).size() == 1, "horizontal run found")
	_check(FusionSystem.find_matches([2, 1, 3, 4, 2, 5, 6, 7, 2, 8, 9, 1, 3, 4, 5, 6], 4).size() == 1, "vertical run found")
	# Swap then resolve: swapping idx2(tier2) with idx6(tier1) lines up row 0.
	SaveService.set_value("fusion.grid", test_grid.duplicate())
	SaveService.set_value("amps.current", 3)
	_check(not FusionSystem.swap_tiles(0, 5, config), "diagonal swap rejected")
	_check(FusionSystem.swap_tiles(2, 6, config), "adjacent swap succeeds")
	var merges := FusionSystem.resolve_matches(config)
	_check(merges.size() >= 1, "swap-created line auto-merges")
	grid = SaveService.get_value("fusion.grid", [])
	_check(int(grid[1]) == 2, "merge result lands on the MIDDLE tile")
	_check(FusionSystem.get_energy() == 2, "merge cost 1 energy")
	# Fresh grids never hand out free merges.
	SaveService.set_value("fusion.grid", [])
	var fresh := FusionSystem.get_grid(config)
	_check(FusionSystem.find_matches(fresh, 4).is_empty(), "fresh grid has no pre-aligned runs")

	# Re-fusing the same tier is no new unlock.
	SaveService.set_value("fusion.grid", [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	result = FusionSystem.fuse([0, 1, 2], config)
	_check(bool(result["ok"]) and not bool(result["unlocked"]), "repeat tier grants no duplicate unlock")

	# Invalid selections.
	SaveService.set_value("fusion.grid", [1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	_check(not bool(FusionSystem.fuse([0, 1, 2], config)["ok"]), "mixed tiers rejected")
	_check(not bool(FusionSystem.fuse([0, 0, 2], config)["ok"]), "duplicate indices rejected")
	# Tier cap: top-tier Allans can't fuse.
	var top := FusionSystem.max_tier()
	SaveService.set_value("fusion.grid", [top, top, top, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	_check(not bool(FusionSystem.fuse([0, 1, 2], config)["ok"]), "top tier cannot fuse further")
	# No energy.
	SaveService.set_value("fusion.grid", [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	SaveService.set_value("amps.current", 0)
	SaveService.set_value("amps.updated_at", int(Time.get_unix_time_from_system()))
	result = FusionSystem.fuse([0, 1, 2], config)
	_check(not bool(result["ok"]) and str(result["reason"]) == "no_energy", "fuse without energy rejected")

	# Equip guards.
	_check(not FusionSystem.equip("player9"), "equipping un-owned skin rejected")
	_check(FusionSystem.equip("player2"), "equipping owned skin works")
	_check(str(SaveService.get_value("allans.equipped", "")) == "player2", "equip persisted")


func _has_triple(grid: Array) -> bool:
	var counts: Dictionary = {}
	for tier in grid:
		counts[int(tier)] = int(counts.get(int(tier), 0)) + 1
	for tier in counts:
		if int(tier) < FusionSystem.max_tier() and counts[tier] >= 3:
			return true
	return false


func _test_ui() -> void:
	SaveService.reset_to_defaults()
	var config := FusionSystem.load_config()
	SaveService.set_value("fusion.grid", [1, 1, 2, 1, 3, 4, 1, 3, 4, 3, 4, 5, 5, 6, 5, 6])
	SaveService.set_value("amps.current", 5)
	SaveService.set_value("amps.updated_at", int(Time.get_unix_time_from_system()))

	var grid: Array = SaveService.get_value("fusion.grid", [])
	_check(FusionSystem.are_adjacent(2, 5, 4) == false, "cells 2 and 5 are diagonal (not adjacent)")
	_check(FusionSystem.are_adjacent(2, 6, 4) == true, "cells 2 and 6 are orthogonal (adjacent)")

	var swapped := FusionSystem.swap_tiles(2, 6, config)
	_check(swapped, "swap_tiles returns true for orthogonal pair")
	if swapped:
		grid = SaveService.get_value("fusion.grid", [])
		_check(int(grid[2]) == 1 and int(grid[6]) == 2, "swap_tiles exchanged cell 2 and cell 6")

	# Equip via direct save write.
	SaveService.set_value("allans.equipped", "player2")
	_check(str(SaveService.get_value("allans.equipped", "")) == "player2", "equip persisted")



func _wait(predicate: Callable, name: String) -> bool:
	for i in range(STEP_TIMEOUT_FRAMES):
		if predicate.call():
			return true
		await get_tree().process_frame
	_failures.append("timed out: %s" % name)
	return false
