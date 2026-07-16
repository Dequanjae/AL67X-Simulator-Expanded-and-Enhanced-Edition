extends Node3D

const ZOOM_MIN := 9.0
const ZOOM_MAX := 26.0

var _level := 1
var _theme: Dictionary = {}
var _config: Dictionary = {}
var _stats: PlayerStats
var _run_blobs := 0
var _ad_continue_used := false
var _start_msec := 0
var _survival_remaining := 60.0
var _boss_phase := false
var _boss_warning_timer := -1.0
var _xp_by_enemy: Dictionary = {}
var _blob_xp := 0.25
var _ended := false
var _powerup_defs: Array = []
var _timed_boosts: Array = []

@onready var _player: RunPlayer = $Player
@onready var _camera_rig: RunCamera = $CameraRig
@onready var _camera: Camera3D = $CameraRig/Camera
@onready var _level_root: LevelBuilder = $LevelRoot
@onready var _pickups: PickupManager = $Pickups
@onready var _horde: HordeSystem = $Horde
@onready var _swarm: BlobSwarm = $Swarm
@onready var _damage_numbers: DamageNumbers = $DamageNumbers
@onready var _splats: SplatSystem = $Splats
@onready var _header_label: Label = $HUD/TopMargin/TopBox/VBox/HeaderLabel
@onready var _timer_label: Label = $HUD/TopMargin/TopBox/VBox/TimerLabel
@onready var _blobs_label: Label = $HUD/TopMargin/TopBox/VBox/BlobsLabel
@onready var _hearts_box: HBoxContainer = $HUD/TopMargin/TopBox/VBox/HeartsBox
@onready var _xp_bar: ProgressBar = $HUD/TopMargin/TopBox/VBox/XPBar
@onready var _level_label: Label = $HUD/TopMargin/TopBox/VBox/LevelLabel
@onready var _boss_warn_label: Label = $HUD/BossWarnLabel
@onready var _boss_bar_margin: MarginContainer = $HUD/BossBarMargin
@onready var _boss_name_label: Label = $HUD/BossBarMargin/BossBarBox/BossNameLabel
@onready var _boss_bar: ProgressBar = $HUD/BossBarMargin/BossBarBox/BossBar
@onready var _level_up_menu: PanelContainer = $HUD/LevelUpMenu
@onready var _dev_margin: MarginContainer = $HUD/DevMargin
@onready var _boss_button: Button = $HUD/DevMargin/DevBox/BossButton
@onready var _die_button: Button = $HUD/DevMargin/DevBox/DieButton
@onready var _spotlight: ColorRect = $HUD/DeathSpotlight
@onready var _death_panel: PanelContainer = $HUD/DeathPanel
@onready var _death_portrait: TextureRect = $HUD/DeathPanel/DeathBox/CryPortrait
@onready var _ad_button: Button = $HUD/DeathPanel/DeathBox/AdContinueButton
@onready var _ascend_button: Button = $HUD/DeathPanel/DeathBox/AscendButton
@onready var _ascend_overlay: Control = $HUD/AscendOverlay
@onready var _ascend_title: Label = $HUD/AscendOverlay/Center/Box/TitleLabel
@onready var _ascend_blobs_label: Label = $HUD/AscendOverlay/Center/Box/BlobCountLabel
@onready var _ascend_total_label: Label = $HUD/AscendOverlay/Center/Box/TotalLabel


func _ready() -> void:
	print("--- RUN _ready: start ---")
	_level = int(SaveService.get_value("progress.highest_level_unlocked", 1))
	_start_msec = Time.get_ticks_msec()
	print("RUN: level=%d" % _level)
	_config = RunBalance.load_config()
	_stats = PlayerStats.from_config(_config)
	CardUpgrades.apply_loadout(_stats, CardUpgrades.load_config())
	_blob_xp = float(_config.get("player_xp", {}).get("blob_xp_value", 0.25))
	_xp_by_enemy = EnemyCatalog.xp_map(EnemyCatalog.load_all())
	_survival_remaining = RunBalance.survival_seconds(_level, _config)
	var powerups_data: Variant = JsonData.load_json("res://data/powerups/powerups.json")
	_powerup_defs = powerups_data.get("effects", []) if powerups_data is Dictionary else []
	print("RUN: config+stats done")

	var themes := _load_themes()
	_theme = themes[(_level - 1) % themes.size()] if not themes.is_empty() else {}
	print("RUN: themes loaded, theme=%s" % _theme.get("id", "?"))
	var layout: Dictionary
	if ClassDB.class_exists("LevelGeneratorRs"):
		layout = ClassDB.instantiate("LevelGeneratorRs").generate(_level, _theme)
	else:
		push_error("LevelGeneratorRs not available")
		layout = {"ok": false}
	print("RUN: layout generated, arena=%s props=%d ok=%s" % [str(layout.get("arena_size", "?")), layout.get("props", []).size(), layout.get("ok", false)])
	_level_root.build(layout, _theme)
	print("RUN: level built")
	_player.position = layout["player_spawn"]
	_player.camera = _camera
	_player.stats = _stats
	_player.set_shield_visible(_stats.shield > 0)
	_pickups.configure(layout["walkable_points"], _theme.get("spawns", {}), _player)

	var equipped := str(SaveService.get_value("allans.equipped", "player1"))
	_swarm.setup(_player, equipped)
	_horde.setup(_player, _swarm, _stats, layout, _level, _config)
	_horde.boss_killed.connect(_on_boss_killed)
	_level_up_menu.stats = _stats

	print("RUN: camera setup...")
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 16.0
	_camera.look_at_from_position(Vector3(10.0, 10.0, 10.0), Vector3.ZERO)
	_camera_rig.target = _player
	_camera_rig.snap_to_target()
	EventBus.player_hit.connect(func(_damage: float) -> void: _camera_rig.shake(0.9))
	EventBus.shield_broken.connect(func() -> void: _camera_rig.shake(0.6))
	EventBus.enemy_killed.connect(func(_id: String, _pos: Vector3) -> void: _camera_rig.shake(0.15))
	EventBus.boss_spawned.connect(_on_boss_spawned_camera)

	print("RUN: HUD visibility...")
	_header_label.text = "Day %d" % _level
	_header_label.tooltip_text = str(_theme.get("name", "The Shop"))
	_death_panel.visible = false
	_spotlight.visible = false
	_ascend_overlay.visible = false
	_boss_warn_label.visible = false
	_dev_margin.visible = OS.is_debug_build()
	_boss_button.pressed.connect(_on_dev_boss_win)
	_die_button.pressed.connect(func() -> void:
		_stats.shield = 0
		_stats.hearts = 1
		_apply_player_damage(1.0))
	_ad_button.pressed.connect(_on_ad_continue)
	_ascend_button.pressed.connect(func() -> void: _end_run(false, "ascend"))
	EventBus.blob_collected.connect(_on_blob_collected)
	EventBus.blob_lost.connect(_on_blob_lost)
	EventBus.player_hit.connect(_apply_player_damage)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.powerup_picked_up.connect(_on_powerup_picked_up)
	EventBus.card_chosen.connect(func(_id: String) -> void:
		_player.set_shield_visible(_stats.shield > 0)
		_refresh_hud())

	EventBus.run_started.emit(_level)
	_refresh_hud()
	print("--- RUN _ready: done ---")


func _process(delta: float) -> void:
	var zoom := InputService.consume_zoom_delta()
	if zoom != 0.0:
		_camera.size = clampf(_camera.size + zoom, ZOOM_MIN, ZOOM_MAX)
	if _ended:
		return
	_tick_timed_boosts(delta)
	if not _boss_phase:
		_survival_remaining -= delta
		if _survival_remaining <= 0.0:
			_start_boss_warning()
	elif _boss_warning_timer > 0.0:
		_boss_warning_timer -= delta
		if _boss_warning_timer <= 0.0:
			_boss_warn_label.visible = false
			_horde.spawn_boss()
	_refresh_hud()


func _start_boss_warning() -> void:
	_boss_phase = true
	_survival_remaining = 0.0
	_boss_warning_timer = float(_config.get("boss", {}).get("warning_seconds", 2.5))
	_boss_warn_label.visible = true
	EventBus.boss_incoming.emit(_level)


func _on_boss_spawned_camera(_boss_id: String) -> void:
	var boss_pos := _horde.boss_position()
	_camera_rig.intro_pan(Vector3(boss_pos.x, 0, boss_pos.y), 0.9)
	_camera_rig.shake(1.1)


func _on_boss_killed(boss_id: String) -> void:
	EventBus.boss_defeated.emit(boss_id, _level)
	_unlock_next_level()
	_end_run(true, "boss_defeated")


func _unlock_next_level() -> void:
	var next_level := _level + 1
	SaveService.set_value("progress.highest_level_unlocked", next_level)
	EventBus.level_unlocked.emit(next_level)


func _on_dev_boss_win() -> void:
	EventBus.boss_incoming.emit(_level)
	EventBus.boss_spawned.emit("dev_boss")
	EventBus.boss_defeated.emit("dev_boss", _level)
	_unlock_next_level()
	_end_run(true, "boss_defeated")


func _on_blob_collected(amount: int) -> void:
	_run_blobs += amount
	_grant_xp(_blob_xp * float(amount))
	_refresh_hud()


func _on_blob_lost(amount: int) -> void:
	_run_blobs = maxi(0, _run_blobs - amount)
	_refresh_hud()


func _on_enemy_killed(enemy_id: String, _world_pos: Vector3) -> void:
	_grant_xp(float(_xp_by_enemy.get(enemy_id, 1.0)))


func _grant_xp(amount: float) -> void:
	var level_ups := _stats.add_xp(amount)
	for i in range(level_ups):
		EventBus.player_leveled_up.emit(_stats.level)


func debug_grant_xp(amount: float) -> void:
	_grant_xp(amount)


func _on_powerup_picked_up(effect_id: String) -> void:
	for def in _powerup_defs:
		if str(def.get("id", "")) != effect_id:
			continue
		_damage_numbers.announce(_player.global_position, str(def.get("popup", effect_id.to_upper())))
		match str(def.get("type", "")):
			"heart_restore":
				_stats.hearts = mini(_stats.hearts + int(def.get("value", 1)), _stats.max_hearts)
			"damage_boost":
				_stats.damage_mult *= float(def.get("multiplier", 1.5))
				_timed_boosts.append({"type": "damage", "multiplier": float(def.get("multiplier", 1.5)), "remaining": float(def.get("duration_sec", 10))})
			"speed_boost":
				_stats.speed_mult *= float(def.get("multiplier", 1.3))
				_timed_boosts.append({"type": "speed", "multiplier": float(def.get("multiplier", 1.3)), "remaining": float(def.get("duration_sec", 8))})
			"succ":
				var duration := float(def.get("duration_sec", 10))
				_pickups.start_vacuum(duration)
				_player.play_succ(duration)
			"invincibility":
				_horde.grant_player_iframes(float(def.get("duration_sec", 5)))
			"freeze":
				_horde.freeze_enemies(float(def.get("duration_sec", 4)))
			"goon_nova":
				_horde.fire_nova(int(def.get("count", 28)))
				_camera_rig.shake(0.8)
			_:
				push_warning("RunController: unknown powerup effect '%s'" % def.get("type", ""))
		_refresh_hud()
		return


func _tick_timed_boosts(delta: float) -> void:
	var i := 0
	while i < _timed_boosts.size():
		_timed_boosts[i]["remaining"] -= delta
		if _timed_boosts[i]["remaining"] <= 0.0:
			var boost: Dictionary = _timed_boosts[i]
			if str(boost["type"]) == "damage":
				_stats.damage_mult /= float(boost["multiplier"])
			else:
				_stats.speed_mult /= float(boost["multiplier"])
			_timed_boosts.remove_at(i)
		else:
			i += 1


func _apply_player_damage(_damage: float) -> void:
	if _ended or _stats.hearts <= 0:
		return
	if _stats.shield > 0:
		_stats.shield -= 1
		_player.set_shield_visible(_stats.shield > 0)
		EventBus.shield_broken.emit()
		_refresh_hud()
		return
	_stats.hearts -= 1
	_player.flash_damage()
	_refresh_hud()
	if _stats.hearts <= 0:
		_on_player_died()


func _on_player_died() -> void:
	EventBus.player_died.emit()
	_player.set_dead(true)
	_show_death_spotlight()
	_show_death_panel()
	get_tree().paused = true
	_refresh_hud()


func _show_death_spotlight() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_pos := _camera.unproject_position(_player.global_position + Vector3(0, 1.0, 0))
	var material := _spotlight.material as ShaderMaterial
	material.set_shader_parameter("center", screen_pos / viewport_size)
	material.set_shader_parameter("aspect", viewport_size.x / viewport_size.y)
	material.set_shader_parameter("darkness", 0.0)
	_spotlight.visible = true
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(
		func(v: float) -> void: material.set_shader_parameter("darkness", v),
		0.0, 0.94, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


func _show_death_panel() -> void:
	var equipped := str(SaveService.get_value("allans.equipped", "player1"))
	var cry_frames: Array = AllanSprites.state_regions().get("cry", [])
	if not cry_frames.is_empty():
		var atlas := AtlasTexture.new()
		atlas.atlas = AllanSprites.sheet_texture(equipped)
		atlas.region = cry_frames[0]
		_death_portrait.texture = atlas
	_death_panel.visible = true
	_death_panel.pivot_offset = _death_panel.size * 0.5
	_death_panel.scale = Vector2(0.1, 0.1)
	_death_panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(_death_panel, "modulate", Color.WHITE, 0.5).set_delay(0.55)
	tween.tween_property(_death_panel, "scale", Vector2(1.15, 1.15), 0.55).set_delay(0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(_death_panel, "scale", Vector2.ONE, 0.15)


func _on_ad_continue() -> void:
	_ad_continue_used = true
	_death_panel.visible = false
	_spotlight.visible = false
	get_tree().paused = false
	_player.set_dead(false)
	_stats.hearts = _stats.max_hearts
	_horde.grant_player_iframes(2.0)
	EventBus.player_revived.emit()
	_refresh_hud()


func _end_run(victory: bool, reason: String) -> void:
	if _ended:
		return
	_ended = true
	get_tree().paused = false
	EconomyService.add_blobs(_run_blobs)
	SaveService.save_now()
	EventBus.run_ended.emit({
		"level": _level,
		"victory": victory,
		"blobs_banked": _run_blobs,
		"duration_sec": float(Time.get_ticks_msec() - _start_msec) / 1000.0,
		"reason": reason,
	})
	await _play_ascend_countup(victory)
	SceneManager.change_scene("res://scenes/hub/hub.tscn", {"pattern": "circle", "speed": 2.5})


func _play_ascend_countup(victory: bool) -> void:
	_death_panel.visible = false
	_ascend_title.text = ("DAY %d COMPLETE!" % _level) if victory else "ASCENDING TO HEAVEN..."
	var total_after := EconomyService.get_blobs()
	var total_before := total_after - _run_blobs
	_ascend_blobs_label.text = "+0 Blobs"
	_ascend_total_label.text = "Total: %d" % total_before
	_ascend_overlay.visible = true
	_ascend_overlay.modulate = Color(1, 1, 1, 0)
	var box: Control = _ascend_overlay.get_node("Center/Box")
	var update_count := func(v: float) -> void:
		var counted := int(v)
		_ascend_blobs_label.text = "+%d Blobs" % counted
		_ascend_total_label.text = "Total: %d" % (total_before + counted)
		box.scale = Vector2.ONE * (1.0 + 0.06 * sin(v * 2.2))
	var finish_count := func() -> void:
		_ascend_blobs_label.text = "+%d Blobs" % _run_blobs
		_ascend_total_label.text = "Total: %d" % total_after
		box.scale = Vector2.ONE
	var duration := clampf(0.3 + float(_run_blobs) * 0.012, 0.5, 1.6)
	var tween := create_tween()
	tween.tween_property(_ascend_overlay, "modulate", Color.WHITE, 0.25)
	tween.tween_method(update_count, 0.0, float(_run_blobs), duration)
	tween.tween_callback(finish_count)
	tween.tween_interval(0.5)
	await tween.finished


func _refresh_hud() -> void:
	if _boss_phase:
		_timer_label.text = "BOSS!" if _boss_warning_timer <= 0.0 else "INCOMING..."
	else:
		var total := int(maxf(0.0, _survival_remaining))
		@warning_ignore("integer_division")
		_timer_label.text = "%d:%02d" % [total / 60, total % 60]
	_blobs_label.text = "%d" % _run_blobs
	_refresh_hearts()
	_xp_bar.max_value = _stats.xp_threshold()
	_xp_bar.value = _stats.xp
	_level_label.text = "Lv %d" % _stats.level
	_ad_button.disabled = _ad_continue_used
	_ad_button.text = "Watch ad to continue" if not _ad_continue_used else "Ad continue used"
	var boss_active := _horde.has_boss()
	_boss_bar_margin.visible = boss_active
	if boss_active:
		_boss_name_label.text = _horde.boss_name().to_upper().replace("BOSS_", "").replace("_", " ")
		_boss_bar.value = _horde.boss_hp_ratio()


func _refresh_hearts() -> void:
	var wanted := _stats.max_hearts + _stats.shield
	var rebuild := _hearts_box.get_child_count() != wanted
	if rebuild:
		for child in _hearts_box.get_children():
			_hearts_box.remove_child(child)
			child.queue_free()
		for i in range(wanted):
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(34, 34)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_hearts_box.add_child(icon)
	for i in range(_hearts_box.get_child_count()):
		var icon := _hearts_box.get_child(i) as TextureRect
		if i < _stats.max_hearts:
			icon.texture = IconFactory.heart(i < _stats.hearts)
		else:
			icon.texture = IconFactory.shield()


static func _load_themes() -> Array:
	var themes: Array = []
	for path in JsonData.list_files("res://data/levels", "json"):
		var t: Variant = JsonData.load_json(path)
		if t is Dictionary and t.has("generation"):
			themes.append(t)
	themes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(a.get("order", 9999))
		var ob := int(b.get("order", 9999))
		if oa != ob:
			return oa < ob
		return str(a.get("id", "")) < str(b.get("id", "")))
	return themes
