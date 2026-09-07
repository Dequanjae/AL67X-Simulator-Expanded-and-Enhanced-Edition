extends Node
## AudioDirector — the single audio system (autoload). Listens ONLY to the
## EventBus contract (plus SceneManager scene swaps and a global button
## hook); gameplay systems never play sounds directly.
##
## Everything it plays is mapped in data/audio/audio_map.json (agent-
## editable): music keys, per-event SFX, the shared random taunt pool, and
## the retro scene-transition stinger pool. Supplying the final shop theme
## later = filling in the "shop" music path — no code.
##
## Hit-feel (spec Section 11 priority): enemy/player/blob hits each have a
## DISTINCT sound, throttled + pitch-jittered so hordes read as punchy, not
## as white noise.

const SFX_POOL_SIZE := 16
const SFX_MIN_INTERVAL := 0.018
const MUSIC_FADE_SEC := 0.7
const TRANSITION_MIN_GAP := 1.0

var _map: Dictionary = {}
var _volumes: Dictionary = {}
var _stream_cache: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _current_music_key := ""
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _sfx_last_played: Dictionary = {}
var _taunt_player: AudioStreamPlayer
var _transition_player: AudioStreamPlayer
var _taunt_paths: PackedStringArray = []
var _transition_streams: Array = []
var _run_active := false
var _taunt_timer := 10.0
var _last_transition_at := -100.0
var _rng := RandomNumberGenerator.new()
var _hub_tab := "play"


func _ready() -> void:
	# Music must keep playing through tree pause (death freeze, menus).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	var parsed: Variant = JsonData.load_json("res://data/audio/audio_map.json")
	_map = parsed if parsed is Dictionary else {}
	_volumes = _map.get("volumes_db", {})

	_music_a = _make_player(float(_volumes.get("music", -8.0)))
	_music_b = _make_player(float(_volumes.get("music", -8.0)))
	_music_active = _music_a
	for i in range(SFX_POOL_SIZE):
		_sfx_pool.append(_make_player(float(_volumes.get("sfx", -4.0))))
	_taunt_player = _make_player(float(_volumes.get("taunts", -10.0)))
	_transition_player = _make_player(float(_volumes.get("transitions", -9.0)))
	EventBus.settings_changed.connect(_on_settings_changed)

	_scan_pools()
	_connect_events()
	# Music starts after the boot splash (boot calls play_music("hub")).


func _process(delta: float) -> void:
	if not _run_active or get_tree().paused:
		return
	_taunt_timer -= delta
	if _taunt_timer <= 0.0:
		_play_random_taunt()
		var interval: Array = _map.get("taunt_interval_sec", [8, 16])
		_taunt_timer = _rng.randf_range(float(interval[0]), float(interval[1]))


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Crossfades to the mapped music track. Missing/empty paths are ignored
## (e.g. the shop theme until it's supplied) — current music continues.
func play_music(key: String) -> void:
	if key == _current_music_key:
		return
	var path := str(_map.get("music", {}).get(key, ""))
	var stream := _stream(path)
	if stream == null:
		return
	_current_music_key = key
	# Music must loop (MP3/OGG streams don't by default).
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	var fade_out := _music_active
	var fade_in: AudioStreamPlayer = _music_b if _music_active == _music_a else _music_a
	_music_active = fade_in
	fade_in.stream = stream
	fade_in.volume_db = -40.0
	fade_in.play()
	var target := float(_volumes.get("music", -8.0)) + GameSettings.to_db_offset(GameSettings.music_volume())
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(fade_in, "volume_db", target, MUSIC_FADE_SEC)
	if fade_out.playing:
		tween.tween_property(fade_out, "volume_db", -40.0, MUSIC_FADE_SEC)
		tween.chain().tween_callback(fade_out.stop)


func current_music_key() -> String:
	return _current_music_key


## Plays a mapped SFX with throttling + slight pitch jitter (hit-feel:
## rapid repeats stay punchy instead of phasing into noise).
func play_sfx(key: String, pitch_jitter := 0.08) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_sfx_last_played.get(key, -10.0)) < SFX_MIN_INTERVAL:
		return
	var stream := _stream(str(_map.get("sfx", {}).get(key, "")))
	if stream == null:
		return
	_sfx_last_played[key] = now
	var player := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	player.stream = stream
	player.volume_db = float(_volumes.get("sfx", -4.0)) + GameSettings.to_db_offset(GameSettings.sfx_volume())
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	player.play()


## Hub tab transaction hook (called by hub.gd). The retro shop theme slots
## in here once the track exists in the audio map.
func on_hub_tab_changed(tab_id: String) -> void:
	play_sfx("ui_tap")
	if tab_id == "shop" and str(_map.get("music", {}).get("shop", "")) != "":
		play_music("shop")
	elif _hub_tab == "shop" and _current_music_key == "shop":
		play_music("hub")
	_hub_tab = tab_id


# ---------------------------------------------------------------------------

func _connect_events() -> void:
	# Music state.
	EventBus.run_started.connect(func(_level: int) -> void:
		_run_active = true
		_taunt_timer = _rng.randf_range(3.0, 7.0)
		play_music("gameplay"))
	EventBus.run_ended.connect(func(_summary: Dictionary) -> void:
		_run_active = false
		play_music("hub"))
	EventBus.player_died.connect(func() -> void: play_music("death"))
	EventBus.player_revived.connect(func() -> void: play_music("gameplay"))

	# Hit-feel: three DISTINCT identities.
	EventBus.enemy_hit.connect(func(_id: String, _damage: float, _pos: Vector3) -> void: play_sfx("enemy_hit", 0.12))
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_hit.connect(func(_damage: float) -> void: play_sfx("player_hit"))
	EventBus.blob_follower_hit.connect(func() -> void: play_sfx("blob_hit", 0.15))
	EventBus.shield_broken.connect(func() -> void: play_sfx("shield_break"))

	# Pickups / progression.
	EventBus.blob_collected.connect(func(_amount: int) -> void: play_sfx("eat", 0.2))
	EventBus.powerup_picked_up.connect(func(_id: String) -> void: play_sfx("ui_confirm", 0.1))
	EventBus.player_leveled_up.connect(func(_level: int) -> void: play_sfx("level_up"))
	EventBus.card_chosen.connect(func(_id: String) -> void: play_sfx("ui_confirm"))

	# Reveals + purchases.
	EventBus.allan_unlocked.connect(func(_id: String) -> void: play_sfx("unlock_sting"))
	EventBus.card_unlocked.connect(func(_id: String) -> void: play_sfx("unlock_sting"))
	EventBus.purchase_completed.connect(func(_id: String) -> void: play_sfx("ui_confirm"))
	EventBus.purchase_failed.connect(func(_id: String, _reason: String) -> void: play_sfx("ui_error"))

	# Boss.
	EventBus.boss_incoming.connect(func(_level: int) -> void: play_sfx("ui_error", 0.0))
	EventBus.boss_spawned.connect(func(_id: String) -> void: _play_random_taunt())

	# Scene-change retro stingers.
	SceneManager.scene_unloaded.connect(_on_scene_change)

	# Global button tap (covers static + dynamically created buttons).
	get_tree().node_added.connect(_on_node_added)


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key == "music_volume" and _music_active != null and _music_active.playing:
		_music_active.volume_db = float(_volumes.get("music", -8.0)) + GameSettings.to_db_offset(GameSettings.music_volume())


func _on_enemy_killed(_id: String, _pos: Vector3) -> void:
	play_sfx("enemy_die", 0.12)
	if _rng.randf() < float(_map.get("taunt_on_kill_chance", 0.06)):
		_play_random_taunt()


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(func() -> void: play_sfx("ui_tap"))


func _on_scene_change() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_transition_at < TRANSITION_MIN_GAP or _transition_streams.is_empty():
		return
	_last_transition_at = now
	_transition_player.stream = _transition_streams[_rng.randi_range(0, _transition_streams.size() - 1)]
	_transition_player.volume_db = float(_volumes.get("transitions", -9.0)) + GameSettings.to_db_offset(GameSettings.sfx_volume())
	_transition_player.play()


func _play_random_taunt() -> void:
	if _taunt_paths.is_empty() or _taunt_player.playing:
		return
	var stream := _stream(_taunt_paths[_rng.randi_range(0, _taunt_paths.size() - 1)])
	if stream == null:
		return
	_taunt_player.stream = stream
	_taunt_player.volume_db = float(_volumes.get("taunts", -10.0)) + GameSettings.to_db_offset(GameSettings.sfx_volume())
	_taunt_player.play()


func _scan_pools() -> void:
	_taunt_paths = JsonData.list_files(str(_map.get("taunts_dir", "")), "ogg")
	var max_sec := float(_map.get("transition_max_sec", 6.0))
	for path in JsonData.list_files(str(_map.get("transitions_dir", "")), "ogg"):
		var stream := _stream(path)
		if stream != null and stream.get_length() <= max_sec:
			_transition_streams.append(stream)


func _make_player(volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = volume_db
	add_child(player)
	return player


func _stream(path: String) -> AudioStream:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if not _stream_cache.has(path):
		_stream_cache[path] = load(path)
	return _stream_cache[path]
