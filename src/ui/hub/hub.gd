extends Control

const TAB_ORDER: Array[String] = ["play", "allans", "deck", "shop"]

const TAB_TRANSITION := {
	"pattern": "squares",
	"speed": 3.0,
	"wait_time": 0.05,
}

var _current_tab := "play"

@onready var _safe_area: MarginContainer = $SafeArea
@onready var _tabs: Dictionary = {
	"play": $SafeArea/Layout/Content/PlayTab,
	"allans": $SafeArea/Layout/Content/AllansTab,
	"deck": $SafeArea/Layout/Content/DeckTab,
	"shop": $SafeArea/Layout/Content/ShopTab,
}
@onready var _nav_buttons: Dictionary = {
	"play": $SafeArea/Layout/NavBar/NavBox/NavPlay,
	"allans": $SafeArea/Layout/NavBar/NavBox/NavAllans,
	"deck": $SafeArea/Layout/NavBar/NavBox/NavDeck,
	"shop": $SafeArea/Layout/NavBar/NavBox/NavShop,
}


func _ready() -> void:
	_apply_safe_area()
	for tab_id in TAB_ORDER:
		_nav_buttons[tab_id].pressed.connect(_on_nav_pressed.bind(tab_id))
	# Currency bars (scenes/ui/TopBars/) listen to the EventBus themselves —
	# no label wiring needed here anymore.
	$SafeArea/Layout/TopBar/TopBarBox/SettingsButton.pressed.connect(
		func() -> void: $SettingsPanel.open())
	_show_tab("play")
	AudioDirector.play_music("hub")


func _on_nav_pressed(tab_id: String) -> void:
	if tab_id == _current_tab or SceneManager.is_transitioning:
		_sync_nav_toggles()
		return
	var options := TAB_TRANSITION.duplicate()
	options["on_fade_out"] = func() -> void: _show_tab(tab_id)
	SceneManager.fade_in_place(options)


func _show_tab(tab_id: String) -> void:
	_current_tab = tab_id
	for id in _tabs:
		_tabs[id].visible = id == tab_id
	_sync_nav_toggles()
	AudioDirector.on_hub_tab_changed(tab_id)


func _sync_nav_toggles() -> void:
	for id in _nav_buttons:
		_nav_buttons[id].set_pressed_no_signal(id == _current_tab)


func _apply_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return
	var canvas := get_viewport().get_visible_rect().size
	var scale := canvas / Vector2(win)
	_safe_area.add_theme_constant_override("margin_top", int(safe.position.y * scale.y))
	_safe_area.add_theme_constant_override("margin_left", int(safe.position.x * scale.x))
	_safe_area.add_theme_constant_override("margin_right", int((win.x - safe.end.x) * scale.x))
	_safe_area.add_theme_constant_override("margin_bottom", int((win.y - safe.end.y) * scale.y))