package com.al67x.webview

import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import java.io.File

/**
 * AL67XWebViewPlugin — Android backend for WebViewHost (see
 * src/services/webview_host.gd + addons/webview_mobile/README.md).
 *
 * STATUS: source skeleton only, not compiled/tested in this repo (no
 * Android SDK/NDK in the dev sandbox this was written in). Wraps the
 * platform's own android.webkit.WebView (Chromium-backed on modern
 * devices) per the "auto-detect the native device webview" request.
 *
 * Registers as an Engine singleton named "AL67XWebView" exposing:
 *   load_html_file(res_path: String)
 *   post_message(json: String)
 *   signal ipc_message(message: String)
 * matching exactly what WebViewHost._mount_native_mobile() expects.
 */
class AL67XWebViewPlugin(godot: Godot) : GodotPlugin(godot) {

    private var webView: WebView? = null

    override fun getPluginName(): String = "AL67XWebView"

    override fun getPluginSignals(): Set<SignalInfo> =
        setOf(SignalInfo("ipc_message", String::class.java))

    /** Called from GDScript: AL67XWebView.load_html_file("res://web_ui/hub/index.html") */
    fun load_html_file(resPath: String) {
        runOnUiThread {
            ensureWebView()
            // res:// paths must already be resolved to a real filesystem path
            // by the caller (Godot's ProjectSettings.globalize_path) before
            // reaching here, or exposed via a local content:// bridge —
            // whichever this plugin's Kotlin-side companion helper ends up
            // using. Left as a TODO since it depends on how assets are
            // packaged (APK asset:// vs extracted user:// data dir).
            val fileUrl = "file://" + File(resPath).absolutePath
            webView?.loadUrl(fileUrl)
        }
    }

    fun post_message(json: String) {
        runOnUiThread {
            val escaped = json.replace("\\", "\\\\").replace("'", "\\'")
            webView?.evaluateJavascript(
                "document.dispatchEvent(new CustomEvent('og-message', { detail: '$escaped' }));" +
                    "document.dispatchEvent(new CustomEvent('message', { detail: '$escaped' }));",
                null
            )
        }
    }

    private fun ensureWebView() {
        if (webView != null) return
        val activity = godot.requireActivity()
        val wv = WebView(activity)
        wv.settings.javaScriptEnabled = true
        wv.settings.domStorageEnabled = true
        wv.webViewClient = WebViewClient()
        wv.addJavascriptInterface(IpcBridge(), "ipc")
        webView = wv
        // TODO: actually attach `wv` into the Godot view hierarchy at the
        // WebViewHost Control's screen-space rect (this skeleton doesn't
        // wire layout/sizing yet — needs the same "sync rect on resize"
        // treatment WebViewHost's Web-export path already does).
    }

    /** Exposed to JS as `window.ipc` -> ipc.postMessage(json) */
    inner class IpcBridge {
        @JavascriptInterface
        fun postMessage(message: String) {
            emitSignal("ipc_message", message)
        }
    }
}
