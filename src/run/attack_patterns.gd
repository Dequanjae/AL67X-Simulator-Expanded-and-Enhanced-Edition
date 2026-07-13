class_name AttackPatterns
extends RefCounted
## Composable boss attack-pattern MODULES (spec Section 3). Bosses are DATA
## (data/bosses/*.json) that reference these modules by type + params;
## later-level bosses remix modules from earlier bosses (BossCatalog).
##
## Each pattern dict carries its own runtime state (keys prefixed "_").
## Modules act on the world exclusively through HordeSystem's boss API:
##   boss_position(), player_position(), spawn_enemy_projectile(),
##   spawn_minion_near(), boss_dash(), set_boss_telegraph().
##
## ADDING A NEW MODULE REQUIRES CODE HERE (a match branch + a func) — this
## is a flagged exception to the data-only content pipeline (Section 13).


static func tick(pattern: Dictionary, horde: HordeSystem, delta: float) -> void:
	match str(pattern.get("type", "")):
		"radial_burst":
			_timed(pattern, delta, func() -> void: _radial_burst(pattern, horde))
		"aimed_volley":
			_timed(pattern, delta, func() -> void: _aimed_volley(pattern, horde))
		"summon_minions":
			_timed(pattern, delta, func() -> void: _summon_minions(pattern, horde))
		"charge_dash":
			_charge_dash(pattern, horde, delta)
		_:
			push_warning("AttackPatterns: unknown pattern type '%s'" % pattern.get("type", ""))


## Shared interval scheduler: fires `action` every pattern.interval seconds.
static func _timed(pattern: Dictionary, delta: float, action: Callable) -> void:
	var timer := float(pattern.get("_timer", float(pattern.get("interval", 3.0)) * 0.5))
	timer -= delta
	if timer <= 0.0:
		timer = float(pattern.get("interval", 3.0))
		action.call()
	pattern["_timer"] = timer


static func _radial_burst(pattern: Dictionary, horde: HordeSystem) -> void:
	var origin := horde.boss_position()
	var count := int(pattern.get("count", 10))
	var speed := float(pattern.get("proj_speed", 5.5))
	var damage := float(pattern.get("damage", 8))
	var phase := float(pattern.get("_phase_angle", 0.0))
	for i in range(count):
		var angle := phase + TAU * float(i) / float(count)
		horde.spawn_enemy_projectile(origin, Vector2.from_angle(angle), speed, damage)
	# Rotate the ring each burst so stand-still isn't safe.
	pattern["_phase_angle"] = phase + TAU / float(maxi(count * 2, 1))


static func _aimed_volley(pattern: Dictionary, horde: HordeSystem) -> void:
	var origin := horde.boss_position()
	var target := horde.player_position()
	var base_dir := (target - origin).normalized()
	var count := int(pattern.get("count", 3))
	var spread := deg_to_rad(float(pattern.get("spread_deg", 16)))
	var speed := float(pattern.get("proj_speed", 8.5))
	var damage := float(pattern.get("damage", 6))
	for i in range(count):
		var offset := 0.0 if count <= 1 else spread * (float(i) / float(count - 1) - 0.5)
		horde.spawn_enemy_projectile(origin, base_dir.rotated(offset), speed, damage)


static func _summon_minions(pattern: Dictionary, horde: HordeSystem) -> void:
	var origin := horde.boss_position()
	for i in range(int(pattern.get("count", 4))):
		horde.spawn_minion_near(origin)


## Two-phase: telegraph (boss slows + flashes) → dash at the player.
static func _charge_dash(pattern: Dictionary, horde: HordeSystem, delta: float) -> void:
	var phase := str(pattern.get("_phase", "cooldown"))
	var timer := float(pattern.get("_timer", float(pattern.get("interval", 4.0)) * 0.5))
	timer -= delta
	match phase:
		"cooldown":
			if timer <= 0.0:
				pattern["_phase"] = "windup"
				timer = float(pattern.get("windup_sec", 0.8))
				horde.set_boss_telegraph(true)
		"windup":
			if timer <= 0.0:
				pattern["_phase"] = "cooldown"
				timer = float(pattern.get("interval", 4.0))
				horde.set_boss_telegraph(false)
				var dir := (horde.player_position() - horde.boss_position()).normalized()
				horde.boss_dash(dir, float(pattern.get("dash_speed", 11.0)), float(pattern.get("dash_sec", 0.6)))
	pattern["_timer"] = timer
