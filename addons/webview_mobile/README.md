# Overvolt Garage — Mobile WebView Plugin (Android + iOS)

## Status: SCAFFOLDED, NOT BUILT/TESTED

Research done while building this UI overhaul:

- `godot_wry` was tried first (it was already installed in the project)
  and then **removed entirely**. Its own README lists Android/iOS/Web as
  "⏳ Planned" (not implemented) — there's an open upstream issue asking
  for Android support (doceazedo/godot_wry#71) — and on this project's
  dev machine even its own unmodified example scene crashed inside
  WebKitGTK's `web_context` init (confirmed via `gdb`/`coredumpctl`: an
  abort in glib `g_type_class_get`, shaped like an ABI mismatch between
  the prebuilt extension and the system's rolling-release webkit2gtk).
  Since this game's real targets are mobile + Web, not a native desktop
  build, keeping a crashing, not-actually-mobile-capable addon around
  wasn't worth it.
- `office-bsmx/godot-webview` (GitHub, ~23 stars, Java) is a real, more
  mature **Android-only** community plugin wrapping `android.webkit.WebView`
  (Chromium-backed on modern devices). Worth evaluating as a drop-in
  Android backend instead of the Kotlin stub below, if you want something
  sooner than finishing this scaffold.
- `moeru-ai/godot-kirie` is a very new (2026), experimental project
  targeting exactly this problem (native Android WebView + iOS WKWebView,
  CBOR IPC) but is pre-alpha/small at the time of writing — worth watching,
  not yet production-ready.
- Nothing currently covers Android **and** iOS **and** Web with one
  actively-maintained, drop-in Godot addon.

## Dev workflow without any native backend (today)

Every screen under `web_ui/` is plain HTML/CSS/JS and was actually
visually verified by opening `web_ui/hub/index.html` directly in a
desktop browser (Chrome/Firefox) rather than through Godot — `bridge.js`
degrades gracefully (queues/warns) with no native host attached, and
every screen still renders and is clickable. Keep using this to iterate
on layout/animation. `WebViewHost` (see `src/services/webview_host.gd`)
shows a placeholder label instead of a blank screen when no backend is
available (plain desktop editor/native runs), specifically pointing back
at this workflow.

The in-engine paths that actually round-trip through `UIBridge` today:
- **Headless GDScript-side testing**: `UIBridge.simulate_message()` /
  `simulate_message_with_reply()` drive the exact same routing real
  screens use without needing any rendered webview at all — see
  `src/dev/fusion_smoke_test.gd` for the pattern.
- **A real Web export**, once one is built (see below) — this is the
  most representative "does the whole thing actually work" test, since
  it's also a real ship target.

## What's here

`src/services/webview_host.gd` (the platform-abstraction layer every screen
uses) already has the calling contract wired for a future native plugin:
it looks for an Engine singleton named **`AL67XWebView`** and expects it to
expose:

```
load_html_file(res_path: String) -> void   # load a local res:// page
post_message(json: String) -> void         # Godot -> JS (arrives as the
                                            # `message` DOM event / og-message
                                            # fallback bridge.js already listens for)
signal ipc_message(message: String)        # JS -> Godot (ipc.postMessage())
```

If you build a plugin (either from the stubs below, or by adapting
`office-bsmx/godot-webview`/`godot-kirie`) that registers itself as an
Engine singleton under that exact name with that exact method/signal
shape, `WebViewHost` picks it up automatically — **no GDScript changes
needed anywhere else in the project.**

- `android/` — Kotlin plugin skeleton using Godot's Android plugin v2
  system, wrapping `android.webkit.WebView`. Requires Android Studio +
  the Godot Android library AAR to actually compile; not attempted in
  this sandbox (no Android SDK/NDK here).
- `ios/` — Swift plugin skeleton using Godot's iOS plugin system, wrapping
  `WKWebView` (this is literally Safari's engine, matching the "auto-detect
  the native device webview" request). Requires Xcode to compile; not
  attempted in this sandbox (no macOS/Xcode here).

## Build steps (once you have the right toolchain)

### Android
1. Open `android/` as a Gradle project (or drop it into an existing Godot
   Android plugin template — see https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html).
2. `./gradlay assembleRelease` produces an `.aar`.
3. Drop the `.aar` + a `.gdap` config (see Godot's Android plugin docs) into
   `res://addons/webview_mobile/android/` and enable it for your Android
   export preset.

### iOS
1. Open `ios/` in Xcode as a Godot iOS plugin target (see
   https://docs.godotengine.org/en/stable/tutorials/platform/ios/ios_plugin.html).
2. Build a static `.xcframework`.
3. Reference it in your iOS export preset's plugin list.

## Known-good fallback path if you want something working sooner

Swap `_mount_native_mobile()` in `webview_host.gd` to call into
`office-bsmx/godot-webview`'s actual exposed API (check their README for
the exact singleton/method names — they differ slightly from the contract
above) for Android specifically, and ship iOS later/behind a feature flag.
The rest of this UI (all of `web_ui/`) doesn't care which backend renders
it, as long as it speaks the `ipc.postMessage()` / `message` event
contract `web_ui/shared/bridge.js` documents.
