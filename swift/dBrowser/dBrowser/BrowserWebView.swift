import Foundation
import SwiftUI
import WebKit

#if os(macOS)
import AppKit

typealias BrowserViewRepresentable = NSViewRepresentable
#else
import UIKit

typealias BrowserViewRepresentable = UIViewRepresentable
#endif

struct BrowserWebView: BrowserViewRepresentable {
    @Binding var tab: BrowserTab
    let command: BrowserWebCommandRequest?
    let onNavigationUpdate: (BrowserNavigationUpdate) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

#if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView, context: context)
    }
#else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView, context: context)
    }
#endif

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
#if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
#else
        webView.scrollView.contentInsetAdjustmentBehavior = .never
#endif
        return webView
    }

    private func update(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        applyCommandIfNeeded(webView, context: context)
        loadTabIfNeeded(webView, context: context)
    }

    private func applyCommandIfNeeded(_ webView: WKWebView, context: Context) {
        guard let command else { return }
        guard command.tabID == tab.id else { return }
        guard context.coordinator.lastHandledCommandID != command.id else { return }
        context.coordinator.lastHandledCommandID = command.id

        switch command.command {
        case .back:
            if webView.canGoBack {
                webView.goBack()
            }
        case .forward:
            if webView.canGoForward {
                webView.goForward()
            }
        case .reload:
            webView.reload()
        case .stop:
            webView.stopLoading()
        }
    }

    private func loadTabIfNeeded(_ webView: WKWebView, context: Context) {
        guard let url = tab.loadableURL else { return }
        guard context.coordinator.lastRequestedURL != url else { return }
        context.coordinator.lastRequestedURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: BrowserWebView
        var lastRequestedURL: URL?
        var lastHandledCommandID: UUID?

        init(_ parent: BrowserWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            publish(webView: webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            publish(webView: webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            publish(webView: webView, isLoading: false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            publish(webView: webView, isLoading: false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            publish(webView: webView, isLoading: false)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            publish(webView: webView, isLoading: false)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let scheme = url.scheme?.lowercased()
            if scheme == "http" || scheme == "https" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        private func publish(webView: WKWebView, isLoading: Bool) {
            let update = BrowserNavigationUpdate(
                tabID: parent.tab.id,
                urlString: webView.url?.absoluteString,
                title: webView.title,
                isLoading: isLoading,
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward
            )
            DispatchQueue.main.async {
                self.parent.onNavigationUpdate(update)
            }
        }
    }
}
