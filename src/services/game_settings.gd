class_name GameSettings
extends RefCounted
## Player settings — persisted under meta.settings, applied live via
## EventBus.settings_changed. Defaults here; UI in the hub Settings panel.

const DEFAULTS := {
	"music_volume": 1.0,     # 0..1
	"sfx_volume": 1.0,       # 0..1
	"screen_shake": 1.0,     # 0..1 multiplier (0 = off)
	"camera_smoothing": true,
	"goo_splats": true,
	"damage_numbers": true,
}


static func get_value(key: String) -> Variant:
	return SaveService.get_value("meta.settings.%s" % key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	SaveService.set_value("meta.settings.%s" % key, value)
	EventBus.settings_changed.emit(key, value)


static func music_volume() -> float:
	return clampf(float(get_value("music_volume")), 0.0, 1.0)


static func sfx_volume() -> float:
	return clampf(float(get_value("sfx_volume")), 0.0, 1.0)


static func screen_shake() -> float:
	return clampf(float(get_value("screen_shake")), 0.0, 1.0)


static func camera_smoothing() -> bool:
	return bool(get_value("camera_smoothing"))


static func goo_splats() -> bool:
	return bool(get_value("goo_splats"))


static func damage_numbers() -> bool:
	return bool(get_value("damage_numbers"))


## Volume (0..1) → dB offset added to a player's base volume.
static func to_db_offset(volume: float) -> float:
	if volume <= 0.001:
		return -80.0
	return linear_to_db(volume)
