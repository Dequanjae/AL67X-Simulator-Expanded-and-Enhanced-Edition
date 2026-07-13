class_name WebViewHost
extends Control
## WebViewHost — the ONE place that decides which webview backend to use on
## the current platform, so every screen (hub, run HUD) just does:
##   var host := WebViewHost.new(); host.page_path = "res://web_ui/hub/index.html"
## and gets JS<->GDScript wired through UIBridge automatically, regardless of
## whether the real backend is gdcef (desktop), a native Android/iOS
## plugin, or a JavaScriptBridge DOM overlay (Web export).
##
## HISTORY: desktop originally used `godot_wry` (WebKitGTK-based). It was
## removed after crashing unfixably on this dev machine even freshly
## rebuilt from source (confirmed via gdb/coredumpctl: abort in glib
## g_type_class_get — an incompatibility between the wry/webkit2gtk-rs
## crates and this system's rolling-release WebKitGTK, not something
## fixable from this project). Desktop now uses **gdcef** (Chromium
## Embedded Framework, see cef_artifacts/ + CefManager autoload) instead —
## it bundles its own self-contained Chromium runtime rather than
## depending on the system's WebKitGTK, so it doesn't hit that bug class
## at all, and it's what actually renders when you press Play in the
## editor now.
##
## gdcef renders OFF-SCREEN into a texture (unlike godot_wry, which drew
## its own native overlay window) — this Control shows that texture on a
## child TextureRect and manually forwards mouse/keyboard input, since
## gdcef doesn't do that automatically the way godot_wry did.
##
## PRACTICAL DEV WORKFLOW for pure HTML/CSS/JS iteration without touching
## Godot at all: open the relevant `web_ui/**/index.html` directly in a
## real desktop browser — `Bridge.send()` just queues/warns with no native
## host attached, and every screen still renders and is clickable. This is
## how every screen in this repo was first visually verified, before
## wiring gdcef up. Good for layout/CSS work; press Play in the editor to
## test the real bridge end-to-end.
##
## IMPORTANT: this script never references a native-extension webview type
## statically, so it still PARSES on every export target regardless of
## which (if any) native plugin is present. All backend calls go through
## Engine.get_singleton()/ClassDB.instantiate() + dynamic (duck-typed)
## method calls.
##
## Current backend support:
##   Desktop (Linux native)  -> gdcef (CEF).                  WORKING — this is what's testable/tested here.
##   Android/iOS             -> addons/webview_mobile plugin. SCAFFOLDED, not yet built/compiled.
##   Web (HTML5 export)      -> JavaScriptBridge DOM overlay.  Exports and boots correctly; UI inlining unverified past engine splash in this environment (see docs/ARCHITECTURE.md).

signal ipc_message(message: String)
signal page_ready()

@export var page_path: String = ""
@export var autoload_on_ready: bool = true

var _backend: Object = null
var _backend_kind := "none"  # "cef" | "android" | "ios" | "web" | "none"


func _ready() -> void:
	if autoload_on_ready and not page_path.is_empty():
		mount(page_path)


## Instantiates the right backend for this platform and loads `path`.
func mount(path: String) -> void:
	page_path = path
	if _backend != null:
		load_url(path)
		return

	if ClassDB.class_exists("GDCEF") and OS.get_name() != "Web":
		_mount_cef_desktop(path)
	elif Engine.has_singleton("AL67XWebView"):
		_mount_native_mobile(path)
	elif OS.get_name() == "Web":
		_mount_web_overlay(path)
	else:
		_mount_placeholder(path)


func post_message(json: String) -> void:
	match _backend_kind:
		"cef":
			_post_message_cef(json)
		"android", "ios":
			_backend.call("post_message", json)
		"web":
			_post_message_web(json)
		_:
			pass  # placeholder backend: nothing listening


func load_url(path: String) -> void:
	match _backend_kind:
		"cef":
			_backend.load_url("file://%s" % ProjectSettings.globalize_path(path))
		"android", "ios":
			_backend.call("load_url", path)
		"web":
			_load_url_web(path)
		_:
			pass


func _on_backend_ipc_message(message: String) -> void:
	ipc_message.emit(message)
	UIBridge.handle_message(message, self)


func _on_backend_page_finished(_url: String) -> void:
	page_ready.emit()


# ---------------------------------------------------------------------------
# Desktop: gdcef (Chromium Embedded Framework). WORKING — this is the
# backend that actually renders when you press Play in the editor now.
# Renders off-screen into a TextureRect (created below as a child) rather
# than drawing its own native window like godot_wry did, so input events
# need manual forwarding — see _gui_input()/_forward_key() below.
# ---------------------------------------------------------------------------

var _cef_texture_rect: TextureRect = null

func _mount_cef_desktop(path: String) -> void:
	_backend_kind = "cef"
	_cef_texture_rect = TextureRect.new()
	_cef_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cef_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cef_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_cef_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cef_texture_rect)

	var url := "file://%s" % ProjectSettings.globalize_path(path)
	var size := get_rect().size
	if size.x < 1 or size.y < 1:
		size = Vector2(1280, 720)  # sane default before the first layout pass
	_backend = CefManager.create_browser(url, _cef_texture_rect, {
		"frame_rate": 60,
		"user_gesture_required": false,
	})
	if _backend == null:
		push_warning("WebViewHost: gdcef browser creation failed, falling back to placeholder.")
		_mount_placeholder(path)
		return
	_backend.resize(size)
	_backend.register_method(Callable(self, "_on_cef_ipc_message"))
	_backend.connect("on_page_loaded", Callable(self, "_on_backend_page_finished"))
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	UIBridge.register_view(self)


## Called from JS as `window.godotMethods._on_cef_ipc_message(jsonString)`
## (bridge.js's gdcef transport calls this exact method name).
func _on_cef_ipc_message(message: Variant) -> void:
	_on_backend_ipc_message(str(message))


func _post_message_cef(json: String) -> void:
	# JS side listens via `window.godotEvents.on("message", ...)`, set up
	# by the bootstrap the gdcef transport in bridge.js installs.
	_backend.emit_js("message", json)


func _gui_input(event: InputEvent) -> void:
	if _backend_kind != "cef" or _backend == null:
		return
	if event is InputEventMouseMotion:
		_backend.set_mouse_moved(int(event.position.x), int(event.position.y))
	elif event is InputEventMouseButton:
		var down: bool = event.pressed
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if down:
					_backend.set_mouse_left_down()
				else:
					_backend.set_mouse_left_up()
			MOUSE_BUTTON_RIGHT:
				if down:
					_backend.set_mouse_right_down()
				else:
					_backend.set_mouse_right_up()
			MOUSE_BUTTON_MIDDLE:
				if down:
					_backend.set_mouse_middle_down()
				else:
					_backend.set_mouse_middle_up()
			MOUSE_BUTTON_WHEEL_UP:
				_backend.set_mouse_wheel_vertical(1, event.shift_pressed, event.ctrl_pressed, event.alt_pressed)
			MOUSE_BUTTON_WHEEL_DOWN:
				_backend.set_mouse_wheel_vertical(-1, event.shift_pressed, event.ctrl_pressed, event.alt_pressed)
		accept_event()
	elif event is InputEventKey:
		_backend.set_key_pressed(event.unicode if event.unicode != 0 else event.keycode,
			event.pressed, event.shift_pressed, event.alt_pressed, event.ctrl_pressed)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _backend_kind == "cef" and _backend != null:
			_backend.resize(get_rect().size)
		elif _backend_kind == "web":
			_sync_web_frame_rect()


# ---------------------------------------------------------------------------
# Android/iOS: native plugin singleton (addons/webview_mobile).
# SCAFFOLDED — see addons/webview_mobile/README.md. The plugin (once built)
# registers itself as an Engine singleton named "AL67XWebView" exposing:
##   load_html_file(res_path: String) -> void
##   post_message(json: String) -> void
##   (emits GDScript signal "ipc_message" via Godot's Android/iOS plugin
##    signal-emission API — see the Kotlin/Swift source for the exact call)
## This path is NOT exercised by any test in this environment (no Android/
## iOS SDK here); wire-up is written to the documented plugin contract but
## unverified end-to-end.
# ---------------------------------------------------------------------------

func _mount_native_mobile(path: String) -> void:
	_backend = Engine.get_singleton("AL67XWebView")
	_backend_kind = "ios" if OS.get_name() == "iOS" else "android"
	if _backend.has_signal("ipc_message"):
		_backend.connect("ipc_message", Callable(self, "_on_backend_ipc_message"))
	_backend.call("load_html_file", path)
	UIBridge.register_view(self)


# ---------------------------------------------------------------------------
# Web (HTML5) export: JavaScriptBridge DOM overlay.
# SCAFFOLDED — the whole game already runs inside a real browser tab on
# this target, so instead of a nested webview we inject a positioned
# <iframe> sibling to the Godot canvas and bridge it with
## JavaScriptBridge.create_callback(). NOT verified in this environment
## (no HTML5 export templates installed here) — written to Godot's
## documented JavaScriptBridge API, exercise on a real Web export build.
# ---------------------------------------------------------------------------

var _web_callback: JavaScriptObject = null
var _web_asset_callback: JavaScriptObject = null
var _web_frame_id := ""
var _web_base_dir := ""

## On Web export, `web_ui/**` is packed inside the .pck along with every
## other res:// file — it is NOT separately fetchable over HTTP the way it
## is when opened directly as a file:// page (which is how every screen in
## this repo was actually visually verified — see the class doc). An
## `<iframe src="res://...">` would just 404. Instead: read the entry
## HTML plus every `<link rel="stylesheet">`/`<script src>` it references
## via FileAccess (works identically packed or not) and inline them all
## into one self-contained document, loaded via `iframe.srcdoc` — no URL
## needed at all. `<img src="...">` tags found in that HTML are resolved
## to base64 data URIs the same way. JS-set image paths (home.js,
## allan_sheet.js, ...) go through the separate `__og_resolve_asset`
## synchronous JS<->GDScript callback registered below instead (see
## web_ui/shared/assets.js) since those can't be caught by a text scan of
## the HTML alone.
##
## NOT LIVE-VERIFIED end-to-end in this environment: a real Web export was
## built and confirmed booting the actual Godot engine/WASM/WebGL pipeline
## correctly (got to the engine's own boot splash), but a live Godot
## editor process was already holding the project directory for the rest
## of this session, so re-exporting to confirm the UI itself renders
## post-splash wasn't done. Please test on a real machine and report back.
func _mount_web_overlay(path: String) -> void:
	_backend_kind = "web"
	_web_frame_id = "og_frame_%d" % get_instance_id()
	_web_base_dir = path.get_base_dir()
	_web_callback = JavaScriptBridge.create_callback(_on_web_message)
	_web_asset_callback = JavaScriptBridge.create_callback(_on_web_resolve_asset)
	# Exposed on the TOP-level window (the one hosting the Godot canvas).
	# The iframe (a separate window context, loaded via srcdoc below) can't
	# see these directly — it reaches them through `window.parent.*`, set
	# up by the bootstrap script injected into the inlined HTML.
	var win := JavaScriptBridge.get_interface("window")
	win.set("ipc_%s" % _web_frame_id, _web_callback)
	win.set("resolve_asset_%s" % _web_frame_id, _web_asset_callback)

	var html := _build_inlined_html(path)
	var bootstrap := """
		<script>
		window.__OG_TRANSPORT__ = {
			postMessage: function(msg) { window.parent['ipc_%s'](msg); }
		};
		window.__og_resolve_asset = function(path) { return window.parent['resolve_asset_%s'](path); };
		</script>
	""" % [_web_frame_id, _web_frame_id]
	html = bootstrap + html

	var escaped := html.replace("\\", "\\\\").replace("`", "\\`")
	JavaScriptBridge.eval("""
		(function() {
			var f = document.createElement('iframe');
			f.id = '%s';
			f.srcdoc = `%s`;
			f.style.position = 'fixed';
			f.style.border = 'none';
			f.style.zIndex = '1000';
			document.body.appendChild(f);
			window.__og_frames = window.__og_frames || {};
			window.__og_frames['%s'] = f;
		})();
	""" % [_web_frame_id, escaped, _web_frame_id], true)
	_sync_web_frame_rect()
	UIBridge.register_view(self)


## Reads `entry_path` and inlines every stylesheet/script it references
## (plus base64-encodes plain `<img src="...">` tags) into one document.
func _build_inlined_html(entry_path: String) -> String:
	var html := _read_text(entry_path)
	var base_dir := entry_path.get_base_dir()

	# <link rel="stylesheet" href="X"> -> <style>...</style>
	var link_re := RegEx.new()
	link_re.compile("<link[^>]*rel=\"stylesheet\"[^>]*href=\"([^\"]+)\"[^>]*>")
	for m in link_re.search_all(html):
		var rel := m.get_string(1)
		if rel.begins_with("http"):
			continue  # Google Fonts etc — left as a real network <link>
		var css_path := base_dir.path_join(rel).simplify_path()
		var css_text := _inline_css_urls(_read_text(css_path), css_path.get_base_dir())
		html = html.replace(m.get_string(0), "<style>%s</style>" % css_text)

	# <script src="X"></script> -> <script>...</script>
	var script_re := RegEx.new()
	script_re.compile("<script[^>]*src=\"([^\"]+)\"[^>]*></script>")
	for m in script_re.search_all(html):
		var rel := m.get_string(1)
		if rel.begins_with("http"):
			continue
		var js_path := base_dir.path_join(rel).simplify_path()
		html = html.replace(m.get_string(0), "<script>%s</script>" % _read_text(js_path))

	# Static <img src="relative/path.png"> -> data URI (JS-set src=
	# assignments are handled separately by __og_resolve_asset).
	var img_re := RegEx.new()
	img_re.compile("<img([^>]*)src=\"([^\"]+)\"")
	for m in img_re.search_all(html):
		var rel := m.get_string(2)
		if rel.begins_with("http") or rel.begins_with("data:"):
			continue
		var img_path := base_dir.path_join(rel).simplify_path()
		var data_uri := _asset_to_data_uri(img_path)
		if not data_uri.is_empty():
			html = html.replace(m.get_string(0), "<img%ssrc=\"%s\"" % [m.get_string(1), data_uri])

	return html


func _inline_css_urls(css_text: String, css_dir: String) -> String:
	var url_re := RegEx.new()
	url_re.compile("url\\(([^)]+)\\)")
	for m in url_re.search_all(css_text):
		var raw := m.get_string(1).strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
		if raw.begins_with("http") or raw.begins_with("data:"):
			continue
		var asset_path := css_dir.path_join(raw).simplify_path()
		var data_uri := _asset_to_data_uri(asset_path)
		if not data_uri.is_empty():
			css_text = css_text.replace(m.get_string(0), "url(%s)" % data_uri)
	return css_text


func _asset_to_data_uri(res_path: String) -> String:
	if not FileAccess.file_exists(res_path):
		return ""
	var file := FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return ""
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var mime := "image/png"
	if res_path.ends_with(".jpg") or res_path.ends_with(".jpeg"):
		mime = "image/jpeg"
	elif res_path.ends_with(".svg"):
		mime = "image/svg+xml"
	return "data:%s;base64,%s" % [mime, Marshalls.raw_to_base64(bytes)]


func _read_text(res_path: String) -> String:
	if not FileAccess.file_exists(res_path):
		push_warning("WebViewHost: missing file for Web inline: %s" % res_path)
		return ""
	var file := FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## JS -> GDScript synchronous asset resolver for paths JS sets at runtime
## (e.g. allan_sheet.js's `img.src = SHEET_SRC`) that a static HTML/CSS
## text scan can't catch. See web_ui/shared/assets.js — screens call
## `OGAssets.resolve(relativePath)` instead of using raw src strings
## directly wherever the path is JS-computed rather than static markup.
func _on_web_resolve_asset(args: Array) -> Variant:
	if args.is_empty():
		return ""
	var rel := str(args[0])
	var full := _web_base_dir.path_join(rel).simplify_path()
	return _asset_to_data_uri(full)


func _on_web_message(args: Array) -> void:
	if args.is_empty():
		return
	var message := str(args[0])
	ipc_message.emit(message)
	UIBridge.handle_message(message, self)


func _post_message_web(json: String) -> void:
	# Delivered as the standard `message` DOM CustomEvent so bridge.js's
	# existing `document.addEventListener("message", ...)` handler (or the
	# `og-message` fallback) picks it up without screen code branching on
	# platform.
	var escaped := json.replace("\\", "\\\\").replace("'", "\\'")
	JavaScriptBridge.eval("""
		(function() {
			var f = window.__og_frames && window.__og_frames['%s'];
			if (f && f.contentWindow) {
				f.contentWindow.dispatchEvent(new CustomEvent('og-message', { detail: JSON.parse('%s') }));
			}
		})();
	""" % [_web_frame_id, escaped], true)


func _load_url_web(path: String) -> void:
	_web_base_dir = path.get_base_dir()
	var html := _build_inlined_html(path)
	var bootstrap := """
		<script>
		window.__OG_TRANSPORT__ = {
			postMessage: function(msg) { window.parent['ipc_%s'](msg); }
		};
		window.__og_resolve_asset = function(path) { return window.parent['resolve_asset_%s'](path); };
		</script>
	""" % [_web_frame_id, _web_frame_id]
	html = bootstrap + html
	var escaped := html.replace("\\", "\\\\").replace("`", "\\`")
	JavaScriptBridge.eval("""
		(function() {
			var f = window.__og_frames && window.__og_frames['%s'];
			if (f) f.srcdoc = `%s`;
		})();
	""" % [_web_frame_id, escaped], true)


func _sync_web_frame_rect() -> void:
	var r := get_global_rect()
	JavaScriptBridge.eval("""
		(function() {
			var f = window.__og_frames && window.__og_frames['%s'];
			if (f) {
				f.style.left = '%dpx'; f.style.top = '%dpx';
				f.style.width = '%dpx'; f.style.height = '%dpx';
			}
		})();
	""" % [_web_frame_id, int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)], true)


# ---------------------------------------------------------------------------
# No backend available on this platform/build (this includes plain desktop
# editor/native runs now that godot_wry is gone — see the class doc for the
# recommended dev workflow: open web_ui/**/index.html directly in a
# desktop browser instead).
# ---------------------------------------------------------------------------

func _mount_placeholder(_path: String) -> void:
	_backend_kind = "none"
	var label := Label.new()
	label.text = "No WebView backend on this platform/build.\nOpen web_ui/**/index.html directly in a desktop browser to iterate on UI.\nSee addons/webview_mobile/README.md for Android/iOS, or export to Web."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(label)
	push_warning("WebViewHost: no backend available (platform=%s)" % OS.get_name())
