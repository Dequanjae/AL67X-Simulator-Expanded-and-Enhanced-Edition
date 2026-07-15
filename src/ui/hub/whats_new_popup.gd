extends Control
## "What's New" popup (spec Section 13): reads the agent-editable
## data/whats_new.json feed on hub load and shows unseen entries since the
## player's last session. Last-seen is tracked LOCALLY in the save (no
## server round-trip). Appending a feed entry is a pure data edit.
##
## Instagram: native Godot can't render the IG embed widget (it's DOM/JS),
## so the button deep-links to the profile. SWAP-POINT (Web export): inject
## docs/instagram_embed.html into the page shell via JavaScriptBridge for a
## true inline embed.

const MAX_ENTRIES := 5
const INSTAGRAM_URL := "https://www.instagram.com/al67x._/"

var _newest_id := ""

@onready var _entries_box: VBoxContainer = $Center/Box/Scroll/EntriesBox
@onready var _ig_button: Button = $Center/Box/IGButton
@onready var _got_it_button: Button = $Center/Box/GotItButton


func _ready() -> void:
	visible = false
	add_to_group("modal_overlay")
	_got_it_button.pressed.connect(_dismiss)
	_ig_button.pressed.connect(func() -> void: OS.shell_open(INSTAGRAM_URL))
	_maybe_show()


func _maybe_show() -> void:
	var feed: Variant = JsonData.load_json("res://data/whats_new.json")
	if not (feed is Dictionary):
		return
	var entries: Array = feed.get("entries", [])
	if entries.is_empty():
		return
	var last_seen := str(SaveService.get_value("meta.whats_new_last_seen", ""))
	_newest_id = str(entries[0].get("id", ""))
	if _newest_id == "" or _newest_id == last_seen:
		return
	var unseen: Array = []
	for entry in entries:
		if str(entry.get("id", "")) == last_seen:
			break
		unseen.append(entry)
		if unseen.size() >= MAX_ENTRIES:
			break
	if unseen.is_empty():
		return
	for entry in unseen:
		_entries_box.add_child(_make_entry(entry))
	visible = true


func _make_entry(entry: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "%s — %s" % [str(entry.get("date", "")), str(entry.get("title", ""))]
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var body := Label.new()
	body.text = str(entry.get("body", ""))
	body.add_theme_font_size_override("font_size", 20)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	return box


func _dismiss() -> void:
	SaveService.set_value("meta.whats_new_last_seen", _newest_id)
	visible = false
