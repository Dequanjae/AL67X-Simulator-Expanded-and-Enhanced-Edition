import Foundation
import WebKit

/// AL67XWebViewPlugin — iOS backend for WebViewHost (see
/// src/services/webview_host.gd + addons/webview_mobile/README.md).
///
/// STATUS: source skeleton only, not compiled/tested in this repo (no
/// Xcode/macOS toolchain in the dev sandbox this was written in). Wraps
/// WKWebView — literally Safari's engine — per the "auto-detect the
/// native device webview" request.
///
/// Registers as an Engine singleton named "AL67XWebView" exposing:
///   load_html_file(res_path: String)
///   post_message(json: String)
///   signal ipc_message(message: String)
/// matching exactly what WebViewHost._mount_native_mobile() expects.
///
/// This file is written against Godot's documented iOS plugin shape
/// (a GodotPlugin-style Objective-C++/Swift bridge target); the exact
/// base class/registration macro names depend on the Godot version's iOS
/// plugin template — verify against
/// https://docs.godotengine.org/en/stable/tutorials/platform/ios/ios_plugin.html
/// when wiring this into a real Xcode project.
@objc(AL67XWebViewPlugin)
class AL67XWebViewPlugin: NSObject, WKScriptMessageHandler {

    static let pluginName = "AL67XWebView"

    private var webView: WKWebView?

    /// Called from GDScript: AL67XWebView.load_html_file("res://web_ui/hub/index.html")
    @objc func load_html_file(_ resPath: String) {
        DispatchQueue.main.async {
            self.ensureWebView()
            // TODO: resolve the res:// path to the bundled resource URL
            // (Godot's iOS export bundles res:// under the main bundle) and
            // call webView?.loadFileURL(...). Left unresolved since it
            // depends on the exact export-time resource layout.
            guard let url = Bundle.main.url(forResource: resPath, withExtension: nil) else { return }
            self.webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    @objc func post_message(_ json: String) {
        DispatchQueue.main.async {
            let escaped = json.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "'", with: "\\'")
            let js = """
            document.dispatchEvent(new CustomEvent('og-message', { detail: '\(escaped)' }));
            document.dispatchEvent(new CustomEvent('message', { detail: '\(escaped)' }));
            """
            self.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func ensureWebView() {
        if webView != nil { return }
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "ipc")
        let wv = WKWebView(frame: .zero, configuration: config)
        webView = wv
        // TODO: attach `wv` as a subview of the Godot root view controller,
        // positioned to match the WebViewHost Control's screen-space rect
        // (mirrors the rect-sync treatment WebViewHost's Web-export path
        // already does for its iframe overlay).
    }

    // WKScriptMessageHandler — JS calls window.webkit.messageHandlers.ipc.postMessage(json)
    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard message.name == "ipc", let body = message.body as? String else { return }
        // TODO: emit the "ipc_message" Godot signal via whichever
        // GodotPlugin signal-emission API this Godot version's iOS plugin
        // template exposes (varies by version — see the docs link above).
        NotificationCenter.default.post(name: Notification.Name("AL67XWebViewIpcMessage"), object: body)
    }
}

// JS-side note (mirrors web_ui/shared/bridge.js's transport-detection):
// WKWebView delivers JS->native via
//   window.webkit.messageHandlers.ipc.postMessage(json)
// not window.ipc.postMessage(). The native-mobile shim that
// WebViewHost/bridge.js expects (window.__OG_TRANSPORT__) should inject a
// small JS snippet on page load that aliases:
//   window.__OG_TRANSPORT__ = { postMessage: (m) => window.webkit.messageHandlers.ipc.postMessage(m) };
