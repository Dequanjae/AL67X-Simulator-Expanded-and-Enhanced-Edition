extends VBoxContainer
## Hub tab: Play — shows current level ("day at the shop") and enters a run.

@onready var _level_label: Label = $LevelLabel
@onready var _play_button: Button = $PlayButton


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	EventBus.save_loaded.connect(_refresh)
	EventBus.level_unlocked.connect(func(_level: int) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	var level := int(SaveService.get_value("progress.highest_level_unlocked", 1))
	_level_label.text = "Day %d at the Electric Motor Shop" % level


func _on_play_pressed() -> void:
	if SceneManager.is_transitioning:
		return
	SceneManager.change_scene(
		"res://scenes/run/run.tscn",
		{"pattern": "diagonal", "speed": 2.5}
	)
