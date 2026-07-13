class_name HordeSystem
extends Node3D
## Batched enemy + projectile simulation (spec Section 5 optimization
## strategy, applied in order):
##  1. STEERING FORCES, no pathfinding: attract-to-player + neighbor
##     separation + prop/wall pushout, summed per frame.
##  2. BATCHED UPDATE: one _physics_process here iterates flat Packed*Arrays
##     for every enemy/projectile — no per-actor nodes or callbacks.
##  3. MULTIMESH RENDERING: one MultiMeshInstance3D per enemy type (billboard
##     shader, per-instance flip/flash/color), one for player projectiles,
##     one for enemy/boss projectiles.
##  4. Rust/GDExtension: escape hatch ONLY if on-device profiling later shows
##     this loop is the bottleneck (see docs/ARCHITECTURE.md).
##
## Enemy definitions are folder-scanned from data/enemies/*.json (behavior
## variety: chase / charge / phases). Bosses come from data/bosses/*.json
## composed per level by BossCatalog and executed as AttackPatterns modules.
##
## Contract signals emitted: player_hit, enemy_hit, enemy_killed,
## boss_spawned. Node signal `boss_killed` → RunController handles unlock.

signal boss_killed(boss_id: String)

const MAX_PER_TYPE := 384
const MAX_PROJECTILES := 192
const MAX_ENEMY_PROJECTILES := 256
const HASH_CELL := 2.0
const CONTACT_IFRAME_SEC := 0.8
const SEPARATION_RADIUS := 0.9
const SPAWN_RING_MIN := 15.0
const SPAWN_RING_MAX := 19.0
const PROJECTILE_TTL := 2.0
const ENEMY_PROJECTILE_TTL := 5.0
const ENEMY_PROJECTILE_RADIUS := 0.3
const BILLBOARD_SHADER := "res://src/shaders/billboard_sprite.gdshader"

# Behavior modes (per-enemy state machine for data-driven behaviors).
const MODE_NORMAL := 0
const MODE_WINDUP := 1
const MODE_DASH := 2

var spawning_enabled := true

var _player: Node3D
var _swarm: BlobSwarm
var _stats: PlayerStats
var _level := 1
var _config: Dictionary = {}
var _arena_half := Vector2(20, 20)
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _spawn_timer := 1.5
var _fire_timer := 0.4
var _player_iframe := 0.0

# Per-type parallel arrays: one entry per enemy type from data/enemies/.
var _types: Array[Dictionary] = []
var _eligible_indices: Array[int] = []
var _hash: Dictionary = {}  # Vector2i -> Array[int] (handle = type*MAX + slot)

# Boss state.
var _boss_type := -1
var _boss_slot := -1
var _boss_id := ""
var _boss_max_hp := 1.0
var _boss_patterns: Array = []
var _boss_dash_dir := Vector2.ZERO
var _boss_dash_speed := 0.0
var _boss_dash_time := 0.0
var _boss_telegraph := false

# Player projectiles (bounce + pierce tracked per projectile).
var _proj_pos: PackedVector2Array
var _proj_dir: PackedVector2Array
var _proj_ttl: PackedFloat32Array
var _proj_bounce: PackedInt32Array
var _proj_pierce: PackedInt32Array
var _proj_count := 0
var _proj_mm: MultiMesh

# Orbitals (Stator Satellites) + nova (Edging Nova) + freeze powerup.
var _orbital_angle := 0.0
var _orbital_hit_timer := 0.0
var _orbital_mm: MultiMesh
var _nova_timer := 0.0
var _freeze_timer := 0.0

# Enemy/boss projectiles (damage the player).
var _eproj_pos: PackedVector2Array
var _eproj_dir: PackedVector2Array
var _eproj_speed: PackedFloat32Array
var _eproj_damage: PackedFloat32Array
var _eproj_ttl: PackedFloat32Array
var _eproj_count := 0
var _eproj_mm: MultiMesh

# Prop obstacles (static, from worldgen layout).
var _obstacles: Array = []          # [{pos: Vector2, half: Vector2}]
var _obstacle_grid: Dictionary = {} # Vector2i -> Array[int]


func setup(player: Node3D, swarm: BlobSwarm, stats: PlayerStats, layout: Dictionary, level: int, config: Dictionary) -> void:
	_player = player
	_swarm = swarm
	_stats = stats
	_level = level
	_config = config
	_arena_half = (layout["arena_size"] as Vector2) * 0.5
	_rng.randomize()

	# Load ALL enemy types (bosses may use bases beyond the eligible set);
	# only eligible ones spawn as regular horde members.
	var defs := EnemyCatalog.load_all()
	if defs.is_empty():
		push_error("HordeSystem: no enemy definitions in data/enemies/")
	for def in defs:
		_types.append(_make_type(def))
	for i in range(_types.size()):
		if int(_types[i]["def"].get("min_level", 1)) <= level:
			_eligible_indices.append(i)

	_build_obstacles(layout)
	_make_projectile_pools()


func active_enemy_count() -> int:
	var count := 0
	for type in _types:
		count += type["active"]
	return count


func grant_player_iframes(seconds: float) -> void:
	_player_iframe = maxf(_player_iframe, seconds)


func has_boss() -> bool:
	return _boss_slot >= 0


func boss_hp_ratio() -> float:
	if _boss_slot < 0:
		return 0.0
	return clampf(float(_types[_boss_type]["hp"][_boss_slot]) / _boss_max_hp, 0.0, 1.0)


func boss_name() -> String:
	return _boss_id


## Spawns the composed boss for the current level (BossCatalog remix rule).
func spawn_boss() -> void:
	var composed := BossCatalog.compose_for_level(_level, BossCatalog.load_all())
	if composed.is_empty() or _types.is_empty():
		push_error("HordeSystem: no boss definitions — falling back to elite enemy")
		composed = {"id": "fallback_boss", "enemy_base": str(_types[0]["def"].get("id", "")), "hp_mult": 1.0, "patterns": []}
	var boss_cfg: Dictionary = _config.get("boss", {})
	var type_index := _type_index_for(str(composed.get("enemy_base", "")))
	if type_index < 0:
		type_index = 0
	var def: Dictionary = _types[type_index]["def"]
	var hp := float(def.get("hp", 20)) \
		* float(boss_cfg.get("hp_multiplier_base", 25)) \
		* (1.0 + float(boss_cfg.get("hp_growth_per_level", 0.3)) * float(_level - 1)) \
		* float(composed.get("hp_mult", 1.0))
	var slot := _spawn_enemy(type_index, _spawn_position(), hp, float(boss_cfg.get("scale", 2.4)))
	if slot < 0:
		return
	_boss_type = type_index
	_boss_slot = slot
	_boss_id = str(composed.get("id", "boss"))
	_boss_max_hp = hp
	_boss_patterns = composed.get("patterns", [])
	_boss_dash_time = 0.0
	_boss_telegraph = false
	EventBus.boss_spawned.emit(_boss_id)


func debug_set_boss_hp(hp: float) -> void:
	if _boss_slot >= 0:
		_types[_boss_type]["hp"][_boss_slot] = hp


## Freeze powerup: enemies stop moving + dealing contact damage.
func freeze_enemies(seconds: float) -> void:
	_freeze_timer = maxf(_freeze_timer, seconds)


## Goon nova powerup / Edging Nova card: radial burst of player projectiles.
func fire_nova(count := 24) -> void:
	var origin := player_position()
	for i in range(count):
		_spawn_projectile(origin, Vector2.from_angle(TAU * float(i) / float(count)))


# ---------------------------------------------------------------------------
# Boss API used by AttackPatterns modules
# ---------------------------------------------------------------------------

func boss_position() -> Vector2:
	if _boss_slot < 0:
		return Vector2.ZERO
	return _types[_boss_type]["pos"][_boss_slot]


func player_position() -> Vector2:
	if _player == null:
		return Vector2.ZERO
	return Vector2(_player.global_position.x, _player.global_position.z)


func spawn_enemy_projectile(from: Vector2, dir: Vector2, speed: float, damage: float) -> void:
	if _eproj_count >= MAX_ENEMY_PROJECTILES:
		return
	_eproj_pos[_eproj_count] = from
	_eproj_dir[_eproj_count] = dir
	_eproj_speed[_eproj_count] = speed
	_eproj_damage[_eproj_count] = damage
	_eproj_ttl[_eproj_count] = ENEMY_PROJECTILE_TTL
	_eproj_count += 1


func spawn_minion_near(origin: Vector2) -> void:
	if _eligible_indices.is_empty():
		return
	var type_index := _weighted_eligible_type()
	var def: Dictionary = _types[type_index]["def"]
	var offset := Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(1.5, 3.0)
	var position := origin + offset
	position.x = clampf(position.x, -_arena_half.x + 1.0, _arena_half.x - 1.0)
	position.y = clampf(position.y, -_arena_half.y + 1.0, _arena_half.y - 1.0)
	_spawn_enemy(type_index, position, float(def.get("hp", 20)), 1.0)


func boss_dash(dir: Vector2, speed: float, duration: float) -> void:
	_boss_dash_dir = dir
	_boss_dash_speed = speed
	_boss_dash_time = duration


func set_boss_telegraph(active: bool) -> void:
	_boss_telegraph = active


# ---------------------------------------------------------------------------

func _type_index_for(enemy_id: String) -> int:
	for i in range(_types.size()):
		if str(_types[i]["def"].get("id", "")) == enemy_id:
			return i
	return -1


func _make_type(def: Dictionary) -> Dictionary:
	var pos := PackedVector2Array()
	pos.resize(MAX_PER_TYPE)
	var vel := PackedVector2Array()
	vel.resize(MAX_PER_TYPE)
	var hp := PackedFloat32Array()
	hp.resize(MAX_PER_TYPE)
	var flash := PackedFloat32Array()
	flash.resize(MAX_PER_TYPE)
	var scale := PackedFloat32Array()
	scale.resize(MAX_PER_TYPE)
	var alive := PackedByteArray()
	alive.resize(MAX_PER_TYPE)
	# Behavior state machine (charge windup/dash etc.).
	var bmode := PackedByteArray()
	bmode.resize(MAX_PER_TYPE)
	var btimer := PackedFloat32Array()
	btimer.resize(MAX_PER_TYPE)
	var bdir := PackedVector2Array()
	bdir.resize(MAX_PER_TYPE)
	var free_slots: Array[int] = []
	for i in range(MAX_PER_TYPE - 1, -1, -1):
		free_slots.append(i)

	var height := float(def.get("size_m", 1.4))
	var width := height
	var sprite_path := str(def.get("sprite", ""))
	var texture: Texture2D = null
	if ResourceLoader.exists(sprite_path):
		texture = load(sprite_path)
		width = height * float(texture.get_width()) / float(texture.get_height())

	var mesh := QuadMesh.new()
	mesh.size = Vector2(width, height)
	var material := ShaderMaterial.new()
	material.shader = load(BILLBOARD_SHADER)
	if texture != null:
		material.set_shader_parameter("sprite_tex", texture)
	mesh.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_PER_TYPE
	var zero := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -100, 0))
	for i in range(MAX_PER_TYPE):
		multimesh.set_instance_transform(i, zero)
		multimesh.set_instance_color(i, Color.WHITE)
		multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))

	var instance := MultiMeshInstance3D.new()
	instance.name = "Horde_%s" % def.get("id", "enemy")
	instance.multimesh = multimesh
	instance.custom_aabb = AABB(Vector3(-200, -110, -200), Vector3(400, 220, 400))
	add_child(instance)

	return {
		"def": def,
		"pos": pos, "vel": vel, "hp": hp, "flash": flash, "scale": scale,
		"alive": alive, "bmode": bmode, "btimer": btimer, "bdir": bdir,
		"free": free_slots, "active": 0,
		"mm": multimesh, "half_height": height * 0.5,
	}


func _make_projectile_pools() -> void:
	# Player projectiles (white-cyan goop).
	_proj_pos = PackedVector2Array()
	_proj_pos.resize(MAX_PROJECTILES)
	_proj_dir = PackedVector2Array()
	_proj_dir.resize(MAX_PROJECTILES)
	_proj_ttl = PackedFloat32Array()
	_proj_ttl.resize(MAX_PROJECTILES)
	_proj_bounce = PackedInt32Array()
	_proj_bounce.resize(MAX_PROJECTILES)
	_proj_pierce = PackedInt32Array()
	_proj_pierce.resize(MAX_PROJECTILES)
	_proj_count = 0
	_proj_mm = _make_goop_pool("Projectiles", MAX_PROJECTILES, Vector2(0.55, 0.55), Color(0.95, 1.0, 0.98), Color(0.55, 0.95, 1.0))

	# Enemy/boss projectiles (white-red goop).
	_eproj_pos = PackedVector2Array()
	_eproj_pos.resize(MAX_ENEMY_PROJECTILES)
	_eproj_dir = PackedVector2Array()
	_eproj_dir.resize(MAX_ENEMY_PROJECTILES)
	_eproj_speed = PackedFloat32Array()
	_eproj_speed.resize(MAX_ENEMY_PROJECTILES)
	_eproj_damage = PackedFloat32Array()
	_eproj_damage.resize(MAX_ENEMY_PROJECTILES)
	_eproj_ttl = PackedFloat32Array()
	_eproj_ttl.resize(MAX_ENEMY_PROJECTILES)
	_eproj_count = 0
	_eproj_mm = _make_goop_pool("EnemyProjectiles", MAX_ENEMY_PROJECTILES, Vector2(0.62, 0.62), Color(1.0, 0.95, 0.95), Color(1.0, 0.3, 0.45))

	# Orbitals (bigger, slower goop).
	_orbital_mm = _make_goop_pool("Orbitals", 12, Vector2(0.9, 0.9), Color(0.95, 1.0, 0.98), Color(0.35, 0.8, 1.0))


## MultiMesh quad pool running the goop projectile shader (adapted from
## Erich_L's MIT "Goop Projectile" — see src/shaders/goop_projectile.gdshader).
func _make_goop_pool(pool_name: String, capacity: int, size: Vector2, color1: Color, color2: Color) -> MultiMesh:
	var mesh := QuadMesh.new()
	mesh.size = size
	var material := ShaderMaterial.new()
	material.shader = load("res://src/shaders/goop_projectile.gdshader")
	var noise := FastNoiseLite.new()
	noise.frequency = 0.06
	var flow := NoiseTexture2D.new()
	flow.noise = noise
	flow.width = 128
	flow.height = 128
	flow.seamless = true
	material.set_shader_parameter("flow_map", flow)
	material.set_shader_parameter("color1", color1)
	material.set_shader_parameter("color2", color2)
	mesh.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = capacity
	var zero := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -100, 0))
	for i in range(capacity):
		multimesh.set_instance_transform(i, zero)
		multimesh.set_instance_custom_data(i, Color(_rng.randf(), 0.6, 0.6, 0))
	var instance := MultiMeshInstance3D.new()
	instance.name = pool_name
	instance.multimesh = multimesh
	instance.custom_aabb = AABB(Vector3(-200, -110, -200), Vector3(400, 220, 400))
	add_child(instance)
	return multimesh


func _build_obstacles(layout: Dictionary) -> void:
	_obstacles.clear()
	_obstacle_grid.clear()
	for prop in layout["props"]:
		var half := LevelGenerator._half_extents(prop) + Vector2(0.35, 0.35)
		var obstacle := {"pos": Vector2(float(prop["pos"][0]), float(prop["pos"][1])), "half": half}
		var index := _obstacles.size()
		_obstacles.append(obstacle)
		var min_cell := Vector2i(((obstacle["pos"] as Vector2) - half) / HASH_CELL)
		var max_cell := Vector2i(((obstacle["pos"] as Vector2) + half) / HASH_CELL)
		for cx in range(min_cell.x - 1, max_cell.x + 2):
			for cz in range(min_cell.y - 1, max_cell.y + 2):
				var key := Vector2i(cx, cz)
				if not _obstacle_grid.has(key):
					_obstacle_grid[key] = []
				_obstacle_grid[key].append(index)


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null or _stats == null:
		return
	_time += delta
	_player_iframe -= delta
	_freeze_timer -= delta
	var player_pos := Vector2(_player.global_position.x, _player.global_position.z)

	_update_spawning(delta)
	_rebuild_hash()
	_update_boss_patterns(delta)
	_update_enemies(delta, player_pos)
	_update_weapon(delta, player_pos)
	_update_orbitals(delta, player_pos)
	_update_nova(delta)
	_update_projectiles(delta)
	_update_enemy_projectiles(delta, player_pos)


func _update_boss_patterns(delta: float) -> void:
	if _boss_slot < 0:
		return
	_boss_dash_time -= delta
	for pattern in _boss_patterns:
		AttackPatterns.tick(pattern, self, delta)


func _update_spawning(delta: float) -> void:
	if not spawning_enabled or _eligible_indices.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = RunBalance.spawn_interval(_level, _time, _config)
	# Batches grow with level + time survived (density ramps hard late).
	var batch := RunBalance.spawn_batch(_level, _time, _config)
	for i in range(batch):
		var type_index := _weighted_eligible_type()
		var def: Dictionary = _types[type_index]["def"]
		_spawn_enemy(type_index, _spawn_position(), float(def.get("hp", 20)), 1.0)


func _weighted_eligible_type() -> int:
	var total := 0.0
	for i in _eligible_indices:
		total += float(_types[i]["def"].get("weight", 1))
	var roll := _rng.randf() * total
	for i in _eligible_indices:
		roll -= float(_types[i]["def"].get("weight", 1))
		if roll <= 0.0:
			return i
	return _eligible_indices[0]


func _spawn_position() -> Vector2:
	var player_pos := Vector2(_player.global_position.x, _player.global_position.z)
	for i in range(12):
		var angle := _rng.randf_range(0.0, TAU)
		var candidate := player_pos + Vector2.from_angle(angle) * _rng.randf_range(SPAWN_RING_MIN, SPAWN_RING_MAX)
		candidate.x = clampf(candidate.x, -_arena_half.x + 1.5, _arena_half.x - 1.5)
		candidate.y = clampf(candidate.y, -_arena_half.y + 1.5, _arena_half.y - 1.5)
		if candidate.distance_to(player_pos) > 8.0:
			return candidate
	return Vector2(_arena_half.x - 2.0, 0)


func _spawn_enemy(type_index: int, position: Vector2, hp: float, scale: float) -> int:
	var type: Dictionary = _types[type_index]
	var free_slots: Array = type["free"]
	if free_slots.is_empty():
		return -1
	var slot: int = free_slots.pop_back()
	type["pos"][slot] = position
	type["vel"][slot] = Vector2.ZERO
	type["hp"][slot] = hp
	type["flash"][slot] = 0.0
	type["scale"][slot] = scale
	type["alive"][slot] = 1
	type["bmode"][slot] = MODE_NORMAL
	type["btimer"][slot] = float(type["def"].get("behavior", {}).get("interval", 3.0))
	type["active"] += 1
	return slot


func _kill_enemy(type_index: int, slot: int, emit_signals := true) -> void:
	var type: Dictionary = _types[type_index]
	if type["alive"][slot] == 0:
		return
	type["alive"][slot] = 0
	type["active"] -= 1
	type["free"].append(slot)
	var multimesh: MultiMesh = type["mm"]
	multimesh.set_instance_transform(slot, Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -100, 0)))
	var def_id := str(type["def"].get("id", "enemy"))
	if emit_signals:
		var p: Vector2 = type["pos"][slot]
		EventBus.enemy_killed.emit(def_id, Vector3(p.x, 0.5, p.y))
	if type_index == _boss_type and slot == _boss_slot:
		_boss_type = -1
		_boss_slot = -1
		_boss_patterns = []
		_boss_telegraph = false
		boss_killed.emit(_boss_id)


func _rebuild_hash() -> void:
	_hash.clear()
	for type_index in range(_types.size()):
		var type: Dictionary = _types[type_index]
		if type["active"] == 0:
			continue
		var alive: PackedByteArray = type["alive"]
		var pos: PackedVector2Array = type["pos"]
		for slot in range(MAX_PER_TYPE):
			if alive[slot] == 0:
				continue
			var key := Vector2i((pos[slot] / HASH_CELL).floor())
			var handle := type_index * MAX_PER_TYPE + slot
			if not _hash.has(key):
				_hash[key] = []
			_hash[key].append(handle)


func _update_enemies(delta: float, player_pos: Vector2) -> void:
	var boss_cfg: Dictionary = _config.get("boss", {})
	for type_index in range(_types.size()):
		var type: Dictionary = _types[type_index]
		if type["active"] == 0:
			continue
		var def: Dictionary = type["def"]
		var behavior: Dictionary = def.get("behavior", {})
		var behavior_type := str(behavior.get("type", "chase"))
		var phases := bool(def.get("phases", false))
		var alive: PackedByteArray = type["alive"]
		var pos: PackedVector2Array = type["pos"]
		var vel: PackedVector2Array = type["vel"]
		var flash: PackedFloat32Array = type["flash"]
		var scale: PackedFloat32Array = type["scale"]
		var bmode: PackedByteArray = type["bmode"]
		var btimer: PackedFloat32Array = type["btimer"]
		var bdir: PackedVector2Array = type["bdir"]
		var multimesh: MultiMesh = type["mm"]
		var base_speed := float(def.get("speed", 2.5))
		var damage := float(def.get("damage", 10))
		var radius := float(def.get("radius", 0.5))
		var half_height: float = type["half_height"]

		for slot in range(MAX_PER_TYPE):
			if alive[slot] == 0:
				continue
			var is_boss := type_index == _boss_type and slot == _boss_slot
			var speed := base_speed * (float(boss_cfg.get("speed_multiplier", 0.85)) if is_boss else 1.0)
			var enemy_damage := damage * (float(boss_cfg.get("damage_multiplier", 2.0)) if is_boss else 1.0)
			var enemy_radius := radius * scale[slot]
			var p := pos[slot]
			var telegraph := 0.0

			if _freeze_timer > 0.0:
				# Frozen solid: no movement, no contact damage, icy tint.
				vel[slot] = Vector2.ZERO
				flash[slot] = maxf(0.0, flash[slot] - delta * 5.0)
				multimesh.set_instance_color(slot, Color(0.6, 0.8, 1.4))
				continue
			multimesh.set_instance_color(slot, Color.WHITE)

			if is_boss and _boss_dash_time > 0.0:
				# Boss dash overrides steering (charge_dash pattern).
				vel[slot] = _boss_dash_dir * _boss_dash_speed
				p += vel[slot] * delta
			elif is_boss and _boss_telegraph:
				# Winding up: brake and pulse.
				vel[slot] = vel[slot].lerp(Vector2.ZERO, minf(1.0, 12.0 * delta))
				p += vel[slot] * delta
				telegraph = 0.5 + 0.5 * sin(_time * 20.0)
			elif behavior_type == "charge" and not is_boss:
				telegraph = _update_charge_behavior(delta, type, slot, player_pos, speed, behavior)
				p = pos[slot] + vel[slot] * delta
			else:
				# Default chase steering.
				vel[slot] = _steer(delta, p, vel[slot], player_pos, speed, type_index, slot)
				p += vel[slot] * delta

			# Prop pushout (ghosts phase through) + arena clamp.
			if not phases:
				p = _resolve_obstacles(p, enemy_radius)
			p.x = clampf(p.x, -_arena_half.x + 0.6, _arena_half.x - 0.6)
			p.y = clampf(p.y, -_arena_half.y + 0.6, _arena_half.y - 0.6)
			pos[slot] = p

			# Contact: player.
			if _player_iframe <= 0.0 and p.distance_to(player_pos) < enemy_radius + 0.5:
				_player_iframe = CONTACT_IFRAME_SEC
				EventBus.player_hit.emit(enemy_damage)
			# Contact: blob swarm members.
			if _swarm != null:
				_swarm.try_kill_near(p, enemy_radius + 0.35)

			# Render write.
			flash[slot] = maxf(0.0, flash[slot] - delta * 5.0)
			var render_flash := maxf(flash[slot], telegraph)
			var s := scale[slot]
			var basis := Basis().scaled(Vector3(s, s, s))
			multimesh.set_instance_transform(slot, Transform3D(basis, Vector3(p.x, half_height * s, p.y)))
			multimesh.set_instance_custom_data(slot, Color(1.0 if vel[slot].x < 0.0 else 0.0, render_flash, 0, 0))


## Chase steering: seek + neighbor separation. Returns new velocity.
func _steer(delta: float, p: Vector2, current_vel: Vector2, player_pos: Vector2, speed: float, type_index: int, slot: int) -> Vector2:
	var to_player := player_pos - p
	var dist := to_player.length()
	var desired := to_player / maxf(dist, 0.001) * speed
	var push := Vector2.ZERO
	var checked := 0
	var cell := Vector2i((p / HASH_CELL).floor())
	for cx in range(cell.x - 1, cell.x + 2):
		for cz in range(cell.y - 1, cell.y + 2):
			var bucket: Variant = _hash.get(Vector2i(cx, cz))
			if bucket == null:
				continue
			for handle in bucket:
				if checked >= 6:
					break
				@warning_ignore("integer_division")
				var other_type: int = handle / MAX_PER_TYPE
				var other_slot: int = handle % MAX_PER_TYPE
				if other_type == type_index and other_slot == slot:
					continue
				var other_pos: Vector2 = _types[other_type]["pos"][other_slot]
				var away := p - other_pos
				var d := away.length()
				if d < SEPARATION_RADIUS and d > 0.001:
					push += away / d * (SEPARATION_RADIUS - d)
					checked += 1
	var new_vel := desired + push * speed * 1.6
	var max_speed := speed * 1.3
	if new_vel.length() > max_speed:
		new_vel = new_vel.normalized() * max_speed
	return current_vel.lerp(new_vel, minf(1.0, 10.0 * delta))


## Charge behavior state machine. Returns telegraph flash amount (0..1).
func _update_charge_behavior(delta: float, type: Dictionary, slot: int, player_pos: Vector2, speed: float, behavior: Dictionary) -> float:
	var bmode: PackedByteArray = type["bmode"]
	var btimer: PackedFloat32Array = type["btimer"]
	var bdir: PackedVector2Array = type["bdir"]
	var pos: PackedVector2Array = type["pos"]
	var vel: PackedVector2Array = type["vel"]
	btimer[slot] -= delta
	match int(bmode[slot]):
		MODE_WINDUP:
			vel[slot] = vel[slot].lerp(Vector2.ZERO, minf(1.0, 12.0 * delta))
			if btimer[slot] <= 0.0:
				bmode[slot] = MODE_DASH
				btimer[slot] = float(behavior.get("dash_sec", 0.5))
				var to_player := player_pos - pos[slot]
				bdir[slot] = to_player.normalized() if to_player.length() > 0.01 else Vector2.RIGHT
				vel[slot] = bdir[slot] * speed * float(behavior.get("dash_speed_mult", 4.0))
			return 0.6
		MODE_DASH:
			vel[slot] = bdir[slot] * speed * float(behavior.get("dash_speed_mult", 4.0))
			if btimer[slot] <= 0.0:
				bmode[slot] = MODE_NORMAL
				btimer[slot] = float(behavior.get("interval", 3.5))
			return 0.0
		_:
			vel[slot] = _steer(delta, pos[slot], vel[slot], player_pos, speed, -1, -1)
			if btimer[slot] <= 0.0 and pos[slot].distance_to(player_pos) < float(behavior.get("trigger_range", 8.0)):
				bmode[slot] = MODE_WINDUP
				btimer[slot] = float(behavior.get("windup_sec", 0.7))
			return 0.0


func _resolve_obstacles(p: Vector2, radius: float) -> Vector2:
	var key := Vector2i((p / HASH_CELL).floor())
	var bucket: Variant = _obstacle_grid.get(key)
	if bucket == null:
		return p
	for index in bucket:
		var obstacle: Dictionary = _obstacles[index]
		var center: Vector2 = obstacle["pos"]
		var half: Vector2 = obstacle["half"]
		var closest := Vector2(
			clampf(p.x, center.x - half.x, center.x + half.x),
			clampf(p.y, center.y - half.y, center.y + half.y)
		)
		var away := p - closest
		var d := away.length()
		if d < radius:
			if d < 0.001:
				away = (p - center).normalized()
				d = 0.001
			p = closest + away / d * radius
	return p


# ---------------------------------------------------------------------------
# Player weapon + projectiles
# ---------------------------------------------------------------------------

func _update_weapon(delta: float, player_pos: Vector2) -> void:
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	var target := _nearest_enemy(player_pos, _stats.attack_range)
	if target == Vector2.INF:
		return
	_fire_timer = _stats.fire_interval
	var base_dir := (target - player_pos).normalized()
	var count := _stats.projectile_count
	for i in range(count):
		var spread := deg_to_rad(10.0) * (float(i) - float(count - 1) * 0.5)
		_spawn_projectile(player_pos, base_dir.rotated(spread))


func _nearest_enemy(from: Vector2, max_range: float) -> Vector2:
	var best := Vector2.INF
	var best_dist := max_range
	for type in _types:
		var alive: PackedByteArray = type["alive"]
		var pos: PackedVector2Array = type["pos"]
		if type["active"] == 0:
			continue
		for slot in range(MAX_PER_TYPE):
			if alive[slot] == 0:
				continue
			var d := from.distance_to(pos[slot])
			if d < best_dist:
				best_dist = d
				best = pos[slot]
	return best


func _spawn_projectile(from: Vector2, dir: Vector2) -> void:
	if _proj_count >= MAX_PROJECTILES:
		return
	_proj_pos[_proj_count] = from
	_proj_dir[_proj_count] = dir
	_proj_ttl[_proj_count] = PROJECTILE_TTL
	_proj_bounce[_proj_count] = _stats.projectile_bounces
	_proj_pierce[_proj_count] = _stats.projectile_pierce
	_proj_count += 1


## Wall/prop collision for projectiles. Returns the surface normal if the
## point is inside an obstacle or outside the arena, else Vector2.ZERO.
func _projectile_wall_normal(p: Vector2, radius: float) -> Vector2:
	if p.x < -_arena_half.x + radius:
		return Vector2.RIGHT
	if p.x > _arena_half.x - radius:
		return Vector2.LEFT
	if p.y < -_arena_half.y + radius:
		return Vector2.DOWN
	if p.y > _arena_half.y - radius:
		return Vector2.UP
	var bucket: Variant = _obstacle_grid.get(Vector2i((p / HASH_CELL).floor()))
	if bucket == null:
		return Vector2.ZERO
	for index in bucket:
		var obstacle: Dictionary = _obstacles[index]
		var center: Vector2 = obstacle["pos"]
		var half: Vector2 = obstacle["half"]
		var closest := Vector2(
			clampf(p.x, center.x - half.x, center.x + half.x),
			clampf(p.y, center.y - half.y, center.y + half.y))
		var away := p - closest
		var d := away.length()
		if d < radius:
			if d < 0.001:
				away = p - center
			return away.normalized() if away.length() > 0.001 else Vector2.RIGHT
	return Vector2.ZERO


func _update_projectiles(delta: float) -> void:
	var speed := _stats.projectile_speed
	var damage := _stats.effective_damage()
	var proj_radius := 0.3 * _stats.projectile_scale
	var i := 0
	while i < _proj_count:
		_proj_ttl[i] -= delta
		var p := _proj_pos[i] + _proj_dir[i] * speed * delta
		var dead := _proj_ttl[i] <= 0.0

		# Walls/props: bounce (Ricochet Windings) or break.
		if not dead:
			var normal := _projectile_wall_normal(p, proj_radius)
			if normal != Vector2.ZERO:
				if _proj_bounce[i] > 0:
					_proj_bounce[i] -= 1
					_proj_dir[i] = _proj_dir[i].bounce(normal)
					p = _proj_pos[i] + _proj_dir[i] * speed * delta
				else:
					dead = true
		_proj_pos[i] = p

		if not dead:
			# Enemy hits via spatial hash (pierce = Deep Groove Bearings).
			var cell := Vector2i((p / HASH_CELL).floor())
			for cx in range(cell.x - 1, cell.x + 2):
				if dead:
					break
				for cz in range(cell.y - 1, cell.y + 2):
					if dead:
						break
					var bucket: Variant = _hash.get(Vector2i(cx, cz))
					if bucket == null:
						continue
					for handle in bucket:
						@warning_ignore("integer_division")
						var type_index: int = handle / MAX_PER_TYPE
						var slot: int = handle % MAX_PER_TYPE
						var type: Dictionary = _types[type_index]
						if type["alive"][slot] == 0:
							continue
						var enemy_radius := float(type["def"].get("radius", 0.5)) * float(type["scale"][slot])
						if p.distance_to(type["pos"][slot]) < enemy_radius + proj_radius:
							_damage_enemy(type_index, slot, damage)
							if _proj_pierce[i] > 0:
								_proj_pierce[i] -= 1
							else:
								dead = true
							break

		if dead:
			_proj_count -= 1
			_proj_pos[i] = _proj_pos[_proj_count]
			_proj_dir[i] = _proj_dir[_proj_count]
			_proj_ttl[i] = _proj_ttl[_proj_count]
			_proj_bounce[i] = _proj_bounce[_proj_count]
			_proj_pierce[i] = _proj_pierce[_proj_count]
		else:
			i += 1

	var zero := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -100, 0))
	var proj_scale := _stats.projectile_scale
	for j in range(MAX_PROJECTILES):
		if j < _proj_count:
			var basis := Basis().scaled(Vector3(proj_scale, proj_scale, proj_scale))
			_proj_mm.set_instance_transform(j, Transform3D(basis, Vector3(_proj_pos[j].x, 0.8, _proj_pos[j].y)))
			_proj_mm.set_instance_custom_data(j, Color(fmod(float(j) * 0.37, 1.0), _proj_dir[j].x * 0.5, _proj_dir[j].y * 0.5, 0))
		else:
			_proj_mm.set_instance_transform(j, zero)


## Orbiting goop satellites (Stator Satellites card).
func _update_orbitals(delta: float, player_pos: Vector2) -> void:
	var count := mini(_stats.orbital_count, 12)
	_orbital_angle += delta * 2.4
	_orbital_hit_timer -= delta
	var zero := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -100, 0))
	var can_hit := _orbital_hit_timer <= 0.0
	if can_hit and count > 0:
		_orbital_hit_timer = 0.28
	for j in range(_orbital_mm.instance_count):
		if j >= count:
			_orbital_mm.set_instance_transform(j, zero)
			continue
		var angle := _orbital_angle + TAU * float(j) / float(count)
		var p := player_pos + Vector2.from_angle(angle) * 2.3
		_orbital_mm.set_instance_transform(j, Transform3D(Basis(), Vector3(p.x, 0.85, p.y)))
		_orbital_mm.set_instance_custom_data(j, Color(fmod(float(j) * 0.61, 1.0), cos(angle) * 0.4, sin(angle) * 0.4, 0))
		if can_hit:
			_orbital_damage_at(p, 0.55, _stats.effective_damage() * 0.8)


func _orbital_damage_at(p: Vector2, radius: float, damage: float) -> void:
	var bucket: Variant = _hash.get(Vector2i((p / HASH_CELL).floor()))
	if bucket == null:
		return
	for handle in bucket:
		@warning_ignore("integer_division")
		var type_index: int = handle / MAX_PER_TYPE
		var slot: int = handle % MAX_PER_TYPE
		var type: Dictionary = _types[type_index]
		if type["alive"][slot] == 0:
			continue
		var enemy_radius := float(type["def"].get("radius", 0.5)) * float(type["scale"][slot])
		if p.distance_to(type["pos"][slot]) < enemy_radius + radius:
			_damage_enemy(type_index, slot, damage)
			return


## Edging Nova card: periodic all-directions release.
func _update_nova(delta: float) -> void:
	if _stats.nova_interval <= 0.0:
		return
	_nova_timer -= delta
	if _nova_timer <= 0.0:
		_nova_timer = _stats.nova_interval
		fire_nova(20)


func _update_enemy_projectiles(delta: float, player_pos: Vector2) -> void:
	var i := 0
	while i < _eproj_count:
		_eproj_ttl[i] -= delta
		var p := _eproj_pos[i] + _eproj_dir[i] * _eproj_speed[i] * delta
		_eproj_pos[i] = p
		# Enemy projectiles break on walls AND props.
		var dead := _eproj_ttl[i] <= 0.0 \
			or _projectile_wall_normal(p, ENEMY_PROJECTILE_RADIUS) != Vector2.ZERO

		if not dead and p.distance_to(player_pos) < ENEMY_PROJECTILE_RADIUS + 0.45:
			if _player_iframe <= 0.0:
				_player_iframe = CONTACT_IFRAME_SEC * 0.5
				EventBus.player_hit.emit(_eproj_damage[i])
			dead = true

		if dead:
			_eproj_count -= 1
			_eproj_pos[i] = _eproj_pos[_eproj_count]
			_eproj_dir[i] = _eproj_dir[_eproj_count]
			_eproj_speed[i] = _eproj_speed[_eproj_count]
			_eproj_damage[i] = _eproj_damage[_eproj_count]
			_eproj_ttl[i] = _eproj_ttl[_eproj_count]
		else:
			i += 1

	var zero := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -100, 0))
	for j in range(MAX_ENEMY_PROJECTILES):
		if j < _eproj_count:
			_eproj_mm.set_instance_transform(j, Transform3D(Basis(), Vector3(_eproj_pos[j].x, 0.8, _eproj_pos[j].y)))
			_eproj_mm.set_instance_custom_data(j, Color(fmod(float(j) * 0.53, 1.0), _eproj_dir[j].x * 0.5, _eproj_dir[j].y * 0.5, 0))
		else:
			_eproj_mm.set_instance_transform(j, zero)


func _damage_enemy(type_index: int, slot: int, damage: float) -> void:
	var type: Dictionary = _types[type_index]
	type["hp"][slot] -= damage
	type["flash"][slot] = 1.0
	var p: Vector2 = type["pos"][slot]
	EventBus.enemy_hit.emit(str(type["def"].get("id", "enemy")), damage, Vector3(p.x, float(type["half_height"]) * float(type["scale"][slot]), p.y))
	if type["hp"][slot] <= 0.0:
		_kill_enemy(type_index, slot)
