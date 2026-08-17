import AppKit
import SwiftUI
import WebKit

struct WebDashboardView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int
    let focusToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .windowBackgroundColor
        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif
        context.coordinator.load(url, in: webView)
        context.coordinator.reloadToken = reloadToken
        context.coordinator.focusToken = focusToken
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.load(url, in: webView)
        } else if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            webView.reload()
        }

        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            webView.evaluateJavaScript(
                "document.getElementById('event-code')?.focus();"
            )
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var reloadToken = 0
        var focusToken = 0

        func load(_ url: URL, in webView: WKWebView) {
            loadedURL = url
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let destination = navigationAction.request.url,
                  let loadedURL,
                  destination.host != loadedURL.host else {
                decisionHandler(.allow)
                return
            }

            if destination.scheme == "http" || destination.scheme == "https" {
                NSWorkspace.shared.open(destination)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}
