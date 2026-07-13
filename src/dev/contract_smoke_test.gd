extends Node
## Contract smoke test (Phase 2 gate) — run headless:
##   godot --headless res://scenes/dev/contract_smoke_test.tscn
## Exits 0 on PASS, 1 on FAIL. NOTE: resets the local save file.

var _failures: PackedStringArray = []
var _last_blob_signal := -1
var _last_token_signal := -1
var _bus_events: PackedStringArray = []


func _ready() -> void:
	await get_tree().process_frame
	_run_tests()
	if _failures.is_empty():
		print("CONTRACT TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("CONTRACT TEST: FAILED (%d)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures.append(name)


func _run_tests() -> void:
	# --- Economy + signal contract -------------------------------------
	SaveService.reset_to_defaults()
	EventBus.blobs_changed.connect(func(v: int) -> void: _last_blob_signal = v)
	EventBus.tokens_changed.connect(func(v: int) -> void: _last_token_signal = v)

	_check(EconomyService.get_blobs() == 0, "fresh save has 0 blobs")
	_check(EconomyService.get_tokens() == 0, "fresh save has 0 tokens")

	EconomyService.add_blobs(150)
	_check(EconomyService.get_blobs() == 150, "add_blobs applies")
	_check(_last_blob_signal == 150, "blobs_changed emitted with new balance")

	_check(EconomyService.spend_blobs(50), "spend within balance succeeds")
	_check(EconomyService.get_blobs() == 100, "spend deducts")
	_check(not EconomyService.spend_blobs(1000), "overspend rejected")
	_check(EconomyService.get_blobs() == 100, "overspend leaves balance intact")

	EconomyService.debug_grant_tokens(100)
	_check(EconomyService.get_tokens() == 100, "debug token grant applies")
	_check(_last_token_signal == 100, "tokens_changed emitted")
	_check(EconomyService.spend_tokens(30), "token spend succeeds")
	_check(not EconomyService.spend_tokens(999), "token overspend rejected")

	# --- Save persistence roundtrip -------------------------------------
	SaveService.set_value("progress.highest_level_unlocked", 3)
	SaveService.set_value("cards.equipped", ["stub_card"])
	SaveService.save_now()
	SaveService.data = {}
	SaveService.load_game()
	_check(int(SaveService.get_value("progress.highest_level_unlocked", 1)) == 3, "level unlock persists")
	_check(EconomyService.get_blobs() == 100, "blob balance persists")
	_check(EconomyService.get_tokens() == 70, "token balance persists")
	var equipped: Array = SaveService.get_value("cards.equipped", [])
	_check(equipped == ["stub_card"], "deck persists")
	_check(SaveService.get_value("amps.max", -1) == 10, "schema migration fills defaults")

	# --- Data pipeline files ---------------------------------------------
	var allans: Variant = JsonData.load_json("res://data/allans/allans.json")
	_check(allans is Dictionary and allans.get("allans", []).size() == 10, "allan registry: 10 entries")
	if allans is Dictionary:
		for entry in allans["allans"]:
			if not ResourceLoader.exists(entry["sheet"]):
				_failures.append("allan sheet missing on disk: %s" % entry["sheet"])
	var curves: Variant = JsonData.load_json("res://data/balance/run_curves.json")
	_check(curves is Dictionary and curves.has("survival_timer") and curves.has("enemy_spawn"), "run curves load")
	var whats_new: Variant = JsonData.load_json("res://data/whats_new.json")
	_check(whats_new is Dictionary and whats_new.get("entries", []).size() >= 1, "whats_new feed loads")

	# --- Full run-loop signal traffic (mirrors run_placeholder flow) -----
	var tracked := [
		"run_started", "blob_collected", "blob_lost", "player_leveled_up",
		"player_died", "player_revived", "boss_defeated", "level_unlocked",
		"run_ended",
	]
	for signal_name in tracked:
		_check(EventBus.has_signal(signal_name), "EventBus has %s" % signal_name)
		EventBus.connect(signal_name, _make_recorder(signal_name))

	EventBus.run_started.emit(3)
	EventBus.blob_collected.emit(1)
	EventBus.blob_lost.emit(1)
	EventBus.player_leveled_up.emit(1)
	EventBus.player_died.emit()
	EventBus.player_revived.emit()
	EventBus.boss_defeated.emit("stub", 3)
	EventBus.level_unlocked.emit(4)
	EventBus.run_ended.emit({"level": 3, "victory": true, "blobs_banked": 0, "duration_sec": 1.0, "reason": "boss_defeated"})
	for signal_name in tracked:
		_check(signal_name in _bus_events, "signal delivered: %s" % signal_name)

	# Leave a clean default save behind.
	SaveService.reset_to_defaults()


func _make_recorder(signal_name: String) -> Callable:
	return func(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
		_bus_events.append(signal_name)
