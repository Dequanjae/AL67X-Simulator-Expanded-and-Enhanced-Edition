class_name BossCatalog
extends RefCounted
## Folder-scanned boss definitions (data/bosses/*.json) + the endless
## composition rule (spec Section 3): bosses cycle by level; each full
## cycle REMIXES in patterns borrowed from other boss definitions and
## tightens pattern intervals — "floor 10's boss reuses pieces of floor 3
## and floor 6's patterns in a new combination". Deterministic per level.

const MAX_PATTERNS := 5
const INTERVAL_TIGHTEN_PER_CYCLE := 0.92
const HP_GROWTH_PER_CYCLE := 0.35


static func load_all() -> Array:
	var bosses: Array = []
	for path in JsonData.list_files("res://data/bosses", "json"):
		var boss: Variant = JsonData.load_json(path)
		if boss is Dictionary and boss.has("id"):
			bosses.append(boss)
	# Cycle order comes from the explicit "order" field (agent-addable
	# without filename conventions); ties break by id.
	bosses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(a.get("order", 9999))
		var ob := int(b.get("order", 9999))
		if oa != ob:
			return oa < ob
		return str(a.get("id", "")) < str(b.get("id", "")))
	return bosses


## Returns the fully composed (remixed + scaled) boss definition for a level.
static func compose_for_level(level: int, bosses: Array) -> Dictionary:
	if bosses.is_empty():
		return {}
	var count := bosses.size()
	var index := (level - 1) % count
	var cycle := (level - 1) / count
	var composed: Dictionary = (bosses[index] as Dictionary).duplicate(true)
	var patterns: Array = composed.get("patterns", [])

	# Remix: borrow the first pattern of each subsequent boss, one per cycle.
	for k in range(1, mini(cycle, count - 1) + 1):
		if patterns.size() >= MAX_PATTERNS:
			break
		var donor: Dictionary = bosses[(index + k) % count]
		var donor_patterns: Array = donor.get("patterns", [])
		if donor_patterns.is_empty():
			continue
		var borrowed: Dictionary = (donor_patterns[0] as Dictionary).duplicate(true)
		borrowed["_borrowed_from"] = str(donor.get("id", "?"))
		patterns.append(borrowed)

	# Scale: tighter intervals + more HP each cycle.
	if cycle > 0:
		var tighten := pow(INTERVAL_TIGHTEN_PER_CYCLE, float(cycle))
		for pattern in patterns:
			if pattern.has("interval"):
				pattern["interval"] = maxf(0.6, float(pattern["interval"]) * tighten)
		composed["hp_mult"] = float(composed.get("hp_mult", 1.0)) * (1.0 + HP_GROWTH_PER_CYCLE * float(cycle))

	composed["patterns"] = patterns
	composed["cycle"] = cycle
	return composed
