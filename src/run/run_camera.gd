class_name RunCamera
extends Node3D
## Camera rig: trails the player with momentum (not hard-locked), screen
## shake on impacts, and a boss-intro pan (fly to the boss spawn, hold,
## fly back — shows the player where the boss came in).

@export var follow_speed := 4.5
@export var pan_speed := 7.0
@export var shake_decay := 3.0

var target: Node3D

var _follow_pos := Vector3.ZERO
var _shake := 0.0
var _pan_target := Vector3.ZERO
var _pan_phase := 0  # 0 = follow, 1 = flying out, 2 = holding, 3 = returning
var _pan_hold := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func snap_to_target() -> void:
	if target != null:
		_follow_pos = target.global_position
		global_position = _follow_pos


func shake(amount: float) -> void:
	# Settings: shake intensity multiplier (0 disables).
	_shake = maxf(_shake, amount * GameSettings.screen_shake())


## Boss intro: pan out to `world_pos`, hold, return to the player.
func intro_pan(world_pos: Vector3, hold_sec := 0.8) -> void:
	_pan_target = world_pos
	_pan_hold = hold_sec
	_pan_phase = 1


func _process(delta: float) -> void:
	if target == null:
		return
	_shake = maxf(0.0, _shake - shake_decay * delta * _shake - 0.2 * delta)
	match _pan_phase:
		1:
			_follow_pos = _follow_pos.lerp(_pan_target, minf(1.0, pan_speed * delta))
			if _follow_pos.distance_to(_pan_target) < 0.8:
				_pan_phase = 2
		2:
			_pan_hold -= delta
			if _pan_hold <= 0.0:
				_pan_phase = 3
		3:
			_follow_pos = _follow_pos.lerp(target.global_position, minf(1.0, pan_speed * delta))
			if _follow_pos.distance_to(target.global_position) < 0.8:
				_pan_phase = 0
		_:
			# Trailing follow: eases after the player, so momentum reads.
			# (Settings can disable smoothing → near-instant lock.)
			var speed := follow_speed if GameSettings.camera_smoothing() else 30.0
			_follow_pos = _follow_pos.lerp(target.global_position, minf(1.0, speed * delta))
	var shake_offset := Vector3(
		_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)
	) * _shake * 0.35
	global_position = _follow_pos + shake_offset
