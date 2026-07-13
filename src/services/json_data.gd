class_name JsonData
extends RefCounted
## Tiny helper for the agent-editable plain-text data pipeline (Section 13).
## All extensible game content loads through here (or through folder scans
## of text .tres files) — never from hardcoded tables in scripts.


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("JsonData: missing data file %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("JsonData: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null:
		push_error("JsonData: %s is not valid JSON" % path)
	return parsed


## Lists resource/data files in a folder (non-recursive), for folder-scan
## loaders (cards, enemies, loot boxes). Works in exported builds too since
## it uses ResourceLoader-visible paths.
static func list_files(dir_path: String, extension: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			# Exported PCK may expose imported files as *.remap — strip it.
			var clean := name.trim_suffix(".remap")
			if clean.get_extension() == extension:
				out.append(dir_path.path_join(clean))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
