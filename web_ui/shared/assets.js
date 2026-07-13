/**
 * assets.js — resolves a relative asset path (e.g.
 * "../../assets/sprites/allan/frames/player_idle0.png") to whatever the
 * current backend needs:
 *   - Desktop/dev browser: the plain relative path works as-is (this is
 *     how every screen in this repo was actually visually verified).
 *   - Web export: `webview_host.gd`'s `_mount_web_overlay` inlines HTML/
 *     CSS/JS at load time but can't rewrite JS-computed paths (e.g.
 *     allan_sheet.js building a sheet path per-tier at runtime) — those
 *     call `OGAssets.resolve()` instead, which round-trips through the
 *     synchronous `window.__og_resolve_asset` JS<->GDScript bridge
 *     (base64 data URI) that webview_host.gd registers for exactly this.
 *   - Android/iOS native plugin: not yet exercised; falls back to the
 *     plain relative path like desktop until a real need is found.
 */
const OGAssets = (() => {
  function resolve(path) {
    if (window.__og_resolve_asset) {
      const uri = window.__og_resolve_asset(path);
      if (uri) return uri;
    }
    return path;
  }
  return { resolve };
})();

window.OGAssets = OGAssets;
