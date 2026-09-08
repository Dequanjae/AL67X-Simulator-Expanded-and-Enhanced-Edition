extends Control
## Boot — loading screen wallpaper + progress bar → title menu.
## PLAY NOW enters the hub on a local save. The old Google sign-in /
## Support-the-Creator (XMR) panel were removed (2026-09-08 UI cleanup) —
## cloud-save plumbing (CloudSaveAdapter/Android) stays in the codebase
## untouched for whenever account sign-in returns.

const INSTAGRAM_URL := "https://www.instagram.com/al67x._/"

var _load_done := false

@onready var _splash: TextureRect = $Splash
@onready var _loading_bar: ProgressBar = $LoadingBar
@onready var _title: Label = $TitleLabel
@onready var _menu: VBoxContainer = $Menu
@onready var _play_now_button: Button = $Menu/PlayNowButton
@onready var _ig_button: Button = $Menu/SocialRow/IGButton
@onready var _status_label: Label = $Menu/StatusLabel


func _ready() -> void:
	_menu.visible = false
	_title.visible = false
	_play_now_button.pressed.connect(_on_play_now)
	_ig_button.pressed.connect(func() -> void: OS.shell_open(INSTAGRAM_URL))
	_play_load()


func _ensure_splash_texture() -> void:
	if _splash.texture != null:
		return
	# load() follows the .remap in exported builds (raw PNG is not packed),
	# so this works in the editor AND on Android. FileAccess.open() does not
	# remap, which silently skipped the splash in every export.
	var tex: Texture2D = load("res://assets/video/Loading-screen.png")
	if tex != null:
		_splash.texture = tex


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
	_show_menu()


func _show_menu() -> void:
	_menu.visible = true
	_status_label.text = ""


func _on_play_now() -> void:
	SaveService.set_value("meta.save_mode", "local")
	SaveService.save_now()
	_go_hub()


func _go_hub() -> void:
	if SceneManager.is_transitioning:
		return
	SceneManager.change_scene(
		"res://scenes/hub/hub.tscn",
		{"pattern": "fade", "speed": 2.0, "skip_fade_out": true, "wait_time": 0.1}
	)