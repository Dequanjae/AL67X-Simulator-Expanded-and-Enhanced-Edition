class_name LevelGenerator
extends RefCounted
## Pure worldgen logic — NO nodes, NO rendering. Takes a level number + a
## theme dict (from data/levels/theme_*.json) and returns a layout dict.
## LevelBuilder turns layouts into 3D nodes; tests validate layouts directly.
##
## Dodge-ability guarantees (spec Section 5):
##  - every algorithm keeps `min_clearance` meters between prop footprints,
##  - a clear spawn circle at the arena center,
##  - a flood-fill connectivity pass rejects layouts with unreachable
##    pockets (re-rolls with a bumped seed, up to MAX_ATTEMPTS).
##
## Layouts are DETERMINISTIC per level (seeded by level number), so a retry
## of Day N is the same floor.

const CELL_SIZE := 1.0
## Prop footprints are inflated by this margin (player radius + slack) when
## computing blocked cells.
const PROP_INFLATE := 0.55
## Props never spawn closer than this to the arena boundary walls.
const WALL_MARGIN := 2.0
## Minimum fraction of open cells that must be reachable from the center.
const MIN_REACHABLE_RATIO := 0.93
const MAX_ATTEMPTS := 6
## Arena grows with level, capped (percentage-style growth, spec Section 2).
const ARENA_GROWTH_PER_LEVEL := 0.025
const ARENA_GROWTH_CAP := 0.6


static func generate(level: int, theme: Dictionary) -> Dictionary:
	var gen: Dictionary = theme.get("generation", {})
	var base_size: Array = gen.get("arena_size", [40, 40])
	var growth := 1.0 + minf(ARENA_GROWTH_CAP, ARENA_GROWTH_PER_LEVEL * float(level - 1))
	var arena := Vector2(float(base_size[0]) * growth, float(base_size[1]) * growth)
	var clearance := maxf(2.5, float(gen.get("min_clearance", 3.0)))
	var spawn_clear := float(gen.get("spawn_clear_radius", 4.5))
	var algorithm := String(gen.get("algorithm", "scatter"))

	for attempt in range(MAX_ATTEMPTS):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(level) * 1000003 + attempt * 7919
		var props: Array = []
		match algorithm:
			"aisles":
				props = _gen_aisles(rng, arena, theme, clearance, spawn_clear)
			"rings":
				props = _gen_rings(rng, arena, theme, clearance, spawn_clear)
			"clusters":
				props = _gen_clusters(rng, arena, theme, clearance, spawn_clear)
			"rooms":
				props = _gen_rooms(rng, arena, theme, clearance, spawn_clear)
			_:
				props = _gen_scatter(rng, arena, theme, clearance, spawn_clear)
		var validation := _validate(arena, props)
		if validation["ok"]:
			return {
				"ok": true,
				"level": level,
				"theme_id": str(theme.get("id", "?")),
				"arena_size": arena,
				"props": props,
				"walkable_points": validation["walkable"],
				"reachable_ratio": validation["reachable_ratio"],
				"player_spawn": Vector3.ZERO,
				"attempts": attempt + 1,
			}
	push_error("LevelGenerator: level %d (%s) failed validation after %d attempts — open arena fallback" % [level, theme.get("id", "?"), MAX_ATTEMPTS])
	var open_validation := _validate(arena, [])
	return {
		"ok": false,
		"level": level,
		"theme_id": str(theme.get("id", "?")),
		"arena_size": arena,
		"props": [],
		"walkable_points": open_validation["walkable"],
		"reachable_ratio": open_validation["reachable_ratio"],
		"player_spawn": Vector3.ZERO,
		"attempts": MAX_ATTEMPTS,
	}


## Loads all theme files, ordered by their explicit "order" field (level 1
## uses the lowest order — keep that theme the easiest, it's the tutorial
## hook), ties broken by id.
static func load_themes() -> Array:
	var themes: Array = []
	for path in JsonData.list_files("res://data/levels", "json"):
		var theme: Variant = JsonData.load_json(path)
		if theme is Dictionary and theme.has("generation"):
			themes.append(theme)
	themes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(a.get("order", 9999))
		var ob := int(b.get("order", 9999))
		if oa != ob:
			return oa < ob
		return str(a.get("id", "")) < str(b.get("id", "")))
	return themes


static func theme_for_level(level: int, themes: Array) -> Dictionary:
	if themes.is_empty():
		return {}
	return themes[(level - 1) % themes.size()]


# ---------------------------------------------------------------------------
# Prop helpers
# ---------------------------------------------------------------------------

static func _pick_prop(rng: RandomNumberGenerator, theme: Dictionary, role := "") -> Dictionary:
	var pool: Array = theme.get("props", [])
	if role != "":
		var filtered := pool.filter(func(p: Dictionary) -> bool: return str(p.get("role", "")) == role)
		if not filtered.is_empty():
			pool = filtered
	if pool.is_empty():
		return {"shape": "box", "size": [1, 1, 1], "color": "#888888"}
	var total := 0.0
	for p in pool:
		total += float(p.get("weight", 1))
	var roll := rng.randf() * total
	for p in pool:
		roll -= float(p.get("weight", 1))
		if roll <= 0.0:
			return p
	return pool.back()


static func _make_prop(def: Dictionary, x: float, z: float, rot_deg := 0.0) -> Dictionary:
	var prop := {
		"shape": str(def.get("shape", "box")),
		"size": def.get("size", [1, 1, 1]),
		"color": str(def.get("color", "#888888")),
		"pos": [x, z],
		"rot": rot_deg,
	}
	# Mesh props carry their model path through to the builder.
	if def.has("mesh"):
		prop["mesh"] = str(def["mesh"])
	return prop


## Half extents of the prop footprint on the ground plane, accounting for
## yaw. Arbitrary rotations use a conservative square bound.
static func _half_extents(prop: Dictionary) -> Vector2:
	var sx := float(prop["size"][0]) * 0.5
	var sz := float(prop["size"][2]) * 0.5
	var r := fposmod(float(prop.get("rot", 0.0)), 180.0)
	if absf(r - 90.0) < 1.0:
		return Vector2(sz, sx)
	if r < 1.0 or r > 179.0:
		return Vector2(sx, sz)
	var m := maxf(sx, sz)
	return Vector2(m, m)


static func _footprint_radius(prop: Dictionary) -> float:
	var he := _half_extents(prop)
	return maxf(he.x, he.y)


static func _fits(props: Array, candidate: Dictionary, clearance: float) -> bool:
	var cx := float(candidate["pos"][0])
	var cz := float(candidate["pos"][1])
	var cr := _footprint_radius(candidate)
	for other in props:
		var dist := Vector2(cx - float(other["pos"][0]), cz - float(other["pos"][1])).length()
		if dist < clearance + cr + _footprint_radius(other):
			return false
	return true


static func _in_spawn_clear(x: float, z: float, prop_radius: float, spawn_clear: float) -> bool:
	return Vector2(x, z).length() < spawn_clear + prop_radius


# ---------------------------------------------------------------------------
# Algorithms — each returns Array of prop dicts
# ---------------------------------------------------------------------------

static func _gen_scatter(rng: RandomNumberGenerator, arena: Vector2, theme: Dictionary, clearance: float, spawn_clear: float) -> Array:
	var props: Array = []
	var density := float(theme.get("generation", {}).get("prop_density", 0.03))
	var target := int(arena.x * arena.y * density)
	var half := arena * 0.5
	var tries := target * 30
	while props.size() < target and tries > 0:
		tries -= 1
		var def := _pick_prop(rng, theme)
		var r := _footprint_radius(_make_prop(def, 0, 0))
		var x := rng.randf_range(-half.x + WALL_MARGIN + r, half.x - WALL_MARGIN - r)
		var z := rng.randf_range(-half.y + WALL_MARGIN + r, half.y - WALL_MARGIN - r)
		if _in_spawn_clear(x, z, r, spawn_clear):
			continue
		var candidate := _make_prop(def, x, z, 90.0 * float(rng.randi_range(0, 1)))
		if _fits(props, candidate, clearance):
			props.append(candidate)
	return props


static func _gen_aisles(rng: RandomNumberGenerator, arena: Vector2, theme: Dictionary, clearance: float, spawn_clear: float) -> Array:
	var props: Array = []
	var half := arena * 0.5
	var horizontal := rng.randi_range(0, 1) == 0  # rows run along X (true) or Z
	var shelf_def := _pick_prop(rng, theme, "shelf")
	var shelf_size: Array = shelf_def.get("size", [0.9, 1.5, 3.0])
	var shelf_w := float(shelf_size[0])
	var shelf_len := float(shelf_size[2])
	# Corridor between rows must comfortably exceed clearance.
	var row_gap := maxf(clearance + shelf_w + 0.6, 4.5)
	var perp_half := half.y if horizontal else half.x
	var along_half := half.x if horizontal else half.y
	var row_pos := -perp_half + WALL_MARGIN + 1.0
	while row_pos < perp_half - WALL_MARGIN - 1.0:
		# Skip rows crossing the spawn clearing entirely; door gaps handle
		# the rest of traversal.
		var t := -along_half + WALL_MARGIN
		var segments_since_door := 0
		var door_every := rng.randi_range(2, 4)
		while t + shelf_len < along_half - WALL_MARGIN:
			if segments_since_door >= door_every:
				t += rng.randf_range(2.8, 3.8)  # door gap, always > player + slack
				segments_since_door = 0
				door_every = rng.randi_range(2, 4)
				continue
			var center_t := t + shelf_len * 0.5
			var x := center_t if horizontal else row_pos
			var z := row_pos if horizontal else center_t
			var rot := 90.0 if horizontal else 0.0
			var prop := _make_prop(shelf_def, x, z, rot)
			if not _in_spawn_clear(x, z, _footprint_radius(prop), spawn_clear):
				props.append(prop)
			t += shelf_len + 0.2
			segments_since_door += 1
		row_pos += row_gap
	# Sprinkle a few loose props in corridor space.
	var extras := _gen_scatter_into(rng, arena, theme, clearance, spawn_clear, props, int(arena.x * arena.y * 0.004))
	props.append_array(extras)
	return props


static func _gen_rings(rng: RandomNumberGenerator, arena: Vector2, theme: Dictionary, clearance: float, spawn_clear: float) -> Array:
	var props: Array = []
	var half := arena * 0.5
	var max_r := minf(half.x, half.y) - WALL_MARGIN - 1.0
	var radius := spawn_clear + 2.5
	while radius < max_r:
		# 2-4 door gaps per ring at random angles, each ~3.2m of arc.
		var doors: Array[float] = []
		for i in range(rng.randi_range(2, 4)):
			doors.append(rng.randf_range(0.0, TAU))
		var door_half_arc := 1.7 / radius  # half-width in radians (~3.4m door)
		var angle := rng.randf_range(0.0, TAU)
		var walked := 0.0
		while walked < TAU * radius:
			var def := _pick_prop(rng, theme)
			var prop_dim := _footprint_radius(_make_prop(def, 0, 0)) * 2.0
			var step := prop_dim + 0.5
			var in_door := false
			for door_angle in doors:
				if absf(angle_difference(angle, door_angle)) < door_half_arc + (prop_dim * 0.5) / radius:
					in_door = true
					break
			if not in_door:
				var x := cos(angle) * radius
				var z := sin(angle) * radius
				props.append(_make_prop(def, x, z, rad_to_deg(angle) + 90.0))
			var dtheta := step / radius
			angle = fposmod(angle + dtheta, TAU)
			walked += step
		radius += maxf(clearance + 2.0, 5.0)
	return props


static func _gen_clusters(rng: RandomNumberGenerator, arena: Vector2, theme: Dictionary, clearance: float, spawn_clear: float) -> Array:
	var props: Array = []
	var half := arena * 0.5
	var density := float(theme.get("generation", {}).get("prop_density", 0.03))
	var cluster_count := clampi(int(arena.x * arena.y * density * 0.25), 4, 14)
	var centers: Array[Vector2] = []
	var tries := cluster_count * 40
	var center_spacing := clearance * 2.0 + 4.0
	while centers.size() < cluster_count and tries > 0:
		tries -= 1
		var c := Vector2(
			rng.randf_range(-half.x + WALL_MARGIN + 3.0, half.x - WALL_MARGIN - 3.0),
			rng.randf_range(-half.y + WALL_MARGIN + 3.0, half.y - WALL_MARGIN - 3.0)
		)
		if c.length() < spawn_clear + 4.0:
			continue
		var ok := true
		for existing in centers:
			if c.distance_to(existing) < center_spacing:
				ok = false
				break
		if ok:
			centers.append(c)
	for center in centers:
		var cluster_size := rng.randi_range(3, 6)
		var cluster_props: Array = []
		var placement_tries := cluster_size * 20
		while cluster_props.size() < cluster_size and placement_tries > 0:
			placement_tries -= 1
			var offset := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, 2.2)
			var pos := center + offset
			var def := _pick_prop(rng, theme)
			var candidate := _make_prop(def, pos.x, pos.y, 90.0 * float(rng.randi_range(0, 1)))
			# Tight intra-cluster packing (0.4m), normal clearance to others.
			if _fits(cluster_props, candidate, 0.4) and _fits(props, candidate, clearance):
				cluster_props.append(candidate)
		props.append_array(cluster_props)
	return props


## Rooms: interior wall lines split the arena into back rooms, each wall
## broken by generous door gaps (always wider than the dodge clearance).
## Props with role="wall" form the walls; a light scatter furnishes rooms.
static func _gen_rooms(rng: RandomNumberGenerator, arena: Vector2, theme: Dictionary, clearance: float, spawn_clear: float) -> Array:
	var props: Array = []
	var half := arena * 0.5
	var wall_def := _pick_prop(rng, theme, "wall")
	var wall_size: Array = wall_def.get("size", [0.5, 2.0, 2.6])
	var seg_len := float(wall_size[2])
	var door_w := maxf(clearance + 0.8, 3.6)
	var cols := 3 if arena.x > 44.0 else 2
	# Vertical interior lines (walls run along Z).
	for ci in range(1, cols):
		var x := -half.x + arena.x * float(ci) / float(cols)
		props.append_array(_wall_line(rng, wall_def, x, -half.y + WALL_MARGIN, half.y - WALL_MARGIN, true, seg_len, door_w, spawn_clear))
	# One horizontal line (walls run along X) — it crosses the spawn
	# clearing, which naturally opens the center up.
	props.append_array(_wall_line(rng, wall_def, 0.0, -half.x + WALL_MARGIN, half.x - WALL_MARGIN, false, seg_len, door_w, spawn_clear))
	# Furnish the rooms.
	var extras := _gen_scatter_into(rng, arena, theme, clearance, spawn_clear, props, int(arena.x * arena.y * 0.008))
	props.append_array(extras)
	return props


static func _wall_line(rng: RandomNumberGenerator, def: Dictionary, line_pos: float, from: float, to: float, vertical: bool, seg_len: float, door_w: float, spawn_clear: float) -> Array:
	var segments: Array = []
	var length := to - from
	var doors: Array[float] = []
	var door_count := 3
	for i in range(door_count):
		doors.append(from + length * (float(i) + 0.5 + rng.randf_range(-0.18, 0.18)) / float(door_count))
	var t := from
	while t + seg_len <= to:
		var center := t + seg_len * 0.5
		var in_door := false
		for door in doors:
			if absf(center - door) < (door_w + seg_len) * 0.5:
				in_door = true
				break
		if not in_door:
			var x := line_pos if vertical else center
			var z := center if vertical else line_pos
			var prop := _make_prop(def, x, z, 0.0 if vertical else 90.0)
			if not _in_spawn_clear(x, z, _footprint_radius(prop), spawn_clear):
				segments.append(prop)
		t += seg_len + 0.05
	return segments


## Scatter helper that respects an existing prop set (used for aisle extras).
static func _gen_scatter_into(rng: RandomNumberGenerator, arena: Vector2, theme: Dictionary, clearance: float, spawn_clear: float, existing: Array, target: int) -> Array:
	var extras: Array = []
	var half := arena * 0.5
	var tries := target * 30
	while extras.size() < target and tries > 0:
		tries -= 1
		var def := _pick_prop(rng, theme)
		var r := _footprint_radius(_make_prop(def, 0, 0))
		var x := rng.randf_range(-half.x + WALL_MARGIN + r, half.x - WALL_MARGIN - r)
		var z := rng.randf_range(-half.y + WALL_MARGIN + r, half.y - WALL_MARGIN - r)
		if _in_spawn_clear(x, z, r, spawn_clear):
			continue
		var candidate := _make_prop(def, x, z)
		if _fits(existing, candidate, clearance) and _fits(extras, candidate, clearance):
			extras.append(candidate)
	return extras


# ---------------------------------------------------------------------------
# Validation — coarse-grid flood fill from the spawn point
# ---------------------------------------------------------------------------

static func _validate(arena: Vector2, props: Array) -> Dictionary:
	var nx := maxi(1, int(arena.x / CELL_SIZE))
	var nz := maxi(1, int(arena.y / CELL_SIZE))
	var half := arena * 0.5
	var blocked := PackedByteArray()
	blocked.resize(nx * nz)

	for prop in props:
		var he := _half_extents(prop) + Vector2(PROP_INFLATE, PROP_INFLATE)
		var px := float(prop["pos"][0])
		var pz := float(prop["pos"][1])
		var i_min := maxi(0, int((px - he.x + half.x) / CELL_SIZE))
		var i_max := mini(nx - 1, int((px + he.x + half.x) / CELL_SIZE))
		var j_min := maxi(0, int((pz - he.y + half.y) / CELL_SIZE))
		var j_max := mini(nz - 1, int((pz + he.y + half.y) / CELL_SIZE))
		for i in range(i_min, i_max + 1):
			for j in range(j_min, j_max + 1):
				var cx := -half.x + (float(i) + 0.5) * CELL_SIZE
				var cz := -half.y + (float(j) + 0.5) * CELL_SIZE
				if absf(cx - px) <= he.x and absf(cz - pz) <= he.y:
					blocked[j * nx + i] = 1

	var open_count := 0
	for v in blocked:
		if v == 0:
			open_count += 1

	# BFS from the center cell.
	var start_i := nx / 2
	var start_j := nz / 2
	var reachable := PackedByteArray()
	reachable.resize(nx * nz)
	var queue: Array[int] = []
	if blocked[start_j * nx + start_i] == 0:
		queue.append(start_j * nx + start_i)
		reachable[start_j * nx + start_i] = 1
	var reachable_count := 0
	var walkable := PackedVector3Array()
	while not queue.is_empty():
		var idx: int = queue.pop_back()
		reachable_count += 1
		var i := idx % nx
		var j := idx / nx
		walkable.append(Vector3(-half.x + (float(i) + 0.5) * CELL_SIZE, 0.0, -half.y + (float(j) + 0.5) * CELL_SIZE))
		for offset in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var ni: int = i + offset[0]
			var nj: int = j + offset[1]
			if ni < 0 or ni >= nx or nj < 0 or nj >= nz:
				continue
			var nidx := nj * nx + ni
			if blocked[nidx] == 0 and reachable[nidx] == 0:
				reachable[nidx] = 1
				queue.append(nidx)

	var ratio := float(reachable_count) / float(maxi(1, open_count))
	return {
		"ok": ratio >= MIN_REACHABLE_RATIO and walkable.size() >= 50,
		"reachable_ratio": ratio,
		"walkable": walkable,
	}
