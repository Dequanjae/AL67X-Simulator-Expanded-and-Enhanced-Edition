extends SceneTree
## CI smoke: verify the project font + theme resolve in a FRESH import
## environment. Exits non-zero on failure so CI blocks a broken export.
func _init() -> void:
	var failures: PackedStringArray = []
	var font: Variant = load("res://assets/fonts/YouBlockheadOpen.ttf")
	if font == null or not (font is Font):
		failures.append("font load failed: res://assets/fonts/YouBlockheadOpen.ttf")
	var theme: Variant = load("res://assets/theme/al67x_theme.tres")
	if theme == null or not (theme is Theme):
		failures.append("theme load failed: res://assets/theme/al67x_theme.tres")
	elif (theme as Theme).default_font == null:
		failures.append("theme default_font is null (font reference broken)")
	if failures.is_empty():
		print("FONT SMOKE: PASS")
		quit(0)
	else:
		for f in failures:
			printerr("FONT SMOKE FAIL: %s" % f)
		quit(1)
