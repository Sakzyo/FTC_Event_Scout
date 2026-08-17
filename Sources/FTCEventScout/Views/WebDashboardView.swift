import AppKit
import SwiftUI
import WebKit

struct WebDashboardView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int
    let eventCode: String
    let eventLoadToken: Int

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
        context.coordinator.eventLoadToken = eventLoadToken
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.load(url, in: webView)
        } else if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            webView.reload()
        }

        if context.coordinator.eventLoadToken != eventLoadToken {
            context.coordinator.eventLoadToken = eventLoadToken
            context.coordinator.loadEvent(eventCode, in: webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var reloadToken = 0
        var eventLoadToken = 0

        func load(_ url: URL, in webView: WKWebView) {
            loadedURL = url
            webView.load(URLRequest(url: nativeDashboardURL(from: url), cachePolicy: .reloadIgnoringLocalCacheData))
        }

        func loadEvent(_ eventCode: String, in webView: WKWebView) {
            guard let data = try? JSONEncoder().encode([eventCode]),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            let script = """
                (() => {
                    const code = (\(json))[0];
                    const input = document.getElementById('event-code');
                    if (!input) return;
                    input.value = code;
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    const form = document.getElementById('event-form');
                    if (form?.requestSubmit) form.requestSubmit();
                    else document.getElementById('load-event-button')?.click();
                })();
                """
            webView.evaluateJavaScript(script)
        }

        private func nativeDashboardURL(from url: URL) -> URL {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url
            }
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "native", value: "1"))
            components.queryItems = queryItems
            return components.url ?? url
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            webView.evaluateJavaScript("document.documentElement.classList.add('native-shell');")
        }
    }
}
