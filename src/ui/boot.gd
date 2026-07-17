extends Control
## Boot — loading screen wallpaper + progress bar → save-path choice
## (spec Section 9):
##  - "Play Now"            → local save only.
##  - "Sign in with Google" → Firebase Auth + Firestore cloud save; if a
##    cloud save exists it ALWAYS wins over local (no merge).
## Plus: Follow-on-Instagram + Support-the-Creator (XMR) buttons.
##
## Platform notes: cloud is Android-only right now (native plugin).
## The Google button is disabled off-Android.

const INSTAGRAM_URL := "https://www.instagram.com/al67x._/"
const XMR_ADDRESS := "8ApdEka2j6CUaaNKp12H1VBi1bziZB2T9Dhju1fPzgiTC8KBLWEEddVeZnpZjg7Ni4KCENsPLfSDfh2nbMhbFqngM5wKwHE"


var _load_done := false

@onready var _splash: TextureRect = $Splash
@onready var _loading_bar: ProgressBar = $LoadingBar
@onready var _title: Label = $TitleLabel
@onready var _menu: VBoxContainer = $Menu
@onready var _play_now_button: Button = $Menu/PlayNowButton
@onready var _google_button: Button = $Menu/GoogleButton
@onready var _ig_button: Button = $Menu/SocialRow/IGButton
@onready var _support_button: Button = $Menu/SocialRow/SupportButton
@onready var _status_label: Label = $Menu/StatusLabel
@onready var _support_panel: PanelContainer = $SupportPanel
@onready var _xmr_label: Label = $SupportPanel/SupportBox/XMRLabel
@onready var _copy_button: Button = $SupportPanel/SupportBox/CopyButton
@onready var _close_support_button: Button = $SupportPanel/SupportBox/CloseButton


func _ready() -> void:
	_menu.visible = false
	_title.visible = false
	_support_panel.visible = false
	_play_now_button.pressed.connect(_on_play_now)
	_google_button.pressed.connect(_on_google)
	_ig_button.pressed.connect(func() -> void: OS.shell_open(INSTAGRAM_URL))
	_support_button.pressed.connect(func() -> void: _support_panel.visible = true)
	_copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(XMR_ADDRESS)
		_copy_button.text = "COPIED! <3")
	_close_support_button.pressed.connect(func() -> void: _support_panel.visible = false)
	_xmr_label.text = XMR_ADDRESS
	_play_load()


func _ensure_splash_texture() -> void:
	if _splash.texture != null:
		return
	var f := FileAccess.open("res://assets/video/Loading-screen.png", FileAccess.READ)
	if f == null:
		return
	var bytes := f.get_buffer(f.get_length())
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return
	_splash.texture = ImageTexture.create_from_image(img)


func _play_load() -> void:
	_ensure_splash_texture()
	if _splash.texture == null or DisplayServer.get_name() == "headless":
		_finish_load()
		return
	_splash.visible = true
	_loading_bar.visible = true
	_loading_bar.value = 0.0
	var player := AudioStreamPlayer.new()
	player.stream = load("res://assets/audio/music/Credits.ogg")
	player.volume_db = -8.0
	add_child(player)
	player.play()
	await _fake_load()
	player.stop()
	player.queue_free()
	_finish_load()


func _fake_load() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bar := 0.0
	while bar < 100.0:
		var chunk := rng.randf_range(4.0, 14.0)
		bar = minf(bar + chunk, 100.0)
		var step_time := rng.randf_range(0.08, 0.22)
		if rng.randf() < 0.25:
			step_time += rng.randf_range(0.15, 0.45)
		var tween := create_tween()
		tween.tween_property(_loading_bar, "value", bar, step_time).set_ease(Tween.EASE_IN)
		await tween.finished


func _finish_load() -> void:
	if _load_done:
		return
	_load_done = true
	_splash.visible = false
	_loading_bar.visible = false
	_title.visible = true
	AudioDirector.play_music("hub")
	await get_tree().create_timer(0.2).timeout
	_decide()


func _decide() -> void:
	var mode := str(SaveService.get_value("meta.save_mode", ""))
	if mode == "local":
		_go_hub()
		return
	var adapter := CloudSaveAndroid.new()
	if mode == "cloud" and adapter.is_available() and adapter.is_signed_in():
		EventBus.cloud_state_changed.emit("syncing")
		await SaveService.attach_cloud_adapter(adapter)
		_go_hub()
		return
	_show_menu(adapter)


func _show_menu(adapter: CloudSaveAdapter) -> void:
	_menu.visible = true
	if adapter.is_available():
		_google_button.disabled = false
		_status_label.text = ""
	else:
		_google_button.disabled = true
		_status_label.text = "Google sign-in requires the Android build."


func _on_play_now() -> void:
	SaveService.set_value("meta.save_mode", "local")
	SaveService.save_now()
	_go_hub()


func _on_google() -> void:
	_google_button.disabled = true
	_play_now_button.disabled = true
	_status_label.text = "Signing in..."
	var adapter := CloudSaveAndroid.new()
	var ok: bool = await adapter.sign_in_interactive()
	if ok:
		SaveService.set_value("meta.save_mode", "cloud")
		_status_label.text = "Syncing save..."
		await SaveService.attach_cloud_adapter(adapter)
		SaveService.save_now()
		_go_hub()
	else:
		_google_button.disabled = false
		_play_now_button.disabled = false
		_status_label.text = "Sign-in failed — try again or Play Now."


func _go_hub() -> void:
	if SceneManager.is_transitioning:
		return
	SceneManager.change_scene(
		"res://scenes/hub/hub.tscn",
		{"pattern": "fade", "speed": 2.0, "skip_fade_out": true, "wait_time": 0.1}
	)
