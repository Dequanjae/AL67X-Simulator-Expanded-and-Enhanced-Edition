extends Node3D
## RunController — orchestrates a run:
##  worldgen build → survival timer (curve-driven) → horde combat → boss →
##  death/ascend or victory → animated blob count-up banking → hub.
##
## Health is HIT-BASED: hearts (3 base). Aura Shield charges absorb hits
## first and break permanently (no regen). Powerups apply here (heart
## restore + timed boosts). Camera zoom: scroll wheel / pinch.
##
## Contract responsibilities (Section 10): banks blobs via EconomyService
## and writes level unlocks BEFORE emitting run_ended. In-run state is
## never persisted.

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
var _boss_warning_active := false
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
@onready var _level_up: LevelUpController = $LevelUpController
@onready var _hud: RunHud = $HUD
@onready var _spotlight: ColorRect = $HUD/DeathSpotlight


func _ready() -> void:
	_level = int(SaveService.get_value("progress.highest_level_unlocked", 1))
	_start_msec = Time.get_ticks_msec()
	_config = RunBalance.load_config()
	_stats = PlayerStats.from_config(_config)
	CardUpgrades.apply_loadout(_stats, CardUpgrades.load_config())
	_blob_xp = float(_config.get("player_xp", {}).get("blob_xp_value", 0.25))
	_xp_by_enemy = EnemyCatalog.xp_map(EnemyCatalog.load_all())
	_survival_remaining = RunBalance.survival_seconds(_level, _config)
	var powerups_data: Variant = JsonData.load_json("res://data/powerups/powerups.json")
	_powerup_defs = powerups_data.get("effects", []) if powerups_data is Dictionary else []

	# --- Worldgen ----------------------------------------------------------
	var themes := LevelGenerator.load_themes()
	_theme = LevelGenerator.theme_for_level(_level, themes)
	var layout := LevelGenerator.generate(_level, _theme)
	_level_root.build(layout, _theme)
	_player.position = layout["player_spawn"]
	_player.camera = _camera
	_player.stats = _stats
	_player.set_shield_visible(_stats.shield > 0)
	_pickups.configure(layout["walkable_points"], _theme.get("spawns", {}), _player)

	# --- Combat systems ----------------------------------------------------
	var equipped := str(SaveService.get_value("allans.equipped", "player1"))
	_swarm.setup(_player, equipped)
	_horde.setup(_player, _swarm, _stats, layout, _level, _config)
	_horde.boss_killed.connect(_on_boss_killed)
	_level_up.stats = _stats

	# --- Camera ---------------------------------------------------------------
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 16.0
	_camera.look_at_from_position(Vector3(10.0, 10.0, 10.0), Vector3.ZERO)
	_camera_rig.target = _player
	_camera_rig.snap_to_target()
	EventBus.player_hit.connect(func(_damage: float) -> void: _camera_rig.shake(0.9))
	EventBus.shield_broken.connect(func() -> void: _camera_rig.shake(0.6))
	EventBus.enemy_killed.connect(func(_id: String, _pos: Vector3) -> void: _camera_rig.shake(0.15))
	EventBus.boss_spawned.connect(_on_boss_spawned_camera)

	# --- HUD signals ----------------------------------------------------------
	_spotlight.visible = false
	_hud.pause_toggled.connect(func(paused: bool) -> void: get_tree().paused = paused)
	_hud.ad_continue_pressed.connect(_on_ad_continue)
	_hud.ascend_pressed.connect(func() -> void: _end_run(false, "ascend"))
	_hud.quit_to_hub_pressed.connect(func() -> void: _end_run(false, "quit"))
	_hud.dev_boss_win_pressed.connect(_on_dev_boss_win)
	_hud.dev_die_pressed.connect(func() -> void:
		_stats.shield = 0
		_stats.hearts = 1
		_apply_player_damage(1.0))

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
			_boss_warning_active = false
			_horde.spawn_boss()
	_refresh_hud()


# ---------------------------------------------------------------------------
# Survival timer → boss phase
# ---------------------------------------------------------------------------

func _start_boss_warning() -> void:
	_boss_phase = true
	_survival_remaining = 0.0
	_boss_warning_timer = float(_config.get("boss", {}).get("warning_seconds", 2.5))
	_boss_warning_active = true
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


# ---------------------------------------------------------------------------
# Blobs + XP + powerups
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Hearts / shield / death / revive
# ---------------------------------------------------------------------------

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
	_hud.show_death_panel(_ad_continue_used)
	get_tree().paused = true


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


func _on_ad_continue() -> void:
	_ad_continue_used = true
	_spotlight.visible = false
	get_tree().paused = false
	_player.set_dead(false)
	_stats.hearts = _stats.max_hearts
	_horde.grant_player_iframes(2.0)
	EventBus.player_revived.emit()
	_hud.hide_death_panel()
	_hud.set_hearts(_stats.hearts, _stats.max_hearts)


# ---------------------------------------------------------------------------
# Run end + banking
# ---------------------------------------------------------------------------

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
	var total_after := EconomyService.get_blobs()
	var total_before := total_after - _run_blobs
	var title := "VICTORY!" if victory else "ASCENDING..."
	_hud.show_ascend(title, _run_blobs, total_after)
	var duration := clampf(0.3 + float(_run_blobs) * 0.012, 0.5, 1.6)
	await get_tree().create_timer(0.25 + duration + 0.5).timeout


# ---------------------------------------------------------------------------

func _refresh_hud() -> void:
	var timer_text: String
	if _boss_phase:
		timer_text = "BOSS!" if _boss_warning_timer <= 0.0 else "INCOMING..."
	else:
		var total := int(maxf(0.0, _survival_remaining))
		@warning_ignore("integer_division")
		timer_text = "%d:%02d" % [total / 60, total % 60]

	var boss_active := _horde.has_boss()
	_hud.set_hearts(_stats.hearts, _stats.max_hearts)
	_hud.set_timer(timer_text)
	_hud.set_blobs(_run_blobs)
	_hud.set_xp(_stats.level, _stats.xp, _stats.xp_threshold())
	_hud.show_boss_warning(_boss_warning_active)
	_hud.show_boss_bar(boss_active)
	if boss_active:
		_hud.set_boss_health(
			_horde.boss_name().to_upper().replace("BOSS_", "").replace("_", " "),
			_horde.boss_hp_ratio())
