class_name RunBalance
extends RefCounted
## Pure balance-curve math (spec Section 2). All constants come from
## data/balance/run_curves.json — this file only implements the formulas
## documented there. Tunables are data, never magic numbers here.


static func load_config() -> Dictionary:
	var parsed: Variant = JsonData.load_json("res://data/balance/run_curves.json")
	return parsed if parsed is Dictionary else {}


## Percentage-based growth that shrinks per level, with a hard cap:
## seconds(level) = min(cap, base * Π_{i=0..level-2} (1 + rate * decay^i))
static func survival_seconds(level: int, config: Dictionary) -> float:
	var cfg: Dictionary = config.get("survival_timer", {})
	var seconds := float(cfg.get("base_seconds", 60))
	var rate := float(cfg.get("growth_rate", 0.2))
	var decay := float(cfg.get("growth_decay", 0.93))
	var cap := float(cfg.get("cap_seconds", 480))
	for i in range(level - 1):
		seconds *= 1.0 + rate * pow(decay, float(i))
	return minf(seconds, cap)


## Spawn interval shrinks with level and time survived, floored:
## interval = max(min, base / (1 + level_factor*(level-1) + time_factor*t))
## Level 1 is the tutorial hook: intervals stretched by level1_interval_mult.
static func spawn_interval(level: int, time_survived: float, config: Dictionary) -> float:
	var cfg: Dictionary = config.get("enemy_spawn", {})
	var base := float(cfg.get("base_interval_sec", 2.0))
	var min_interval := float(cfg.get("min_interval_sec", 0.35))
	var level_factor := float(cfg.get("level_factor", 0.08))
	var time_factor := float(cfg.get("time_factor", 0.012))
	var interval := maxf(min_interval, base / (1.0 + level_factor * float(level - 1) + time_factor * time_survived))
	if level <= 1:
		interval *= float(cfg.get("level1_interval_mult", 1.5))
	return interval


## Enemies per spawn tick — grows with level and time survived, capped:
## batch = min(batch_max, 1 + (level-1)/batch_per_levels + t/batch_time_sec)
static func spawn_batch(level: int, time_survived: float, config: Dictionary) -> int:
	var cfg: Dictionary = config.get("enemy_spawn", {})
	if level <= 1:
		return 1  # tutorial: singles only
	var per_levels := maxf(0.5, float(cfg.get("batch_per_levels", 3.0)))
	var time_sec := maxf(10.0, float(cfg.get("batch_time_sec", 70.0)))
	var batch := 1 + int(float(level - 1) / per_levels) + int(time_survived / time_sec)
	return clampi(batch, 1, int(cfg.get("batch_max", 6)))


## XP needed to clear the given in-run level (levels start at 0).
static func xp_threshold(level: int, config: Dictionary) -> float:
	var cfg: Dictionary = config.get("player_xp", {})
	var base := float(cfg.get("base_kills_to_level", 8))
	var growth := float(cfg.get("kills_growth_per_level", 1.35))
	return ceilf(base * pow(growth, float(level)))
