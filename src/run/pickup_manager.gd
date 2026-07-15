class_name PickupManager
extends Node3D
## Spawns and maintains run-map pickups per the level theme's `spawns`
## config (data/levels/theme_*.json):
##  - Shawarmas/Doinairs: full-map-spread, RESPAWNING soft-currency pickups.
##  - Powerups: icon = ANY PNG dropped in assets/sprites/items/powerups/
##    (folder-scanned, agent-addable); effect = weighted random roll from
##    data/powerups/powerups.json's effect pool.
##  - Free loot boxes: rare chance replacing a powerup spawn tick.
## Also runs the SUCC vacuum: shawarmas fly to the player while active.

const SHAWARMA_TEXTURES: Array[String] = [
	"res://assets/sprites/items/blobs/shawarma.png",
	"res://assets/sprites/items/blobs/doinair.png",
]
const POWERUP_ICON_DIR := "res://assets/sprites/items/powerups"
## Pickups never spawn closer than this to the player.
const MIN_PLAYER_DISTANCE := 4.0
const VACUUM_SPEED := 13.0

var _walkable: PackedVector3Array = PackedVector3Array()
var _config: Dictionary = {}
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _effect_pool: Array = []
var _icon_paths: PackedStringArray = []
var _shawarma_count := 0
var _respawn_timer := 0.0
var _powerup_timer := 0.0
var _vacuum_timer := 0.0
var _active := false


func configure(walkable_points: PackedVector3Array, spawn_config: Dictionary, player: Node3D) -> void:
	_walkable = walkable_points
	_config = spawn_config
	_player = player
	_rng.randomize()
	var powerups_data: Variant = JsonData.load_json("res://data/powerups/powerups.json")
	_effect_pool = powerups_data.get("effects", []) if powerups_data is Dictionary else []
	_icon_paths = JsonData.list_files(POWERUP_ICON_DIR, "png")
	# Initial fill.
	for i in range(int(_config.get("shawarma_max", 20))):
		_spawn_shawarma()
	_powerup_timer = _roll_powerup_interval()
	_active = true


## SUCC powerup: vacuum shawarmas toward Allan for `seconds`.
func start_vacuum(seconds: float) -> void:
	_vacuum_timer = maxf(_vacuum_timer, seconds)


func _process(delta: float) -> void:
	if not _active:
		return
	var max_shawarma := int(_config.get("shawarma_max", 20))
	if _shawarma_count < max_shawarma:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_spawn_shawarma()
			_respawn_timer = float(_config.get("shawarma_respawn_sec", 2.5))
	_powerup_timer -= delta
	if _powerup_timer <= 0.0:
		if _rng.randf() < float(_config.get("lootbox_chance", 0.15)):
			_spawn_loot_box()
		else:
			_spawn_powerup()
		_powerup_timer = _roll_powerup_interval()
	# Vacuum: drag every shawarma toward the player.
	_vacuum_timer -= delta
	if _vacuum_timer > 0.0 and _player != null:
		var target := _player.global_position
		for child in get_children():
			if child is RunPickup and (child as RunPickup).type == RunPickup.Type.SHAWARMA:
				var pickup := child as RunPickup
				var to_player: Vector3 = target - pickup.global_position
				pickup.global_position += to_player.normalized() * minf(VACUUM_SPEED * delta, to_player.length())


## Used by tests and (later) HUD pings.
func get_active_shawarma_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for child in get_children():
		if child is RunPickup and child.type == RunPickup.Type.SHAWARMA:
			out.append(child.global_position)
	return out


# ---------------------------------------------------------------------------

func _roll_powerup_interval() -> float:
	var interval: Array = _config.get("powerup_interval_sec", [18, 32])
	return _rng.randf_range(float(interval[0]), float(interval[1]))


func _spawn_point() -> Vector3:
	if _walkable.is_empty():
		return Vector3.ZERO
	for i in range(24):
		var point := _walkable[_rng.randi_range(0, _walkable.size() - 1)]
		if _player == null or point.distance_to(_player.global_position) >= MIN_PLAYER_DISTANCE:
			return point
	return _walkable[_rng.randi_range(0, _walkable.size() - 1)]


func _spawn_shawarma() -> void:
	var pickup := _make_pickup(RunPickup.Type.SHAWARMA, "", 1)
	var texture_path: String = SHAWARMA_TEXTURES[_rng.randi_range(0, SHAWARMA_TEXTURES.size() - 1)]
	pickup.add_child(_make_sprite(texture_path, 0.0032, 0.5))
	add_child(pickup)
	pickup.global_position = _spawn_point()
	_shawarma_count += 1
	pickup.collected.connect(func(_p: RunPickup) -> void: _shawarma_count -= 1)


func _spawn_powerup() -> void:
	if _effect_pool.is_empty() or _icon_paths.is_empty():
		return
	var effect: Dictionary = _weighted_pick(_effect_pool)
	var pickup := _make_pickup(RunPickup.Type.POWERUP, str(effect.get("id", "?")), 1)
	# Any PNG dropped in the powerups folder is a valid item icon.
	var icon: String = _icon_paths[_rng.randi_range(0, _icon_paths.size() - 1)]
	pickup.add_child(_make_sprite(icon, 0.0028, 0.65))
	add_child(pickup)
	pickup.global_position = _spawn_point()


func _spawn_loot_box() -> void:
	# Box id is theme data (defaults to the basic box); collecting banks it
	# into inventory via EconomyService's loot_box_collected listener.
	var box_id := str(_config.get("lootbox_id", "basic_box"))
	var pickup := _make_pickup(RunPickup.Type.LOOT_BOX, box_id, 1)
	# Placeholder visual: gold box mesh (no loot box art yet).
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 0.8, 0.8)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.78, 0.2)
	material.metallic = 0.4
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 0.4
	pickup.add_child(mesh_instance)
	add_child(pickup)
	pickup.global_position = _spawn_point()
	EventBus.loot_box_spawned.emit(pickup.global_position)


func _make_pickup(type: int, payload: String, amount: int) -> RunPickup:
	var pickup := RunPickup.new()
	pickup.type = type
	pickup.payload = payload
	pickup.amount = amount
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	shape.shape = sphere
	shape.position.y = 0.5
	pickup.add_child(shape)
	return pickup


func _make_sprite(texture_path: String, pixel_size: float, y_offset: float) -> Sprite3D:
	var sprite := Sprite3D.new()
	if ResourceLoader.exists(texture_path):
		var tex: Texture2D = load(texture_path)
		sprite.texture = tex
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://src/shaders/passthrough_sprite.gdshader")
		mat.set_shader_parameter("sprite_tex", tex)
		sprite.material_override = mat
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.pixel_size = pixel_size
	sprite.position.y = y_offset
	return sprite


func _weighted_pick(pool: Array) -> Dictionary:
	var total := 0.0
	for entry in pool:
		total += float(entry.get("weight", 1))
	var roll := _rng.randf() * total
	for entry in pool:
		roll -= float(entry.get("weight", 1))
		if roll <= 0.0:
			return entry
	return pool.back()
