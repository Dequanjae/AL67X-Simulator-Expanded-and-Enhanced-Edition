class_name WattsService
extends RefCounted
## Watts — the TIME currency (user spec, 2026-09-08): accrues in real time
## even while away, capped, spent on card upgrades (currency 'watts' in
## card_upgrades.json). Loaded lazily by EconomyService (autoload
## registration order can't be guaranteed).
##
## Accrual math is offline-safe: balance = stored + elapsed_hours * rate,
## clamped to cap. Stored balance syncs on read so time never double-counts.


const CONFIG_PATH := "res://data/balance/economy.json"


static func config() -> Dictionary:
	var data: Variant = JsonData.load_json(CONFIG_PATH)
	if data is Dictionary and data.has("watts"):
		return data.get("watts", {})
	return {"start": 30, "per_hour": 60, "cap": 480}


## Balance as of now (accrues between calls).
static func get_watts() -> int:
	var cfg := config()
	var cap := int(cfg.get("cap", 480))
	var now := _now_hours()
	var synced := float(SaveService.get_value("economy.watts_synced_hours", 0.0))
	if synced <= 0.0:
		# First-ever read: seed the balance with config.start and start the
		# accrual clock at 'now' (0.0 timestamp is epoch, not a real sync).
		SaveService.set_value("economy.watts", int(cfg.get("start", 30)))
		SaveService.set_value("economy.watts_synced_hours", now)
		EventBus.watts_changed.emit(int(cfg.get("start", 30)))
		return int(cfg.get("start", 30))
	var stored := int(SaveService.get_value("economy.watts", 0))
	# Only accrue from the last sync point; clamp so idle time can't overflow.
	var balance := stored + int((now - synced) * float(cfg.get("per_hour", 60)))
	balance = clampi(balance, 0, cap)
	# Sync point moves forward by exactly the consumed elapsed time.
	var consumed := float(balance - stored) / float(cfg.get("per_hour", 60))
	SaveService.set_value("economy.watts", balance)
	SaveService.set_value("economy.watts_synced_hours", synced + consumed)
	if balance >= cap:
		# At cap the sync point sits at 'now' so nothing accrues while full.
		SaveService.set_value("economy.watts_synced_hours", now)
	return balance


static func spend_watts(amount: int) -> bool:
	var balance := get_watts()
	if amount < 0 or balance < amount:
		return false
	SaveService.set_value("economy.watts", balance - amount)
	EventBus.watts_changed.emit(balance - amount)
	return true


static func add_watts(amount: int) -> void:
	if amount == 0:
		return
	var cfg := config()
	var balance := clampi(get_watts() + amount, 0, int(cfg.get("cap", 480)))
	SaveService.set_value("economy.watts", balance)
	EventBus.watts_changed.emit(balance)


static func _now_hours() -> float:
	return Time.get_unix_time_from_system() / 3600.0