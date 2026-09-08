extends Node
## FontService — applies the project's custom game font at startup, in code.
## WHY NOT theme/custom: a .tres that references the font file is loaded
## BEFORE the font's imported .fontdata exists on a cold import (fresh CI
## checkout, first phone boot) — the theme load fails, the failed reference
## poisons the font's remap, and every boot after that re-fails. Applying
## the font in code after the first frame sidesteps the whole ordering
## problem: if the font somehow fails, the game still boots with the
## default font instead of dying with a broken theme.

const GAME_FONT_PATH := "res://assets/UI/fonts/Clash-Regular.ttf"

func _ready() -> void:
	call_deferred("_apply_font")

func _apply_font() -> void:
	var font: Variant = load(GAME_FONT_PATH)
	if font == null or not (font is Font):
		push_warning("FontService: game font missing (%s) — using default" % GAME_FONT_PATH)
		return
	# Project-wide default font for every control that doesn't override.
	var theme := ThemeDB.get_project_theme()
	if theme != null:
		theme.default_font = font
		theme.default_font_size = 16
	# Fallback chain too (dialogs etc.).
	var fb := ThemeDB.get_fallback_font()
	if fb == null:
		ThemeDB.set_fallback_font(font as Font)
