extends Control
## Hub — native Godot UI (replacing the old HTML/WebView hub).
## All nodes built in _ready(); Home + Settings functional, Shop/Merge/Deck
## placeholder-ready for itch.io sprite pack drops.

var _current_tab := "home"
var _tab_btns: Dictionary = {}
var _views: Dictionary = {}
var _blob_label: Label
var _token_label: Label
var _level_label: Label


func _ready() -> void:
	_build_views()
	_refresh_pills()
	_switch_tab("home")
	AudioDirector.play_music("hub")


func _build_views() -> void:
	var ink := Color("#1c1c1c")
	var paper := Color("#fffaf0")

	# --- Top bar: resource pills ---
	_blob_label = _make_pill("Blobs", Color("#ffd400"), 0)
	_token_label = _make_pill("AL67X", Color("#16d1ff"), 0)
	var _amp_label := _make_pill("Amps", Color("#ff6a13"), 0)

	# --- Nav rail (right side) ---
	var nav := VBoxContainer.new()
	nav.name = "Nav"
	nav.position = Vector2(1280 - 100, 12)
	nav.size = Vector2(88, 0)
	nav.add_theme_constant_override("separation", 6)
	add_child(nav)

	var tab_defs := [
		["home", "HOME"],
		["deck", "CARDS"],
		["merge", "MERGE"],
		["shop", "SHOP"],
	]
	for td in tab_defs:
		var id: String = td[0]
		var label: String = td[1]
		var btn := _make_nav_btn(label)
		btn.pressed.connect(func(tab: String = id) -> void: _switch_tab(tab))
		nav.add_child(btn)
		_tab_btns[id] = btn

	# --- Views ---
	_build_home(ink, paper)
	_build_settings(ink, paper)
	_build_placeholder("deck", "DECK", "Card collection coming soon — drop in itch.io sprites!")
	_build_placeholder("merge", "MERGE", "Fusion grid coming soon!")
	_build_placeholder("shop", "SHOP", "Shop catalog coming soon!")


func _build_home(ink: Color, paper: Color) -> void:
	var view := Control.new()
	view.name = "HomeView"
	view.visible = false
	add_child(view)
	_views["home"] = view

	var highest := int(SaveService.get_value("progress.highest_level_unlocked", 1))

	_level_label = Label.new()
	_level_label.text = "LV %d\nSHOP TECH" % highest
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.position = Vector2(1280 / 2 - 100, 720 / 2 - 80)
	_level_label.size = Vector2(200, 60)
	_level_label.add_theme_font_size_override("font_size", 24)
	_level_label.add_theme_color_override("font_color", paper)
	view.add_child(_level_label)

	var play_btn := Button.new()
	play_btn.text = "▶"
	play_btn.custom_minimum_size = Vector2(96, 96)
	play_btn.size = Vector2(96, 96)
	play_btn.position = Vector2(1280 / 2 - 48, 720 / 2 + 10)
	var play_style := StyleBoxFlat.new()
	play_style.bg_color = Color("#ff6a13")
	play_style.border_color = ink
	play_style.border_width_left = 3
	play_style.border_width_top = 3
	play_style.border_width_right = 3
	play_style.border_width_bottom = 3
	play_style.corner_radius_top_left = 48
	play_style.corner_radius_top_right = 48
	play_style.corner_radius_bottom_left = 48
	play_style.corner_radius_bottom_right = 48
	play_style.shadow_color = Color(0, 0, 0, 0.35)
	play_style.shadow_size = 6
	play_btn.add_theme_stylebox_override("normal", play_style)
	play_btn.add_theme_font_size_override("font_size", 28)
	play_btn.add_theme_color_override("font_color", paper)
	play_btn.pressed.connect(_start_run)
	view.add_child(play_btn)


func _build_settings(ink: Color, paper: Color) -> void:
	var view := Control.new()
	view.name = "SettingsView"
	view.visible = false
	add_child(view)
	_views["settings"] = view

	var title := Label.new()
	title.text = "SETTINGS"
	title.position = Vector2(1280 / 2 - 80, 40)
	title.size = Vector2(160, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", paper)
	view.add_child(title)

	var y := 100
	var slider_rows := [
		["Music Volume", "music_volume"],
		["SFX Volume", "sfx_volume"],
		["Screen Shake", "screen_shake"],
	]
	for row in slider_rows:
		var label := row[0] as String
		var key := row[1] as String
		var hbox := HBoxContainer.new()
		hbox.position = Vector2(1280 / 2 - 180, y)
		hbox.size = Vector2(360, 36)
		hbox.add_theme_constant_override("separation", 12)
		view.add_child(hbox)

		var lbl := Label.new()
		lbl.text = label
		lbl.custom_minimum_size = Vector2(140, 0)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", paper)
		hbox.add_child(lbl)

		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(160, 0)
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.value = GameSettings.get_value(key)
		slider.value_changed.connect(func(v: float, k: String = key) -> void: GameSettings.set_value(k, v))
		hbox.add_child(slider)

		var val_label := Label.new()
		val_label.custom_minimum_size = Vector2(40, 0)
		val_label.add_theme_font_size_override("font_size", 12)
		val_label.add_theme_color_override("font_color", Color("#9aa0a6"))
		val_label.text = str(int(slider.value * 100)) + "%"
		slider.value_changed.connect(func(v: float, vl: Label = val_label) -> void: vl.text = str(int(v * 100)) + "%")
		hbox.add_child(val_label)

		y += 44

	var toggle_defs := [
		["Camera Smoothing", "camera_smoothing"],
		["Goo Splats", "goo_splats"],
		["Damage Numbers", "damage_numbers"],
	]
	for td in toggle_defs:
		var label := td[0] as String
		var key := td[1] as String
		var hbox := HBoxContainer.new()
		hbox.position = Vector2(1280 / 2 - 180, y)
		hbox.size = Vector2(360, 36)
		hbox.add_theme_constant_override("separation", 12)
		view.add_child(hbox)

		var lbl := Label.new()
		lbl.text = label
		lbl.custom_minimum_size = Vector2(140, 0)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", paper)
		hbox.add_child(lbl)

		var check := CheckButton.new()
		check.button_pressed = GameSettings.get_value(key)
		check.toggled.connect(func(v: bool, k: String = key) -> void: GameSettings.set_value(k, v))
		hbox.add_child(check)

		y += 44


func _build_placeholder(id: String, title: String, subtitle: String) -> void:
	var view := Control.new()
	view.name = id.capitalize() + "View"
	view.visible = false
	add_child(view)
	_views[id] = view

	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(1280 / 2 - 100, 720 / 2 - 40)
	t.size = Vector2(200, 30)
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color("#16d1ff"))
	view.add_child(t)

	var s := Label.new()
	s.text = subtitle
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.position = Vector2(1280 / 2 - 200, 720 / 2 + 0)
	s.size = Vector2(400, 20)
	s.add_theme_font_size_override("font_size", 12)
	s.add_theme_color_override("font_color", Color("#9aa0a6"))
	view.add_child(s)


func _switch_tab(tab: String) -> void:
	if _current_tab == tab:
		return
	for v in _views.values():
		v.visible = false
	var target := _views.get(tab)
	if target:
		target.visible = true
	_current_tab = tab
	for id in _tab_btns:
		_tab_btns[id].disabled = (id == tab)
	AudioDirector.on_hub_tab_changed(tab)


func _start_run() -> void:
	if SceneManager.is_transitioning:
		return
	SceneManager.change_scene("res://scenes/run/run.tscn", {
		"pattern": "squares",
		"speed": 3.0,
		"wait_time": 0.05,
	})


func _refresh_pills() -> void:
	_blob_label.text = str(EconomyService.get_blobs())
	_token_label.text = str(EconomyService.get_tokens())


func _make_pill(label: String, accent: Color, value: int) -> Label:
	var pills := find_child("Pills", true, false)
	if not pills:
		pills = HBoxContainer.new()
		pills.name = "Pills"
		pills.position = Vector2(12, 12)
		pills.add_theme_constant_override("separation", 8)
		add_child(pills)

	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fffaf0")
	style.border_color = Color("#1c1c1c")
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(140, 44)
	(pills as HBoxContainer).add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.position = Vector2(4, 0)
	hbox.size = Vector2(132, 44)
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.color = accent
	hbox.add_child(icon)

	var vbox := VBoxContainer.new()
	hbox.add_child(vbox)

	var val := Label.new()
	val.text = str(value)
	val.add_theme_font_size_override("font_size", 16)
	val.add_theme_color_override("font_color", Color("#1c1c1c"))
	vbox.add_child(val)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color("#333333"))
	vbox.add_child(lbl)

	return val


func _make_nav_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(88, 80)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fffaf0")
	style.border_color = Color("#1c1c1c")
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 4
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.add_theme_color_override("font_color", Color("#1c1c1c"))
	btn.add_theme_color_override("font_color_disabled", Color("#1c1c1c"))
	btn.add_theme_font_size_override("font_size", 12)
	return btn
