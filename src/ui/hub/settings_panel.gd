extends Control
## Settings panel (hub overlay): audio volumes, graphics/feel toggles
## (screen shake, camera smoothing, goo splats, damage numbers) and the
## account section (sign in with Google / sign out). Values persist in the
## save (meta.settings) and apply live via EventBus.settings_changed.

@onready var _music_slider: HSlider = $Center/Box/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $Center/Box/SFXRow/SFXSlider
@onready var _shake_slider: HSlider = $Center/Box/ShakeRow/ShakeSlider
@onready var _smoothing_check: CheckButton = $Center/Box/SmoothingCheck
@onready var _splats_check: CheckButton = $Center/Box/SplatsCheck
@onready var _numbers_check: CheckButton = $Center/Box/NumbersCheck
@onready var _account_label: Label = $Center/Box/AccountRow/AccountLabel
@onready var _account_button: Button = $Center/Box/AccountRow/AccountButton
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
	_account_button.pressed.connect(_on_account_button)


func open() -> void:
	_music_slider.set_value_no_signal(GameSettings.music_volume())
	_sfx_slider.set_value_no_signal(GameSettings.sfx_volume())
	_shake_slider.set_value_no_signal(GameSettings.screen_shake())
	_smoothing_check.set_pressed_no_signal(GameSettings.camera_smoothing())
	_splats_check.set_pressed_no_signal(GameSettings.goo_splats())
	_numbers_check.set_pressed_no_signal(GameSettings.damage_numbers())
	_refresh_account()
	visible = true


func _refresh_account() -> void:
	var mode := str(SaveService.get_value("meta.save_mode", ""))
	var adapter := CloudSaveAndroid.new()
	if mode == "cloud" and adapter.is_available() and adapter.is_signed_in():
		_account_label.text = "Signed in (cloud save)"
		_account_button.text = "Sign out"
	elif adapter.is_available():
		_account_label.text = "Local save"
		_account_button.text = "Sign in with Google"
	else:
		_account_label.text = "Local save (cloud needs Android)"
		_account_button.text = "Sign in with Google"
		_account_button.disabled = true


func _on_account_button() -> void:
	var mode := str(SaveService.get_value("meta.save_mode", ""))
	var adapter := CloudSaveAndroid.new()
	if mode == "cloud" and adapter.is_available() and adapter.is_signed_in():
		# Sign out → back to local-only saving.
		if Engine.has_singleton("GodotFirebaseAndroid"):
			Firebase.auth.sign_out()
		SaveService.set_value("meta.save_mode", "local")
		SaveService.detach_cloud()
		_refresh_account()
	else:
		# Route through the boot flow for interactive sign-in.
		SaveService.set_value("meta.save_mode", "")
		SaveService.save_now()
		visible = false
		SceneManager.change_scene("res://scenes/boot/boot.tscn", {"pattern": "fade", "speed": 3.0})
