class_name RunPlayer
extends CharacterBody3D

const BASE_SPEED := 7.0
const IDLE_FPS := 9.0
const EAT_DURATION := 0.28
const TURN_DURATION := 0.09

@export var acceleration := 6.5
@export var deceleration := 3.5

var camera: Camera3D
var stats: PlayerStats

var _regions: Dictionary = {}
var _anim_time := 0.0
var _eat_timer := 0.0
var _turn_timer := 0.0
var _succ_timer := 0.0
var _facing_left := false
var _dead := false
var _shield_ring: MeshInstance3D

@onready var _sprite: Sprite3D = $Sprite


func _ready() -> void:
	var equipped := str(SaveService.get_value("allans.equipped", "player1"))
	setup_skin(equipped)
	EventBus.blob_collected.connect(func(_amount: int) -> void: _eat_timer = EAT_DURATION)
	_make_shield_ring()


func _make_shield_ring() -> void:
	_shield_ring = MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.55
	mesh.outer_radius = 0.72
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/shaders/shield_glow.gdshader")
	mesh.material = material
	_shield_ring.mesh = mesh
	_shield_ring.position.y = 0.12
	_shield_ring.visible = false
	add_child(_shield_ring)


func set_shield_visible(active: bool) -> void:
	if _shield_ring != null:
		_shield_ring.visible = active


func play_succ(duration: float) -> void:
	_succ_timer = maxf(_succ_timer, duration)


func setup_skin(allan_id: String) -> void:
	var sheet := AllanSprites.sheet_texture(allan_id)
	if sheet == null:
		return
	_sprite.texture = sheet
	_sprite.region_enabled = true
	_regions = AllanSprites.state_regions()
	_set_frame("idle", 0)


func set_dead(dead: bool) -> void:
	_dead = dead
	if dead:
		_set_frame("cry", 0)


func flash_damage() -> void:
	_sprite.modulate = Color(1, 0.35, 0.35)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", Color.WHITE, 0.25)


func _physics_process(delta: float) -> void:
	if _dead:
		velocity = Vector3.ZERO
		return
	var mv: Vector2 = InputService.get_move_vector()
	var dir := Vector3.ZERO
	if camera != null and mv != Vector2.ZERO:
		var cam_basis := camera.global_transform.basis
		var right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
		var forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
		dir = right * mv.x + forward * -mv.y
	var speed := BASE_SPEED * (stats.speed_mult if stats != null else 1.0)
	var target := dir * speed
	var rate := acceleration if dir != Vector3.ZERO else deceleration
	velocity = velocity.lerp(target, minf(1.0, rate * delta))
	move_and_slide()
	_animate(delta, dir if dir != Vector3.ZERO else velocity * 0.1)


func _animate(delta: float, dir: Vector3) -> void:
	if absf(dir.x) > 0.05:
		var moving_left := dir.x < 0.0
		if moving_left != _facing_left:
			_facing_left = moving_left
			_turn_timer = TURN_DURATION

	_eat_timer = maxf(0.0, _eat_timer - delta)
	_turn_timer = maxf(0.0, _turn_timer - delta)
	_succ_timer = maxf(0.0, _succ_timer - delta)
	_anim_time += delta

	if _succ_timer > 0.0:
		_set_frame("succ", 0)
	elif _eat_timer > 0.0:
		var eat_frames: Array = _regions.get("eat", [])
		var index := 0 if _eat_timer > EAT_DURATION * 0.5 else 1
		_set_frame("eat", mini(index, eat_frames.size() - 1))
	elif _turn_timer > 0.0:
		_set_frame("turn", 0)
		_sprite.flip_h = false
		return
	elif dir != Vector3.ZERO:
		var idle_frames: Array = _regions.get("idle", [])
		_set_frame("idle", int(_anim_time * IDLE_FPS) % maxi(1, idle_frames.size()))
	else:
		_set_frame("idle", 0)
	_sprite.flip_h = _facing_left


func _set_frame(state: String, index: int) -> void:
	var frames: Array = _regions.get(state, [])
	if frames.is_empty():
		return
	_sprite.region_rect = frames[clampi(index, 0, frames.size() - 1)]
