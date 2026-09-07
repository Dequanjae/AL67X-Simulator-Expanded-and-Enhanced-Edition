extends SceneTree
## CI smoke: verify the font pipeline works in a FRESH import environment.
## Architecture (since FontService): the theme .tres carries NO font
## reference (a .tres reference loads before fontdata exists on cold
## import, poisons the font remap, and re-fails every boot — the phone
## black screen). FontService applies the font in code at startup.
## This smoke checks: (1) the font FILE imports to loadable fontdata,
## (2) the theme loads at all (no broken references), (3) FontService
## script exists. Runtime application is editor-gate-verified, not CI.
func _init() -> void:
	var failures: PackedStringArray = []
	var font: Variant = load("res://assets/fonts/YouBlockheadOpen.ttf")
	if font == null or not (font is Font):
		failures.append("font load failed: res://assets/fonts/YouBlockheadOpen.ttf")
	var theme: Variant = load("res://assets/theme/al67x_theme.tres")
	if theme == null or not (theme is Theme):
		failures.append("theme load failed: res://assets/theme/al67x_theme.tres")
	var fs_check: Variant = load("res://src/autoload/font_service.gd")
	if fs_check == null:
		failures.append("FontService script missing")
	if ResourceLoader.exists("res://src/autoload/font_service.gd") == false:
		failures.append("FontService not in export")
	if failures.is_empty():
		print("FONT SMOKE: PASS")
		quit(0)
	else:
		for f in failures:
			printerr("FONT SMOKE FAIL: %s" % f)
		quit(1)
