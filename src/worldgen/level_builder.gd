class_name LevelBuilder
extends Node3D
## Turns a LevelGenerator layout + theme into 3D nodes:
##  - floor: one MeshInstance3D with procedural shader (checker + accent),
##  - boundary walls with collision,
##  - props: StaticBody3D + primitive mesh + collision shape.
##
## Physics layers: 1 = world (walls/props), 2 = player, pickups mask 2.

const WALL_HEIGHT := 2.2
const WALL_THICKNESS := 1.0

var _material_cache: Dictionary = {}
var _mesh_scene_cache: Dictionary = {}


func build(layout: Dictionary, theme: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	_material_cache.clear()
	var arena: Vector2 = layout["arena_size"]
	var colors: Dictionary = theme.get("colors", {})
	var textures: Dictionary = theme.get("textures", {})
	_build_floor(arena, colors, textures)
	_build_walls(arena, colors, textures)
	for prop in layout["props"]:
		_build_prop(prop)


func _build_floor(arena: Vector2, colors: Dictionary, textures: Dictionary) -> void:
	var floor_color := Color.html(str(colors.get("floor", "#4a4f57")))
	var alt_color := Color.html(str(colors.get("floor_alt", "#42464e")))
	var accent := Color.html(str(colors.get("accent", "#c9a86a")))
	var nx := maxi(1, int(arena.x))
	var nz := maxi(1, int(arena.y))

	var mesh := BoxMesh.new()
	mesh.size = Vector3(maxf(0.98, arena.x), 0.12, maxf(0.98, arena.y))
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/shaders/floor_checker.gdshader")
	material.set_shader_parameter("color1", floor_color)
	material.set_shader_parameter("color2", alt_color)
	material.set_shader_parameter("accent", accent)
	material.set_shader_parameter("tile_count", maxf(nx, nz))
	var floor_tex_path := str(textures.get("floor", ""))
	if ResourceLoader.exists(floor_tex_path):
		material.set_shader_parameter("floor_tex", load(floor_tex_path))
		material.set_shader_parameter("tex_strength", 0.5)
	mesh.material = material

	var instance := MeshInstance3D.new()
	instance.name = "FloorTiles"
	instance.mesh = mesh
	add_child(instance)


func _build_walls(arena: Vector2, colors: Dictionary, textures: Dictionary) -> void:
	var wall_color := Color.html(str(colors.get("wall", "#6b5a45")))
	var wall_material := _material_for(wall_color)
	var wall_tex_path := str(textures.get("wall", ""))
	if ResourceLoader.exists(wall_tex_path):
		wall_material = StandardMaterial3D.new()
		wall_material.albedo_texture = load(wall_tex_path)
		wall_material.albedo_color = wall_color.lerp(Color.WHITE, 0.55)
		wall_material.roughness = 0.95
		wall_material.uv1_scale = Vector3(6, 1, 6)
	var half := arena * 0.5
	var specs := [
		# [center, size]
		[Vector3(0, WALL_HEIGHT * 0.5, -half.y - WALL_THICKNESS * 0.5), Vector3(arena.x + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS)],
		[Vector3(0, WALL_HEIGHT * 0.5, half.y + WALL_THICKNESS * 0.5), Vector3(arena.x + WALL_THICKNESS * 2.0, WALL_HEIGHT, WALL_THICKNESS)],
		[Vector3(-half.x - WALL_THICKNESS * 0.5, WALL_HEIGHT * 0.5, 0), Vector3(WALL_THICKNESS, WALL_HEIGHT, arena.y)],
		[Vector3(half.x + WALL_THICKNESS * 0.5, WALL_HEIGHT * 0.5, 0), Vector3(WALL_THICKNESS, WALL_HEIGHT, arena.y)],
	]
	for spec in specs:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = spec[0]
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = spec[1]
		mesh.material = wall_material
		mesh_instance.mesh = mesh
		body.add_child(mesh_instance)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		body.add_child(shape)
		add_child(body)


func _build_prop(prop: Dictionary) -> void:
	var size := Vector3(float(prop["size"][0]), float(prop["size"][1]), float(prop["size"][2]))
	var color := Color.html(str(prop.get("color", "#888888")))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(float(prop["pos"][0]), size.y * 0.5, float(prop["pos"][1]))
	body.rotation_degrees = Vector3(0, float(prop.get("rot", 0.0)), 0)

	var mesh_instance := MeshInstance3D.new()
	var shape := CollisionShape3D.new()
	var shape_name := str(prop.get("shape", "box"))
	if shape_name == "mesh":
		var scene := _mesh_scene_for(str(prop.get("mesh", "")))
		if scene != null:
			var model: Node3D = scene.instantiate()
			var model_scale := size.y / 1.2
			model.scale = Vector3.ONE * model_scale
			body.add_child(model)
			model.position.y = -size.y * 0.5
		else:
			push_warning("LevelBuilder: mesh prop missing model '%s' — box fallback" % prop.get("mesh", ""))
			var fallback := BoxMesh.new()
			fallback.size = size
			fallback.material = _material_for(color)
			mesh_instance.mesh = fallback
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
	elif shape_name == "cylinder":
		var mesh := CylinderMesh.new()
		mesh.top_radius = size.x * 0.5
		mesh.bottom_radius = size.x * 0.5
		mesh.height = size.y
		mesh.material = _material_for(color)
		mesh_instance.mesh = mesh
		var cylinder := CylinderShape3D.new()
		cylinder.radius = size.x * 0.5
		cylinder.height = size.y
		shape.shape = cylinder
	else:
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = _material_for(color)
		mesh_instance.mesh = mesh
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
	body.add_child(mesh_instance)
	body.add_child(shape)
	add_child(body)


func _mesh_scene_for(path: String) -> PackedScene:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if not _mesh_scene_cache.has(path):
		_mesh_scene_cache[path] = load(path)
	return _mesh_scene_cache[path]


func _material_for(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		_material_cache[key] = material
	return _material_cache[key]
