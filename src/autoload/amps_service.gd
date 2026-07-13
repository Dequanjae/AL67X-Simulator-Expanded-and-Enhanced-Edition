extends Node
## AmpsService — global real-time energy/stamina pool (autoload).
##
## Generalizes what used to be merge-only "fusion energy" into ONE resource
## any system can spend from: merge minigame today, gameplay/shop later.
## Do not add a second energy pool — spend/refund through here.
##
## Real-time regen: lazy unix-timestamp accounting (regenerates while the
## app is closed; remainder preserved across restarts), configured by
## data/balance/amps.json. Persisted under SaveService "amps.*".

var _config: Dictionary = {}


func _ready() -> void:
	_config = _load_config()
	# Apply any regen owed since the last time the app was open.
	sync()


func _load_config() -> Dictionary:
	var parsed: Variant = JsonData.load_json("res://data/balance/amps.json")
	return parsed if parsed is Dictionary else {}


func get_max() -> int:
	return int(SaveService.get_value("amps.max", int(_config.get("max", 10))))


func set_max(new_max: int) -> void:
	SaveService.set_value("amps.max", maxi(1, new_max))
	EventBus.amps_changed.emit(get_current(), get_max())


func get_current() -> int:
	return int(SaveService.get_value("amps.current", get_max()))


func _regen_sec() -> int:
	return maxi(1, int(_config.get("regen_sec", 45)))


## Applies lazy regen based on elapsed real time since last accounting.
## Call before reading/spending so the value is always fresh. Returns the
## up-to-date current amount.
func sync() -> int:
	var max_amps := get_max()
	var current := get_current()
	var updated_at := int(SaveService.get_value("amps.updated_at", 0))
	var now := int(Time.get_unix_time_from_system())

	if updated_at <= 0:
		SaveService.set_value("amps.updated_at", now)
		return current
	if current >= max_amps:
		SaveService.set_value("amps.updated_at", now)
		return current

	var regen_sec := _regen_sec()
	var elapsed := now - updated_at
	@warning_ignore("integer_division")
	var gained := elapsed / regen_sec
	if gained <= 0:
		return current

	var new_current := mini(max_amps, current + gained)
	SaveService.set_value("amps.current", new_current)
	# Keep the remainder so partial progress isn't lost.
	var consumed := (new_current - current) * regen_sec
	SaveService.set_value("amps.updated_at", (now if new_current >= max_amps else updated_at + consumed))
	EventBus.amps_changed.emit(new_current, max_amps)
	return new_current


## Seconds until the next point regenerates; -1 when full.
func seconds_to_next() -> int:
	var max_amps := get_max()
	if get_current() >= max_amps:
		return -1
	var regen_sec := _regen_sec()
	var updated_at := int(SaveService.get_value("amps.updated_at", 0))
	var now := int(Time.get_unix_time_from_system())
	return maxi(0, regen_sec - (now - updated_at) % regen_sec)


## Spends `amount` Amps. Returns false (no change) if insufficient.
func spend(amount := 1, _reason := "") -> bool:
	var current := sync()
	if current < amount:
		return false
	# Spending from a full bar starts the regen clock now.
	if current >= get_max():
		SaveService.set_value("amps.updated_at", int(Time.get_unix_time_from_system()))
	var new_current := current - amount
	SaveService.set_value("amps.current", new_current)
	EventBus.amps_changed.emit(new_current, get_max())
	return true


## Refunds `amount` Amps (e.g. a cancelled/failed action). Never exceeds max.
func refund(amount := 1) -> void:
	var new_current := mini(get_max(), sync() + amount)
	SaveService.set_value("amps.current", new_current)
	EventBus.amps_changed.emit(new_current, get_max())


## Token top-up: instantly refills to max. Monetization hook — rejected when
## already full (no token waste) or insufficient tokens.
func refill_with_tokens() -> bool:
	var max_amps := get_max()
	if get_current() >= max_amps:
		return false
	var cost := int(_config.get("token_refill_cost", 20))
	if not EconomyService.spend_tokens(cost):
		EventBus.purchase_failed.emit("amps_refill", "insufficient_tokens")
		return false
	SaveService.set_value("amps.current", max_amps)
	SaveService.set_value("amps.updated_at", int(Time.get_unix_time_from_system()))
	EventBus.amps_changed.emit(max_amps, max_amps)
	EventBus.purchase_completed.emit("amps_refill")
	return true
