extends Control
## Hub — hosts the Home/Shop/Settings/Merge/Deck HTML UI in one WebView
## (see web_ui/hub/index.html). All screen presentation lives in JS; this
## script only owns what must happen scene-side (starting a run) and the
## existing audio-state hooks the old Control-based tabs used to drive.

@onready var _web = $WebViewHost


func _ready() -> void:
	_web.ipc_message.connect(_on_ipc_message)
	AudioDirector.play_music("hub")


func _on_ipc_message(message: String) -> void:
	var data: Variant = JSON.parse_string(message)
	if not (data is Dictionary):
		return
	match str(data.get("type", "")):
		"start_run":
			_start_run()
		"sign_in":
			_go_to_boot()
		"nav_change":
			AudioDirector.on_hub_tab_changed(str(data.get("tab", "home")))


func _start_run() -> void:
	if SceneManager.is_transitioning:
		return
	SceneManager.change_scene("res://scenes/run/run.tscn", {
		"pattern": "squares",
		"speed": 3.0,
		"wait_time": 0.05,
	})


func _go_to_boot() -> void:
	if SceneManager.is_transitioning:
		return
	SceneManager.change_scene("res://scenes/boot/boot.tscn", {
		"pattern": "squares",
		"speed": 3.0,
		"wait_time": 0.05,
	})
