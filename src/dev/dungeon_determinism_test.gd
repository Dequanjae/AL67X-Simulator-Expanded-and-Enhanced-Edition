extends Node
## Dungeon determinism gate — package protocol:
##   seed 84729103, level 10: generate twice, must be identical.
##   seed 84729104: must differ.
##   restore 84729103: must return to the original.
## Exits 0 on PASS, 1 on FAIL.

func _ready() -> void:
	await get_tree().process_frame
	var failures: PackedStringArray = []

	if not ClassDB.class_exists("DungeonGeneratorRs"):
		printerr("DETERMINISM FAIL: DungeonGeneratorRs not available")
		get_tree().quit(1)
		return
	var gen = ClassDB.instantiate("DungeonGeneratorRs")

	var a = gen.generate_dungeon(10, 84729103, 100, 60)
	var b = gen.generate_dungeon(10, 84729103, 100, 60)
	if _sig(a) != _sig(b):
		failures.append("same seed+level produced different layouts")

	var c = gen.generate_dungeon(10, 84729104, 100, 60)
	if _sig(a) == _sig(c):
		failures.append("different seed produced identical layout (seed not affecting layout)")

	var d2 = gen.generate_dungeon(10, 84729103, 100, 60)
	if _sig(a) != _sig(d2):
		failures.append("restored seed did not reproduce original layout")

	# walkability: player start must be on a floor tile
	var ps: Vector2i = a["player_start"]
	var tiles: PackedByteArray = a["tiles"]
	var tw: int = a["width"]
	if tiles[ps.y * tw + ps.x] != 1:
		failures.append("player start not on floor tile")

	if failures.is_empty():
		print("DETERMINISM TEST: PASS (rooms=%d enemies=%d)" % [a["rooms"].size(), a["enemy_spawn_points"].size()])
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("DETERMINISM FAIL: %s" % f)
		get_tree().quit(1)


func _sig(d: Dictionary) -> Dictionary:
	return {
		"tiles": (d["tiles"] as PackedByteArray).duplicate(),
		"rooms": (d["rooms"] as Array).duplicate(true),
		"player_start": d["player_start"],
		"enemy_spawn_points": (d["enemy_spawn_points"] as Array).duplicate(true),
	}
