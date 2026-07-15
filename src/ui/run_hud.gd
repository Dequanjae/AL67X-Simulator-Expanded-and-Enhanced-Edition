@tool
class_name RunHud
extends CanvasLayer
## Native Godot HUD replacing web_ui/hud. Built in _ready so layout is
## self-contained. Exposes signals for run_controller to wire up.

signal pause_toggled(paused: bool)
signal ad_continue_pressed()
signal ascend_pressed()
signal quit_to_hub_pressed()
signal dev_boss_win_pressed()
signal dev_die_pressed()

var hearts_icons: Array[TextureRect] = []
var timer_label: Label
var level_label: Label
var xp_fill: ColorRect
var xp_bg: ColorRect
var blob_label: Label
var pause_btn: Button
var boss_warn: Label
var boss_bar_fill: ColorRect
var boss_bar_bg: ColorRect
var boss_name_label: Label
var death_panel: Panel
var ascend_overlay: Panel
var pause_overlay: Panel
var ad_continue_btn: Button
var ascend_btn: Button
var resume_btn: Button
var quit_hub_btn: Button
var dev_win_btn: Button
var dev_die_btn: Button

func _ready() -> void:
	_build_hud()

func _build_hud() -> void:
	var theme := _make_theme()
	var ink := Color("#1c1c1c")
	var paper := Color("#fffaf0")
	var panel_dark := Color("#232323")
	var safety := Color("#ff6a13")
	var volt := Color("#16d1ff")
	var caution := Color("#ffd400")
	var danger := Color("#ff3d3d")
	var wall := Color("#e8e2d4")

	# --- Top bar (hearts / timer / level) ---
	var topbar := HBoxContainer.new()
	topbar.name = "TopBar"
	topbar.position = Vector2(12, 12)
	topbar.add_theme_constant_override("separation", 8)
	add_child(topbar)

	# Hearts
	var hearts := HBoxContainer.new()
	hearts.name = "Hearts"
	hearts.add_theme_constant_override("separation", 2)
	topbar.add_child(hearts)
	for i in range(5):
		var heart := TextureRect.new()
		heart.custom_minimum_size = Vector2(22, 22)
		heart.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		heart.modulate = danger
		heart.visible = false
		hearts.add_child(heart)
		hearts_icons.append(heart)

	# Timer
	var timer_panel := Panel.new()
	timer_panel.add_theme_stylebox_override("panel", _make_chunky_style(panel_dark, ink))
	topbar.add_child(timer_panel)
	timer_label = Label.new()
	timer_label.text = "1:00"
	timer_label.add_theme_font_size_override("font_size", 18)
	timer_label.add_theme_color_override("font_color", paper)
	timer_label.add_theme_constant_override("shadow_outline_size", 2)
	timer_label.add_theme_color_override("font_shadow_color", ink)
	timer_panel.add_child(timer_label)

	# Level / XP
	var level_panel := Panel.new()
	level_panel.add_theme_stylebox_override("panel", _make_chunky_style(panel_dark, ink))
	topbar.add_child(level_panel)
	var level_vbox := VBoxContainer.new()
	level_panel.add_child(level_vbox)
	level_label = Label.new()
	level_label.text = "Lv 1"
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_color", caution)
	level_vbox.add_child(level_label)
	var xp_container := Control.new()
	xp_container.custom_minimum_size = Vector2(80, 8)
	level_vbox.add_child(xp_container)
	xp_bg = ColorRect.new()
	xp_bg.color = ink
	xp_bg.size = Vector2(80, 8)
	xp_bg.position = Vector2.ZERO
	xp_container.add_child(xp_bg)
	xp_fill = ColorRect.new()
	xp_fill.color = caution
	xp_fill.size = Vector2(0, 8)
	xp_fill.position = Vector2.ZERO
	xp_container.add_child(xp_fill)

	# --- Top-right (blobs + pause) ---
	var topright := HBoxContainer.new()
	topright.name = "TopRight"
	topright.position = Vector2(1280 - 12, 12)
	topright.size = Vector2(0, 0)
	topright.add_theme_constant_override("separation", 8)
	add_child(topright)

	# Blobs pill
	var blob_panel := Panel.new()
	blob_panel.add_theme_stylebox_override("panel", _make_chunky_style(paper, ink))
	blob_panel.add_theme_constant_override("shadow_outline_size", 2)
	topright.add_child(blob_panel)
	var blob_hbox := HBoxContainer.new()
	blob_panel.add_child(blob_hbox)
	var blob_icon := ColorRect.new()
	blob_icon.custom_minimum_size = Vector2(18, 18)
	blob_icon.color = caution
	blob_hbox.add_child(blob_icon)
	blob_label = Label.new()
	blob_label.text = "0"
	blob_label.add_theme_font_size_override("font_size", 16)
	blob_label.add_theme_color_override("font_color", ink)
	blob_hbox.add_child(blob_label)

	# Pause button
	pause_btn = Button.new()
	pause_btn.text = "| |"
	pause_btn.custom_minimum_size = Vector2(36, 36)
	pause_btn.add_theme_font_size_override("font_size", 14)
	pause_btn.add_theme_color_override("font_color", ink)
	pause_btn.add_theme_stylebox_override("normal", _make_chunky_style(paper, ink))
	pause_btn.add_theme_stylebox_override("pressed", _make_chunky_style(Color("#cfc6ae"), ink))
	pause_btn.toggled.connect(func(toggled: bool) -> void: pause_toggled.emit(toggled))
	pause_btn.toggle_mode = true
	topright.add_child(pause_btn)

	# --- Boss warning ---
	boss_warn = Label.new()
	boss_warn.name = "BossWarn"
	boss_warn.text = "BOSS INCOMING"
	boss_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_warn.position = Vector2(1280 / 2 - 100, 50)
	boss_warn.size = Vector2(200, 30)
	boss_warn.add_theme_font_size_override("font_size", 22)
	boss_warn.add_theme_color_override("font_color", danger)
	boss_warn.add_theme_constant_override("shadow_outline_size", 3)
	boss_warn.add_theme_color_override("font_shadow_color", ink)
	boss_warn.visible = false
	add_child(boss_warn)

	# --- Boss HP bar ---
	var boss_bar_container := Control.new()
	boss_bar_container.name = "BossHP"
	boss_bar_container.position = Vector2(1280 / 2 - 100, 80)
	boss_bar_container.size = Vector2(200, 22)
	boss_bar_container.visible = false
	add_child(boss_bar_container)
	boss_name_label = Label.new()
	boss_name_label.position = Vector2(0, -16)
	boss_name_label.size = Vector2(200, 16)
	boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name_label.add_theme_font_size_override("font_size", 12)
	boss_name_label.add_theme_color_override("font_color", paper)
	boss_bar_container.add_child(boss_name_label)
	boss_bar_bg = ColorRect.new()
	boss_bar_bg.color = ink
	boss_bar_bg.size = Vector2(200, 18)
	boss_bar_bg.position = Vector2(0, 0)
	boss_bar_container.add_child(boss_bar_bg)
	boss_bar_fill = ColorRect.new()
	boss_bar_fill.color = danger
	boss_bar_fill.size = Vector2(200, 18)
	boss_bar_fill.position = Vector2(0, 0)
	boss_bar_container.add_child(boss_bar_fill)

	# --- Dev buttons ---
	dev_win_btn = Button.new()
	dev_win_btn.name = "DevWin"
	dev_win_btn.text = "DEV: Win"
	dev_win_btn.position = Vector2(12, 60)
	dev_win_btn.pressed.connect(func() -> void: dev_boss_win_pressed.emit())
	add_child(dev_win_btn)
	dev_die_btn = Button.new()
	dev_die_btn.name = "DevDie"
	dev_die_btn.text = "DEV: Die"
	dev_die_btn.position = Vector2(12, 86)
	dev_die_btn.pressed.connect(func() -> void: dev_die_pressed.emit())
	add_child(dev_die_btn)
	dev_win_btn.visible = OS.is_debug_build()
	dev_die_btn.visible = OS.is_debug_build()

	# --- Death panel ---
	death_panel = Panel.new()
	death_panel.name = "DeathPanel"
	death_panel.size = Vector2(1280, 720)
	death_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	death_panel.visible = false
	death_panel.add_theme_stylebox_override("panel", _make_chunky_style(Color(0, 0, 0, 0.72), Color.TRANSPARENT))
	add_child(death_panel)

	var death_vbox := VBoxContainer.new()
	death_vbox.position = Vector2(1280 / 2 - 120, 720 / 2 - 100)
	death_vbox.size = Vector2(240, 200)
	death_vbox.add_theme_constant_override("separation", 8)
	death_panel.add_child(death_vbox)

	var death_title := Label.new()
	death_title.text = "ALLAN DIED"
	death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_title.add_theme_font_size_override("font_size", 28)
	death_title.add_theme_color_override("font_color", danger)
	death_title.add_theme_constant_override("shadow_outline_size", 3)
	death_title.add_theme_color_override("font_shadow_color", ink)
	death_vbox.add_child(death_title)

	ad_continue_btn = Button.new()
	ad_continue_btn.text = "Watch ad to continue"
	ad_continue_btn.add_theme_font_size_override("font_size", 14)
	ad_continue_btn.add_theme_stylebox_override("normal", _make_chunky_style(caution, ink))
	ad_continue_btn.add_theme_color_override("font_color", ink)
	ad_continue_btn.pressed.connect(func() -> void: ad_continue_pressed.emit())
	death_vbox.add_child(ad_continue_btn)

	ascend_btn = Button.new()
	ascend_btn.text = "Ascend to Base"
	ascend_btn.add_theme_font_size_override("font_size", 14)
	ascend_btn.add_theme_stylebox_override("normal", _make_chunky_style(paper, ink))
	ascend_btn.add_theme_color_override("font_color", ink)
	ascend_btn.pressed.connect(func() -> void: ascend_pressed.emit())
	death_vbox.add_child(ascend_btn)

	# --- Ascend overlay ---
	ascend_overlay = Panel.new()
	ascend_overlay.name = "AscendOverlay"
	ascend_overlay.size = Vector2(1280, 720)
	ascend_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ascend_overlay.visible = false
	ascend_overlay.add_theme_stylebox_override("panel", _make_chunky_style(Color(0, 0, 0, 0.8), Color.TRANSPARENT))
	add_child(ascend_overlay)

	var ascend_vbox := VBoxContainer.new()
	ascend_vbox.position = Vector2(1280 / 2 - 120, 720 / 2 - 60)
	ascend_vbox.size = Vector2(240, 120)
	ascend_vbox.add_theme_constant_override("separation", 6)
	ascend_overlay.add_child(ascend_vbox)

	var ascend_title := Label.new()
	ascend_title.name = "AscendTitle"
	ascend_title.text = "ASCENDING..."
	ascend_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ascend_title.add_theme_font_size_override("font_size", 22)
	ascend_title.add_theme_color_override("font_color", caution)
	ascend_vbox.add_child(ascend_title)

	var ascend_count := Label.new()
	ascend_count.name = "AscendCount"
	ascend_count.text = "+0 Blobs"
	ascend_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ascend_count.add_theme_font_size_override("font_size", 18)
	ascend_count.add_theme_color_override("font_color", paper)
	ascend_vbox.add_child(ascend_count)

	var ascend_total := Label.new()
	ascend_total.name = "AscendTotal"
	ascend_total.text = "Total: 0"
	ascend_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ascend_total.add_theme_font_size_override("font_size", 14)
	ascend_total.add_theme_color_override("font_color", Color("#9aa0a6"))
	ascend_vbox.add_child(ascend_total)

	# --- Pause overlay ---
	pause_overlay = Panel.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.size = Vector2(1280, 720)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	pause_overlay.add_theme_stylebox_override("panel", _make_chunky_style(Color(0, 0, 0, 0.72), Color.TRANSPARENT))
	add_child(pause_overlay)

	var pause_vbox := VBoxContainer.new()
	pause_vbox.position = Vector2(1280 / 2 - 120, 720 / 2 - 80)
	pause_vbox.size = Vector2(240, 160)
	pause_vbox.add_theme_constant_override("separation", 10)
	pause_overlay.add_child(pause_vbox)

	var pause_title := Label.new()
	pause_title.text = "PAUSED"
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_title.add_theme_font_size_override("font_size", 28)
	pause_title.add_theme_color_override("font_color", paper)
	pause_vbox.add_child(pause_title)

	resume_btn = Button.new()
	resume_btn.text = "RESUME"
	resume_btn.add_theme_font_size_override("font_size", 16)
	resume_btn.add_theme_stylebox_override("normal", _make_chunky_style(caution, ink))
	resume_btn.add_theme_color_override("font_color", ink)
	resume_btn.pressed.connect(func() -> void: _hide_pause())
	pause_vbox.add_child(resume_btn)

	quit_hub_btn = Button.new()
	quit_hub_btn.text = "QUIT TO HUB"
	quit_hub_btn.add_theme_font_size_override("font_size", 16)
	quit_hub_btn.add_theme_stylebox_override("normal", _make_chunky_style(paper, ink))
	quit_hub_btn.add_theme_color_override("font_color", ink)
	quit_hub_btn.pressed.connect(func() -> void:
		_hide_pause()
		quit_to_hub_pressed.emit())
	pause_vbox.add_child(quit_hub_btn)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_hearts(count: int, max_count: int) -> void:
	for i in range(hearts_icons.size()):
		hearts_icons[i].visible = i < max_count
		hearts_icons[i].modulate = Color("#ff3d3d") if i < count else Color("#555555")

func set_timer(text: String) -> void:
	timer_label.text = text

func set_blobs(count: int) -> void:
	blob_label.text = str(count)

func set_xp(level: int, xp: float, xp_max: float) -> void:
	level_label.text = "Lv " + str(level)
	var ratio := clampf(xp / maxf(xp_max, 1.0), 0.0, 1.0)
	xp_fill.size.x = 80.0 * ratio

func show_boss_warning(active: bool) -> void:
	boss_warn.visible = active

func set_boss_health(name: String, hp_ratio: float) -> void:
	boss_name_label.text = name
	boss_bar_fill.size.x = 200.0 * clampf(hp_ratio, 0.0, 1.0)

func show_boss_bar(show: bool) -> void:
	var container := find_child("BossHP", true, false)
	if container:
		container.visible = show

func show_death_panel(ad_used: bool) -> void:
	death_panel.visible = true
	ad_continue_btn.visible = not ad_used

func hide_death_panel() -> void:
	death_panel.visible = false

func show_ascend(title: String, blobs: int, total: int) -> void:
	ascend_overlay.visible = true
	var count_label := ascend_overlay.find_child("AscendCount", true, false) as Label
	var total_label := ascend_overlay.find_child("AscendTotal", true, false) as Label
	var title_label := ascend_overlay.find_child("AscendTitle", true, false) as Label
	if title_label: title_label.text = title
	if count_label: count_label.text = "+%d Blobs" % blobs
	if total_label: total_label.text = "Total: %d" % total

func hide_ascend() -> void:
	ascend_overlay.visible = false

func show_pause() -> void:
	pause_overlay.visible = true
	pause_btn.button_pressed = true

func _hide_pause() -> void:
	pause_overlay.visible = false
	pause_btn.button_pressed = false
	pause_toggled.emit(false)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_chunky_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 3
	s.border_width_top = 3
	s.border_width_right = 3
	s.border_width_bottom = 3
	s.corner_radius_top_left = 14
	s.corner_radius_top_right = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right = 14
	return s

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	return t
