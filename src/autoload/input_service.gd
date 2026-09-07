extends Node
## InputService — touch-first movement + zoom input abstraction (autoload).
##
## Movement (agar.io feel):
##  - Mobile: while touching, Allan moves toward the finger (vector from
##    screen center, magnitude by distance up to a saturation radius).
##  - Desktop: Allan FOLLOWS THE MOUSE POINTER continuously (no click
##    needed) — classic agar.io. Activates after the first real mouse
##    motion so headless/tests aren't affected. WASD/arrows still work as
##    an override.
##  - Two fingers down = pinch (movement goes neutral).
##
## Zoom: scroll wheel (desktop) and pinch (mobile) accumulate into a delta
## consumed by the camera owner via [method consume_zoom_delta].
##
## Gameplay consumes ONLY get_move_vector() / consume_zoom_delta().

const SATURATION_RADIUS_PX := 160.0
const DEADZONE_PX := 24.0
const ZOOM_WHEEL_STEP := 1.2
const PINCH_ZOOM_SCALE := 0.02

var _touches: Dictionary = {}  # touch index -> screen position
var _pinch_prev_dist := -1.0
var _zoom_accum := 0.0
var _mouse_seen := false
var _last_touch_vector := Vector2.ZERO  # mobile keeps drifting this way
# --- Virtual joystick (hold anywhere) ---
## Anchor point for the floating joystick: where the first finger landed.
var _stick_anchor := Vector2.ZERO
var _stick_active := false


func _ready() -> void:
	# Input abstraction must keep working while the tree is paused (menus,
	# death panel).
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_stick_anchor = event.position
				_stick_active = true
		else:
			_touches.erase(event.index)
			if _touches.is_empty():
				_stick_active = false
		if _touches.size() != 2:
			_pinch_prev_dist = -1.0
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index] = event.position
		if _touches.size() == 2:
			var points: Array = _touches.values()
			var dist: float = (points[0] as Vector2).distance_to(points[1])
			if _pinch_prev_dist > 0.0:
				_zoom_accum += (_pinch_prev_dist - dist) * PINCH_ZOOM_SCALE
			_pinch_prev_dist = dist
	elif event is InputEventMouseMotion:
		_mouse_seen = true
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_accum -= ZOOM_WHEEL_STEP
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_accum += ZOOM_WHEEL_STEP


## Returns the current movement intent as a screen-space vector, length 0..1.
func get_move_vector() -> Vector2:
	# Pinching: movement neutral.
	if _touches.size() >= 2:
		_last_touch_vector = Vector2.ZERO
		return Vector2.ZERO
	# Active touch: floating joystick — vector from the FINGER-DOWN anchor,
	# not from screen center (hold anywhere on screen).
	if _touches.size() == 1:
		_last_touch_vector = _vector_from_anchor(_touches.values()[0])
		return _last_touch_vector
	# Keyboard override for desktop dev.
	var kb := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if kb != Vector2.ZERO:
		_last_touch_vector = Vector2.ZERO
		return kb
	# Desktop: follow the pointer continuously (agar.io) whenever a real
	# mouse has been seen — no click required.
	if _mouse_seen:
		var viewport := get_viewport()
		if viewport != null:
			return _vector_toward(viewport.get_mouse_position())
	# Mobile with no finger down: keep drifting in the last direction
	# (agar.io feel — lifting your thumb doesn't slam the brakes).
	return _last_touch_vector


## Accumulated zoom since last call (positive = zoom out). Camera owner
## consumes this every frame.
func consume_zoom_delta() -> float:
	var delta := _zoom_accum
	_zoom_accum = 0.0
	return delta


func is_touch_active() -> bool:
	return not _touches.is_empty()


func _vector_toward(screen_point: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var center := viewport.get_visible_rect().size * 0.5
	var offset := screen_point - center
	var dist := offset.length()
	if dist < DEADZONE_PX:
		return Vector2.ZERO
	return offset.normalized() * clampf(dist / SATURATION_RADIUS_PX, 0.0, 1.0)


## Floating joystick vector: from where the finger LANDED (anchor) to where
## it is now. Same deadzone/saturation as the old center-based scheme, so the
## feel is identical — but the anchor is anywhere the thumb rests.
func _vector_from_anchor(screen_point: Vector2) -> Vector2:
	var offset := screen_point - _stick_anchor
	var dist := offset.length()
	if dist < DEADZONE_PX:
		return Vector2.ZERO
	return offset.normalized() * clampf(dist / SATURATION_RADIUS_PX, 0.0, 1.0)
