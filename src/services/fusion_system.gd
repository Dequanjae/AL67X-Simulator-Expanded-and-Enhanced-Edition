class_name FusionSystem
extends RefCounted
## Allan fusion logic (spec Section 6) — pure functions over SaveService
## state, configured by data/balance/fusion.json (grid only — see
## data/balance/amps.json for the energy pool).
##  - Energy: delegates entirely to the global AmpsService (spec: Overvolt
##    Garage UI overhaul consolidated merge-only "fusion energy" into ONE
##    real-time Amps pool shared by merge/gameplay/shop). FusionSystem keeps
##    these wrapper methods so existing call sites (UIBridge, smoke tests)
##    don't need to know the pool is now global.
##  - CANDY-CRUSH-STYLE grid: drag a tile onto an orthogonal neighbor to
##    SWAP; any 3 same-tier Allans aligned in a row/column auto-merge into
##    1 Allan of tier+1 (result lands on the middle tile, 1 Amp per
##    merge; cascades allowed while Amps last). Freed tiles respawn from
##    weighted odds. The grid is guaranteed matchable-by-rearrangement (a
##    triple of some tier always exists).
##  - First time a tier is reached → that Allan skin unlocks permanently
##    (allans.owned) and EventBus.allan_unlocked fires → reveal screen.


static func load_config() -> Dictionary:
	var parsed: Variant = JsonData.load_json("res://data/balance/fusion.json")
	return parsed if parsed is Dictionary else {}


# ---------------------------------------------------------------------------
# Energy — thin pass-through to the global Amps pool (see AmpsService).
# `config` parameters are accepted (unused) so existing call sites keep
# working unchanged.
# ---------------------------------------------------------------------------

static func sync_energy(_config: Dictionary) -> int:
	return AmpsService.sync()


static func get_energy() -> int:
	return AmpsService.get_current()


## Seconds until the next point regenerates; -1 when full.
static func seconds_to_next_energy(_config: Dictionary) -> int:
	return AmpsService.seconds_to_next()


static func spend_energy(_config: Dictionary, amount := 1) -> bool:
	return AmpsService.spend(amount, "fusion")


## Token top-up: instantly refills Amps to max (monetization hook).
static func refill_with_tokens(_config: Dictionary) -> bool:
	return AmpsService.refill_with_tokens()


# ---------------------------------------------------------------------------
# Grid
# ---------------------------------------------------------------------------

static func grid_size(config: Dictionary) -> int:
	return int(config.get("grid_width", 4)) * int(config.get("grid_height", 4))


## Returns the persisted grid, initializing / repairing it as needed.
static func get_grid(config: Dictionary) -> Array:
	var grid: Array = SaveService.get_value("fusion.grid", [])
	var size := grid_size(config)
	if grid.size() != size:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		grid = []
		for i in range(size):
			grid.append(_spawn_tier(rng, config))
		grid = _ensure_matchable(grid)
		# Fresh grids must not hand out free merges: de-align any runs.
		grid = _break_initial_lines(grid, int(config.get("grid_width", 4)), rng)
		SaveService.set_value("fusion.grid", grid)
	return grid


## Candy-crush swap: exchange two ORTHOGONALLY adjacent tiles. Free (no
## energy) — merges are what cost energy.
static func swap_tiles(a: int, b: int, config: Dictionary) -> bool:
	var grid := get_grid(config)
	if a < 0 or b < 0 or a >= grid.size() or b >= grid.size() or a == b:
		return false
	if not are_adjacent(a, b, int(config.get("grid_width", 4))):
		return false
	var tmp: int = int(grid[a])
	grid[a] = grid[b]
	grid[b] = tmp
	SaveService.set_value("fusion.grid", grid)
	return true


## Orthogonal adjacency (candy-crush swaps — no diagonals).
static func are_adjacent(a: int, b: int, width: int) -> bool:
	@warning_ignore("integer_division")
	var ax := a % width
	@warning_ignore("integer_division")
	var ay := a / width
	@warning_ignore("integer_division")
	var bx := b % width
	@warning_ignore("integer_division")
	var by := b / width
	return (absi(ax - bx) + absi(ay - by)) == 1


## Finds aligned 3-runs (rows + columns) of the same fusable tier.
## Returns Array of [i0, i1_middle_last?, ...] — each run is [a, b, c] in
## line order.
static func find_matches(grid: Array, width: int) -> Array:
	@warning_ignore("integer_division")
	var height := grid.size() / width
	var top := max_tier()
	var runs: Array = []
	for y in range(height):
		var x := 0
		while x < width - 2:
			var i := y * width + x
			var tier := int(grid[i])
			if tier < top and int(grid[i + 1]) == tier and int(grid[i + 2]) == tier:
				runs.append([i, i + 1, i + 2])
				x += 3
			else:
				x += 1
	for x in range(width):
		var y := 0
		while y < height - 2:
			var i := y * width + x
			var tier := int(grid[i])
			if tier < top and int(grid[i + width]) == tier and int(grid[i + 2 * width]) == tier:
				runs.append([i, i + width, i + 2 * width])
				y += 3
			else:
				y += 1
	return runs


## Merges every aligned run (1 energy each, result on the MIDDLE tile),
## cascading while energy lasts. Returns the list of fuse results.
static func resolve_matches(config: Dictionary) -> Array:
	var results: Array = []
	var width := int(config.get("grid_width", 4))
	for guard in range(32):
		var grid := get_grid(config)
		var runs := find_matches(grid, width)
		if runs.is_empty():
			break
		if sync_energy(config) < 1:
			break
		var run: Array = runs[0]
		# fuse() places the result on the LAST index — pass middle last.
		var result := fuse([run[0], run[2], run[1]], config)
		if not bool(result.get("ok", false)):
			break
		results.append(result)
	return results


static func _break_initial_lines(grid: Array, width: int, rng: RandomNumberGenerator) -> Array:
	for guard in range(24):
		var runs := find_matches(grid, width)
		if runs.is_empty():
			break
		var run: Array = runs[0]
		grid[run[1]] = 1 if int(grid[run[1]]) != 1 else 2
		grid = _ensure_matchable(grid)
	return grid


static func max_tier() -> int:
	var highest := 1
	for allan in AllanSprites.registry().get("allans", []):
		highest = maxi(highest, int(allan.get("tier", 1)))
	return highest


static func allan_for_tier(tier: int) -> Dictionary:
	for allan in AllanSprites.registry().get("allans", []):
		if int(allan.get("tier", 0)) == tier:
			return allan
	return {}


## Valid selection: 3 distinct in-range indices, identical tier, below the
## top tier (top-tier Allans cannot fuse further).
static func can_fuse(indices: Array, grid: Array) -> bool:
	if indices.size() != 3:
		return false
	var seen: Dictionary = {}
	for index in indices:
		var i := int(index)
		if i < 0 or i >= grid.size() or seen.has(i):
			return false
		seen[i] = true
	var tier := int(grid[int(indices[0])])
	for index in indices:
		if int(grid[int(index)]) != tier:
			return false
	return tier < max_tier()


## Performs the fusion. Returns:
## {ok, reason?, new_tier?, result_index?, unlocked?, allan_id?}
static func fuse(indices: Array, config: Dictionary) -> Dictionary:
	var grid := get_grid(config)
	if not can_fuse(indices, grid):
		return {"ok": false, "reason": "invalid_selection"}
	if not spend_energy(config):
		return {"ok": false, "reason": "no_energy"}

	var tier := int(grid[int(indices[0])])
	var new_tier := tier + 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var result_index := int(indices[2])
	grid[result_index] = new_tier
	grid[int(indices[0])] = _spawn_tier(rng, config)
	grid[int(indices[1])] = _spawn_tier(rng, config)
	grid = _ensure_matchable(grid)
	SaveService.set_value("fusion.grid", grid)

	# Permanent skin unlock on first reach.
	var allan := allan_for_tier(new_tier)
	var allan_id := str(allan.get("id", ""))
	var unlocked := false
	if allan_id != "":
		var owned: Array = SaveService.get_value("allans.owned", [])
		if not owned.has(allan_id):
			owned.append(allan_id)
			SaveService.set_value("allans.owned", owned)
			unlocked = true
			EventBus.allan_unlocked.emit(allan_id)
	return {
		"ok": true, "new_tier": new_tier, "result_index": result_index,
		"unlocked": unlocked, "allan_id": allan_id,
	}


static func equip(allan_id: String) -> bool:
	var owned: Array = SaveService.get_value("allans.owned", [])
	if not owned.has(allan_id):
		return false
	SaveService.set_value("allans.equipped", allan_id)
	EventBus.allan_equipped.emit(allan_id)
	return true


# ---------------------------------------------------------------------------

static func _spawn_tier(rng: RandomNumberGenerator, config: Dictionary) -> int:
	var weights: Dictionary = config.get("spawn_tier_weights", {"1": 100})
	var total := 0.0
	for tier in weights:
		total += float(weights[tier])
	var roll := rng.randf() * total
	for tier in weights:
		roll -= float(weights[tier])
		if roll <= 0.0:
			return int(str(tier))
	return 1


## Guarantees at least one 3-of-a-kind exists. Repairs by converting the
## LOWEST-tier tiles to tier 1 (never sacrifices high-tier progress).
static func _ensure_matchable(grid: Array) -> Array:
	var counts: Dictionary = {}
	for tier in grid:
		counts[int(tier)] = int(counts.get(int(tier), 0)) + 1
	var top := max_tier()
	for tier in counts:
		if int(tier) < top and counts[tier] >= 3:
			return grid
	# No fusable triple: force tier-1 tiles into existence, lowest first.
	var order := range(grid.size())
	order.sort_custom(func(a: int, b: int) -> bool: return int(grid[a]) < int(grid[b]))
	var ones := 0
	for i in order:
		if int(grid[i]) == 1:
			ones += 1
	for i in order:
		if ones >= 3:
			break
		if int(grid[i]) != 1:
			grid[i] = 1
			ones += 1
	return grid
