class_name PlayerStats
extends RefCounted
## In-run player stats. Created fresh each run (in-run progress never
## persists — spec Section 8/9). Card effects mutate these; combat systems
## read them every frame. Base values come from data/balance/run_curves.json.

## HIT-BASED health: hearts, not HP — each enemy hit costs 1 heart
## (i-frames apply). Shield charges absorb a hit before hearts do; shields
## are ONE-TIME (no regen — pull the Aura Shield card again to re-shield).
var max_hearts := 3
var hearts := 3
var shield := 0
var speed_mult := 1.0
var damage := 10.0
var damage_mult := 1.0
var fire_interval := 0.9
var attack_range := 12.0
var projectile_count := 1
var projectile_scale := 1.0
var projectile_speed := 14.0
## Weapon style extensions (cards): wall bounces, enemy pierces, orbiting
## goons, periodic radial nova (0 = off).
var projectile_bounces := 0
var projectile_pierce := 0
var orbital_count := 0
var nova_interval := 0.0
var xp := 0.0
var level := 0
## Card-driven pickup economy knobs.
var shawarma_max_add := 0
var shawarma_xp_mult := 1.0
var powerup_rate_mult := 1.0
var powerup_count_add := 0

var _config: Dictionary = {}


static func from_config(config: Dictionary) -> PlayerStats:
	var stats := PlayerStats.new()
	stats._config = config
	var base: Dictionary = config.get("player_base", {})
	stats.max_hearts = int(base.get("max_hearts", 3))
	stats.hearts = stats.max_hearts
	stats.damage = float(base.get("damage", 10))
	stats.fire_interval = float(base.get("fire_interval_sec", 0.9))
	stats.attack_range = float(base.get("attack_range", 12))
	stats.projectile_speed = float(base.get("projectile_speed", 14))
	stats.projectile_count = int(base.get("projectile_count", 1))
	return stats


func xp_threshold() -> float:
	return RunBalance.xp_threshold(level, _config)


## Adds XP; returns how many level-ups this crossed (can be > 1).
func add_xp(amount: float) -> int:
	xp += amount
	var level_ups := 0
	while xp >= xp_threshold():
		xp -= xp_threshold()
		level += 1
		level_ups += 1
	return level_ups


func effective_damage() -> float:
	return damage * damage_mult


## Applies a card effect dict ({"type": ..., "value": ...}).
## New effect types REQUIRE CODE here (flagged exception to the
## data-only content pipeline — documented in the card data readme).
func apply_effect(effect: Dictionary) -> void:
	var value := float(effect.get("value", 1.0))
	match str(effect.get("type", "")):
		"damage_mult":
			damage_mult *= value
		"damage_mult_add":
			damage_mult += value
		"fire_rate_mult":
			fire_interval /= maxf(0.01, value)
		"speed_mult":
			speed_mult *= value
		"range_add":
			attack_range += value
		"projectile_add":
			projectile_count += int(value)
		"projectile_scale_mult":
			projectile_scale *= value
		"projectile_scale_add":
			projectile_scale += value
		"heart_add":
			max_hearts += int(value)
			hearts = mini(hearts + int(value), max_hearts)
		"shield_add":
			shield += int(value)
		"projectile_bounce_add":
			projectile_bounces += int(value)
		"shawarma_max_add":
			shawarma_max_add += int(value)
		"shawarma_xp_mult":
			shawarma_xp_mult *= value
		"powerup_rate_mult":
			powerup_rate_mult *= value
		"powerup_count_add":
			powerup_count_add += int(value)
		"pierce_add":
			projectile_pierce += int(value)
		"orbital_add":
			orbital_count += int(value)
		"nova_add":
			# First pick enables the nova; further picks tighten the release.
			nova_interval = value if nova_interval <= 0.0 else maxf(1.5, nova_interval * 0.8)
		_:
			push_warning("PlayerStats: unknown card effect type '%s'" % effect.get("type", ""))
