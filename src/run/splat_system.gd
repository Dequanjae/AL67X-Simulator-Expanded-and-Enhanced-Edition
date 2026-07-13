class_name SplatSystem
extends Node3D
## White "goo blood": enemies leak white liquid when hit and burst when
## killed. Persistent floor splats in one MultiMesh (ring buffer — the map
## slowly fills up), procedural blob texture, zero art dependencies.

const MAX_SPLATS := 1000
const SPLAT_TEXTURE_SIZE := 96

var _mm: MultiMesh
var _write := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	mesh.orientation = PlaneMesh.FACE_Y
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _make_splat_texture()
	material.albedo_color = Color(0.96, 0.96, 0.94, 0.92)
	# Ground decals must draw UNDER actors: transparent geometry doesn't
	# write depth, so force the splats to render first among transparents.
	material.render_priority = -20
	material.no_depth_test = false
	mesh.material = material

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = MAX_SPLATS
	var zero := Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0, -100, 0))
	for i in range(MAX_SPLATS):
		_mm.set_instance_transform(i, zero)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _mm
	instance.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 20, 400))
	add_child(instance)

	EventBus.enemy_hit.connect(_on_enemy_hit)
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _on_enemy_hit(_id: String, _damage: float, world_pos: Vector3) -> void:
	# Leak a little on hits (not every hit — keep the fill rate readable).
	if _rng.randf() < 0.45:
		_splat(Vector2(world_pos.x, world_pos.z), _rng.randf_range(0.35, 0.7))


func _on_enemy_killed(_id: String, world_pos: Vector3) -> void:
	# Burst: one big pool + satellites.
	var center := Vector2(world_pos.x, world_pos.z)
	_splat(center, _rng.randf_range(1.1, 1.7))
	for i in range(_rng.randi_range(2, 4)):
		_splat(center + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(0.5, 1.2), _rng.randf_range(0.3, 0.6))


func _splat(pos: Vector2, size: float) -> void:
	if not GameSettings.goo_splats():
		return
	var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(size, 1, size))
	# Tiny per-slot height offset avoids z-fighting between overlapping pools.
	var y := 0.015 + float(_write % 24) * 0.0006
	_mm.set_instance_transform(_write, Transform3D(basis, Vector3(pos.x, y, pos.y)))
	_write = (_write + 1) % MAX_SPLATS


## Irregular soft-edged blob (few sine harmonics on the radius).
func _make_splat_texture() -> ImageTexture:
	var size := SPLAT_TEXTURE_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var p1 := _rng.randf_range(0.0, TAU)
	var p2 := _rng.randf_range(0.0, TAU)
	for py in range(size):
		for px in range(size):
			var v := Vector2(float(px) / size - 0.5, float(py) / size - 0.5)
			var angle := v.angle()
			var edge := 0.34 + 0.08 * sin(angle * 3.0 + p1) + 0.05 * sin(angle * 7.0 + p2)
			var d := v.length()
			if d < edge:
				var alpha: float = clampf((edge - d) / 0.06, 0.0, 1.0)
				image.set_pixel(px, py, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)
