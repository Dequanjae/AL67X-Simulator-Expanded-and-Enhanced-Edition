extends Node
## Audio gate (Phase 10) — run headless (dummy audio driver still tracks
## player state):
##   godot --headless res://scenes/dev/audio_smoke_test.tscn
## Verifies: audio map integrity (every sfx path exists, pools populated),
## event→sound wiring (hits/pickups/reveals/purchases), the three distinct
## hit identities, music state machine (hub→gameplay→death→revive→hub),
## SFX throttling, taunt pool sharing, shop-music fallback plumbing, and
## the global button tap hook.
## Exits 0 on PASS, 1 on FAIL. NOTE: resets the local save file.

var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures.append(name)


func _run() -> void:
	await get_tree().create_timer(0.2).timeout
	SaveService.reset_to_defaults()

	# --- Map integrity ------------------------------------------------------
	var parsed: Variant = JsonData.load_json("res://data/audio/audio_map.json")
	_check(parsed is Dictionary, "audio map loads")
	var map: Dictionary = parsed if parsed is Dictionary else {}
	for key in map.get("sfx", {}):
		_check(ResourceLoader.exists(str(map["sfx"][key])), "sfx file exists: %s" % key)
	for key in ["hub", "gameplay", "death", "credits"]:
		var path := str(map.get("music", {}).get(key, ""))
		_check(path != "" and ResourceLoader.exists(path), "music mapped: %s" % key)
	_check(str(map.get("music", {}).get("shop", "?")) == "", "shop track is an empty plumbing slot (file-swap ready)")
	_check(AudioDirector._taunt_paths.size() >= 50, "shared taunt pool loaded (%d)" % AudioDirector._taunt_paths.size())
	_check(AudioDirector._transition_streams.size() >= 5, "transition stinger pool loaded (%d)" % AudioDirector._transition_streams.size())

	# --- Music state machine -------------------------------------------------
	AudioDirector.play_music("hub")  # boot triggers this after the splash
	_check(AudioDirector.current_music_key() == "hub", "hub music starts post-splash")
	EventBus.run_started.emit(1)
	_check(AudioDirector.current_music_key() == "gameplay", "run start → gameplay music")
	EventBus.player_died.emit()
	_check(AudioDirector.current_music_key() == "death", "death → death music")
	EventBus.player_revived.emit()
	_check(AudioDirector.current_music_key() == "gameplay", "revive → gameplay music")
	EventBus.run_ended.emit({"level": 1, "victory": false, "blobs_banked": 0, "duration_sec": 1.0, "reason": "ascend"})
	_check(AudioDirector.current_music_key() == "hub", "run end → hub music")
	await get_tree().process_frame
	_check(AudioDirector._music_active.playing, "music player actually playing")

	# --- Shop plumbing fallback ----------------------------------------------
	AudioDirector.on_hub_tab_changed("shop")
	_check(AudioDirector.current_music_key() == "hub", "missing shop track keeps hub music (no crash)")
	AudioDirector.on_hub_tab_changed("play")

	# --- Hit identities: three DISTINCT streams ------------------------------
	var streams: Dictionary = {}
	for pair in [["enemy_hit", "enemy"], ["player_hit", "player"], ["blob_hit", "blob"]]:
		var stream: AudioStream = AudioDirector._stream(str(map["sfx"][pair[0]]))
		_check(stream != null, "%s hit stream loads" % pair[1])
		streams[pair[0]] = stream
	_check(streams["enemy_hit"] != streams["player_hit"] and streams["player_hit"] != streams["blob_hit"] and streams["enemy_hit"] != streams["blob_hit"], "hit sounds are three distinct streams")

	# --- Event wiring plays through the pool ---------------------------------
	var checks := [
		[func() -> void: EventBus.enemy_hit.emit("yes_king", 10.0, Vector3.ZERO), "enemy_hit"],
		[func() -> void: EventBus.player_hit.emit(10.0), "player_hit"],
		[func() -> void: EventBus.blob_follower_hit.emit(), "blob_hit"],
		[func() -> void: EventBus.blob_collected.emit(1), "eat"],
		[func() -> void: EventBus.player_leveled_up.emit(1), "level_up"],
		[func() -> void: EventBus.allan_unlocked.emit("player2"), "unlock_sting"],
		[func() -> void: EventBus.purchase_failed.emit("x", "test"), "ui_error"],
	]
	for entry in checks:
		var playing_before := _playing_count()
		AudioDirector._sfx_last_played.clear()
		(entry[0] as Callable).call()
		await get_tree().process_frame
		_check(_playing_count() > playing_before or _pool_has_stream(str(map["sfx"][entry[1]])), "event plays %s" % entry[1])

	# --- Throttling: spamming one key uses few pool slots ---------------------
	for player in AudioDirector._sfx_pool:
		player.stop()
	AudioDirector._sfx_last_played.clear()
	for i in range(50):
		EventBus.enemy_hit.emit("yes_king", 1.0, Vector3.ZERO)
	var busy := _playing_count()
	_check(busy <= 2, "hit spam throttled (%d players busy)" % busy)

	# --- Boss taunt + global button hook --------------------------------------
	AudioDirector._taunt_player.stop()
	EventBus.boss_spawned.emit("boss_yes_king")
	_check(AudioDirector._taunt_player.playing, "boss spawn fires a taunt from the shared pool")

	for player in AudioDirector._sfx_pool:
		player.stop()
	AudioDirector._sfx_last_played.clear()
	var button := Button.new()
	add_child(button)
	await get_tree().process_frame
	button.pressed.emit()
	await get_tree().process_frame
	_check(_pool_has_stream(str(map["sfx"]["ui_tap"])), "global button hook plays ui_tap")

	# --- Report ---------------------------------------------------------------
	if _failures.is_empty():
		print("AUDIO TEST: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("AUDIO TEST: FAILED (%d)" % _failures.size())
	SaveService.reset_to_defaults()
	get_tree().quit(0 if _failures.is_empty() else 1)


func _playing_count() -> int:
	var count := 0
	for player in AudioDirector._sfx_pool:
		if player.playing:
			count += 1
	return count


func _pool_has_stream(path: String) -> bool:
	var target: AudioStream = AudioDirector._stream(path)
	for player in AudioDirector._sfx_pool:
		if player.playing and player.stream == target:
			return true
	return false
