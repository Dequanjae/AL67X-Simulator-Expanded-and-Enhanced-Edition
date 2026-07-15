extends Control
## Boot — Godot splash video (Kenney splash pack animation, tap to skip,
## paired with a synthesized cinematic sting) → save-path choice
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
const SPLASH_SECONDS := 3.4

var _splash_done := false

@onready var _splash: TextureRect = $Splash
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
	_play_splash()


func _play_splash() -> void:
	# Headless (tests/CI): skip straight to the menu.
	if _splash.texture == null or DisplayServer.get_name() == "headless":
		_finish_splash()
		return
	_splash.visible = true
	# Over-the-top: punch-in with overshoot, slow drift zoom, then fade.
	_splash.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	_splash.scale = Vector2(0.25, 0.25)
	_splash.modulate = Color(1, 1, 1, 0)
	AudioDirector.play_sfx("splash_sting", 0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_splash, "modulate", Color.WHITE, 0.5)
	tween.tween_property(_splash, "scale", Vector2(1.06, 1.06), 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(_splash, "scale", Vector2(1.12, 1.12), SPLASH_SECONDS - 1.4)
	tween.chain().tween_property(_splash, "modulate", Color(1, 1, 1, 0), 0.5)
	tween.chain().tween_callback(_finish_splash)


func _input(event: InputEvent) -> void:
	# Tap/click/any key skips the splash.
	if _splash_done:
		return
	if (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed) \
			or event is InputEventKey:
		_finish_splash()


func _finish_splash() -> void:
	if _splash_done:
		return
	_splash_done = true
	_splash.visible = false
	_title.visible = true
	# Main menu music starts AFTER the splash, not under it.
	AudioDirector.play_music("hub")
	# SceneManager (addon) needs its first _process before any change_scene.
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
