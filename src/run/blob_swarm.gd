class_name BlobSwarm
extends Node3D
## Mini-Allan follower swarm — the visual mass of Blobs rescued this run
## (spec Section 5). Same scale architecture as the horde: steering forces,
## one batched update over flat arrays, one MultiMesh draw call.
##
## Sync contract: swarm size ALWAYS mirrors the in-run blob count.
##  - EventBus.blob_collected → +N members (emitted by pickups)
##  - enemy contact → this system removes the member and emits
##    blob_follower_hit + blob_lost(1) (RunController decrements its counter
##    from the same signal — one source of truth, no drift).
## On a member death the nearby swarm scatters outward (agar.io-style
## flinch) before re-settling into the follow ring.

const MAX_MEMBERS := 600
const FOLLOW_SPEED := 9.0
const FOLLOW_RING := 1.3          # members idle inside this distance ring
const SEPARATION_RADIUS := 0.55
const SCATTER_RADIUS := 3.0
const SCATTER_IMPULSE := 9.0
const KILL_COOLDOWN_SEC := 0.25
const MEMBER_HEIGHT := 0.8
const HASH_CELL := 1.5
const BILLBOARD_SHADER := "res://src/shaders/billboard_sprite.gdshader"

var _player: Node3D
var _count := 0
var _pos: PackedVector2Array
var _vel: PackedVector2Array
var _mm: MultiMesh
var _kill_cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var _hash: Dictionary = {}


func setup(player: Node3D, allan_id: String) -> void:
	_player = player
	_rng.randomize()
	_pos = PackedVector2Array()
	_pos.resize(MAX_MEMBERS)
	_vel = PackedVector2Array()
	_vel.resize(MAX_MEMBERS)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(MEMBER_HEIGHT * AllanSprites.frame_aspect(), MEMBER_HEIGHT)
	var material := ShaderMaterial.new()
	material.shader = load(BILLBOARD_SHADER)
	var texture := AllanSprites.sheet_texture(allan_id)
	if texture != null:
		material.set_shader_parameter("sprite_tex", texture)
		material.set_shader_parameter("uv_rect", AllanSprites.frame_uv_rect(allan_id, 0))
	mesh.material = material

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = MAX_MEMBERS
	var zero := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -100, 0))
	for i in range(MAX_MEMBERS):
		_mm.set_instance_transform(i, zero)
		_mm.set_instance_color(i, Color.WHITE)
		_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	var instance := MultiMeshInstance3D.new()
	instance.name = "SwarmMesh"
	instance.multimesh = _mm
	instance.custom_aabb = AABB(Vector3(-200, -110, -200), Vector3(400, 220, 400))
	add_child(instance)

	EventBus.blob_collected.connect(_on_blob_collected)


func member_count() -> int:
	return _count


## Called by HordeSystem on enemy contact. Rate-limited so one enemy pass
## doesn't shred the whole swarm. Removing a member IS the economic loss:
## emits blob_follower_hit (feedback) + blob_lost (counter sync).
func try_kill_near(point: Vector2, radius: float) -> bool:
	if _kill_cooldown > 0.0 or _count == 0:
		return false
	for i in range(_count):
		if _pos[i].distance_to(point) < radius:
			_remove_member(i)
			_scatter_from(point)
			_kill_cooldown = KILL_COOLDOWN_SEC
			EventBus.blob_follower_hit.emit()
			EventBus.blob_lost.emit(1)
			return true
	return false


func _on_blob_collected(amount: int) -> void:
	if _player == null:
		return
	var player_pos := Vector2(_player.global_position.x, _player.global_position.z)
	for i in range(amount):
		if _count >= MAX_MEMBERS:
			return
		var offset := Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(0.4, 1.2)
		_pos[_count] = player_pos + offset
		_vel[_count] = Vector2.ZERO
		_count += 1


func _remove_member(index: int) -> void:
	_count -= 1
	_pos[index] = _pos[_count]
	_vel[index] = _vel[_count]
	var zero := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -100, 0))
	_mm.set_instance_transform(_count, zero)


func _scatter_from(point: Vector2) -> void:
	for i in range(_count):
		var away := _pos[i] - point
		var d := away.length()
		if d < SCATTER_RADIUS:
			var dir := away / d if d > 0.001 else Vector2.from_angle(_rng.randf_range(0.0, TAU))
			_vel[i] += dir * SCATTER_IMPULSE * (1.0 - d / SCATTER_RADIUS)


func _physics_process(delta: float) -> void:
	_kill_cooldown -= delta
	if _player == null or _count == 0:
		return
	var player_pos := Vector2(_player.global_position.x, _player.global_position.z)

	# Spatial hash for member separation.
	_hash.clear()
	for i in range(_count):
		var key := Vector2i((_pos[i] / HASH_CELL).floor())
		if not _hash.has(key):
			_hash[key] = []
		_hash[key].append(i)

	for i in range(_count):
		var p := _pos[i]
		var to_player := player_pos - p
		var dist := to_player.length()
		# Arrive: full speed when far, ease off inside the follow ring.
		var desired := Vector2.ZERO
		if dist > FOLLOW_RING:
			var strength: float = clampf((dist - FOLLOW_RING) / 2.0, 0.15, 1.0)
			desired = to_player / dist * FOLLOW_SPEED * strength
		# Separation.
		var push := Vector2.ZERO
		var checked := 0
		var cell := Vector2i((p / HASH_CELL).floor())
		for cx in range(cell.x - 1, cell.x + 2):
			for cz in range(cell.y - 1, cell.y + 2):
				var bucket: Variant = _hash.get(Vector2i(cx, cz))
				if bucket == null:
					continue
				for j in bucket:
					if j == i or checked >= 5:
						continue
					var away := p - _pos[j]
					var d := away.length()
					if d < SEPARATION_RADIUS and d > 0.001:
						push += away / d * (SEPARATION_RADIUS - d)
						checked += 1
		_vel[i] = _vel[i].lerp(desired + push * 6.0, minf(1.0, 8.0 * delta))
		# Never left behind: hard catch-up if straggling far away.
		if dist > 10.0:
			_vel[i] = to_player / dist * FOLLOW_SPEED * 1.6
		_pos[i] = p + _vel[i] * delta

		_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(_pos[i].x, MEMBER_HEIGHT * 0.55, _pos[i].y)))
		_mm.set_instance_custom_data(i, Color(1.0 if _vel[i].x < 0.0 else 0.0, 0, 0, 0))
