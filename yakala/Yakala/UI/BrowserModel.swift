import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class BrowserModel {
    let webView: WKWebView
    var address = ""
    var title = ""
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var userAgent: String?
    let adBlocker = AdBlocker()

    weak var app: AppModel?
    @ObservationIgnored private var bridge: WebBridge?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        config.userContentController.addUserScript(
            WKUserScript(source: Sniffer.source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true

        let bridge = WebBridge(model: self)
        self.bridge = bridge
        config.userContentController.add(bridge, name: Sniffer.handlerName)
        webView.navigationDelegate = bridge
        webView.uiDelegate = bridge
        adBlocker.attach(config.userContentController)

        let refresh: (WKWebView) -> Void = { [weak self] _ in
            Task { @MainActor in self?.syncState() }
        }
        observations = [
            webView.observe(\.url) { wv, _ in refresh(wv) },
            webView.observe(\.title) { wv, _ in refresh(wv) },
            webView.observe(\.canGoBack) { wv, _ in refresh(wv) },
            webView.observe(\.canGoForward) { wv, _ in refresh(wv) },
            webView.observe(\.isLoading) { wv, _ in refresh(wv) },
        ]
    }

    private func syncState() {
        if let url = webView.url?.absoluteString, url != "about:blank" { address = url }
        title = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }

    func go() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let url: URL?
        if text.contains(" ") || !text.contains(".") {
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: text)]
            url = c.url
        } else if text.contains("://") {
            url = URL(string: text)
        } else {
            url = URL(string: "https://" + text)
        }
        guard let url else { return }
        if MediaKind.classify(url, hint: "") != nil {
            app?.report(url: url, hint: "", page: nil, title: url.deletingPathExtension().lastPathComponent)
        }
        webView.load(URLRequest(url: url))
    }

    func syncCookies() async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
    }

    fileprivate func fetchUserAgent() {
        guard userAgent == nil else { return }
        webView.evaluateJavaScript("navigator.userAgent") { [weak self] value, _ in
            Task { @MainActor in self?.userAgent = value as? String }
        }
    }
}

/// Delegates for the web view, kept apart so the model is not retained by WebKit.
private final class WebBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    weak var model: BrowserModel?

    init(model: BrowserModel) { self.model = model }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let urlString = body["url"] as? String,
              let url = URL(string: urlString) else { return }
        let hint = body["hint"] as? String ?? ""
        let page = (body["page"] as? String).flatMap(URL.init(string:))
        let title = body["title"] as? String ?? ""
        MainActor.assumeIsolated {
            guard let model else { return }
            let pageTitle = title.isEmpty ? model.title : title
            model.app?.report(url: url, hint: hint, page: page ?? model.webView.url, title: pageTitle)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == true {
            MainActor.assumeIsolated { model?.adBlocker.prepare(for: navigationAction.request.url) }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        MainActor.assumeIsolated { model?.app?.pageChanged() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { model?.fetchUserAgent() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if let mime = navigationResponse.response.mimeType,
           mime.contains("mpegurl") || mime.hasPrefix("video/"),
           let url = navigationResponse.response.url {
            MainActor.assumeIsolated {
                model?.app?.report(url: url, hint: mime, page: nil, title: url.deletingPathExtension().lastPathComponent)
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Pop-up blocker: open new-window links only when the user clicked them,
        // never for window.open() calls a script makes on its own.
        let userClicked = navigationAction.navigationType == .linkActivated || navigationAction.modifierFlags.contains(.command)
        let blocking = MainActor.assumeIsolated { model?.adBlocker.enabled ?? true }
        if navigationAction.targetFrame == nil, userClicked || !blocking {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
