extends Node
## CefManager — owns the single required `GDCEF` node for the whole
## project (gdcef's own docs: "You only need a single gdCEF node"). Every
## desktop WebViewHost asks this for a browser instead of creating its own
## GDCEF, since a second one would be invalid.
##
## Backend: gdcef (Chromium Embedded Framework), see cef_artifacts/ +
## https://github.com/Lecrapouille/gdcef. Chosen after `godot_wry`
## (WebKitGTK-based) proved to crash unfixably on this dev machine —
## gdcef bundles its own self-contained Chromium runtime instead of
## depending on the system's WebKitGTK, so it doesn't hit that class of
## bug at all.
##
## Renders browsers OFF-SCREEN into a texture (unlike godot_wry, which
## rendered as a native overlay window) — WebViewHost displays that
## texture on a TextureRect and manually forwards input events, since
## gdcef doesn't do that automatically.

var ready_ok := false
var _cef: Object = null


func _ready() -> void:
	if not ClassDB.class_exists("GDCEF"):
		push_warning("CefManager: GDCEF class not found (cef_artifacts/ missing or platform unsupported).")
		return
	_cef = ClassDB.instantiate("GDCEF")
	add_child(_cef)
	var ok: bool = _cef.initialize({
		"locale": "en-US",
		"log_severity": "warning",
	})
	if not ok:
		push_warning("CefManager: GDCEF.initialize() failed: %s" % _cef.get_error())
		return
	ready_ok = true


## Creates a new browser tab rendering into `texture_rect`. Returns the
## GdBrowserView node (a child of this manager, per gdcef's own model) or
## null if CEF isn't available/initialized.
func create_browser(url: String, texture_rect: TextureRect, settings: Dictionary = {}) -> Object:
	if not ready_ok:
		return null
	return _cef.create_browser(url, texture_rect, settings)


func _exit_tree() -> void:
	if _cef != null and is_instance_valid(_cef):
		_cef.shutdown()
