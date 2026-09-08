extends Control
## Settings panel (hub overlay): audio volumes + graphics/feel toggles
## (screen shake, camera smoothing, goo splats, damage numbers). Values
## persist in the save (meta.settings) and apply live via EventBus.
## Account section removed with the Google sign-in cut (2026-09-08).

@onready var _music_slider: HSlider = $Center/Box/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $Center/Box/SFXRow/SFXSlider
@onready var _shake_slider: HSlider = $Center/Box/ShakeRow/ShakeSlider
@onready var _smoothing_check: CheckButton = $Center/Box/SmoothingCheck
@onready var _splats_check: CheckButton = $Center/Box/SplatsCheck
@onready var _numbers_check: CheckButton = $Center/Box/NumbersCheck
@onready var _close_button: Button = $Center/Box/CloseButton


func _ready() -> void:
	visible = false
	add_to_group("modal_overlay")
	_close_button.pressed.connect(func() -> void: visible = false)
	_music_slider.value_changed.connect(func(v: float) -> void: GameSettings.set_value("music_volume", v))
	_sfx_slider.value_changed.connect(func(v: float) -> void:
		GameSettings.set_value("sfx_volume", v)
		AudioDirector.play_sfx("ui_tap"))
	_shake_slider.value_changed.connect(func(v: float) -> void: GameSettings.set_value("screen_shake", v))
	_smoothing_check.toggled.connect(func(on: bool) -> void: GameSettings.set_value("camera_smoothing", on))
	_splats_check.toggled.connect(func(on: bool) -> void: GameSettings.set_value("goo_splats", on))
	_numbers_check.toggled.connect(func(on: bool) -> void: GameSettings.set_value("damage_numbers", on))


func open() -> void:
	_music_slider.set_value_no_signal(GameSettings.music_volume())
	_sfx_slider.set_value_no_signal(GameSettings.sfx_volume())
	_shake_slider.set_value_no_signal(GameSettings.screen_shake())
	_smoothing_check.set_pressed_no_signal(GameSettings.camera_smoothing())
	_splats_check.set_pressed_no_signal(GameSettings.goo_splats())
	_numbers_check.set_pressed_no_signal(GameSettings.damage_numbers())
	visible = true