extends Node3D
## Dev smoke test: validates the core rendering architecture decision —
## a 3D world viewed through an orthographic isometric camera, with all
## characters rendered as billboarded 2D sprites (Sprite3D) in 3D space.
## Also validates the touch-first InputService movement abstraction.
##
## Run this scene directly. Drag (or click-drag with mouse, emulated as
## touch) to move Allan agar.io-style; WASD/arrows also work on desktop.

const MOVE_SPEED := 7.0

@onready var _actor: Node3D = $Actor
@onready var _camera_rig: Node3D = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera3D


func _ready() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 14.0
	# Classic isometric-look angle: 45° yaw, ~35.26° pitch.
	_camera.look_at_from_position(Vector3(10.0, 10.0, 10.0), Vector3.ZERO)


func _process(delta: float) -> void:
	var mv: Vector2 = InputService.get_move_vector()
	if mv == Vector2.ZERO:
		return
	# Map screen-space input (x right, y down) onto the ground plane
	# relative to the camera's yaw, so "up on screen" = "away from camera".
	var basis := _camera.global_transform.basis
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var dir := right * mv.x + forward * -mv.y
	_actor.position += dir * MOVE_SPEED * delta
	_camera_rig.position = _actor.position
