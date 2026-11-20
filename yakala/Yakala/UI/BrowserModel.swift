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

    /// Recording mode copies the player's MediaSource buffers; it applies from the next page load.
    var recordingMode = false {
        didSet {
            guard recordingMode != oldValue else { return }
            installScripts()
            if webView.url != nil { webView.reload() }
        }
    }
    var playbackRate = 1.0
    var recordings: [Recording] = []

    weak var app: AppModel?
    @ObservationIgnored private var bridge: WebBridge?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true

        let bridge = WebBridge(model: self)
        self.bridge = bridge
        config.userContentController.add(bridge, name: Sniffer.handlerName)
        webView.navigationDelegate = bridge
        webView.uiDelegate = bridge
        installScripts()
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

    private func installScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        if recordingMode {
            controller.addUserScript(WKUserScript(source: Sniffer.recordingFlag, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        controller.addUserScript(WKUserScript(source: Sniffer.source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        webView.evaluateJavaScript(Sniffer.speedScript(rate))
    }

    // MARK: Recording

    fileprivate func recorderMessage(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "mse-track":
            guard let session = body["session"] as? String, let track = body["track"] as? String else { return }
            let mime = body["mime"] as? String ?? "video/mp4"
            var rec = recordings.first { $0.id == session }
            if rec == nil {
                let pageTitle = (body["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? title
                let r = Recording(id: session, title: pageTitle.isEmpty ? "Kayıt" : pageTitle,
                                  page: (body["page"] as? String).flatMap(URL.init(string:)))
                recordings.insert(r, at: 0)
                rec = r
            }
            rec?.addTrack(track, mime: mime)
        case "mse-data":
            guard let track = body["track"] as? String, let seq = body["seq"] as? Int else { return }
            let data = Data(base64Encoded: body["data"] as? String ?? "") ?? Data()
            recordings.first { $0.owns(track) }?.append(track, seq: seq, data: data)
        case "mse-drm":
            let page = body["page"] as? String
            for r in recordings where r.state == .recording && (page == nil || r.page?.absoluteString == page) {
                r.drm = true
            }
        default:
            break
        }
    }

    func discard(_ recording: Recording) {
        recording.discard()
        recordings.removeAll { $0.id == recording.id }
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
        guard let body = message.body as? [String: Any] else { return }
        if body["type"] != nil {
            MainActor.assumeIsolated { model?.recorderMessage(body) }
            return
        }
        guard let urlString = body["url"] as? String,
              let url = URL(string: urlString) else { return }
        let hint = body["hint"] as? String ?? ""
        let page = (body["page"] as? String).flatMap(URL.init(string:))
        let title = body["title"] as? String ?? ""
        let label = body["label"] as? String ?? ""
        MainActor.assumeIsolated {
            guard let model else { return }
            let pageTitle = title.isEmpty ? model.title : title
            model.app?.report(url: url, hint: hint, page: page ?? model.webView.url, title: pageTitle, label: label)
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
        MainActor.assumeIsolated {
            model?.app?.pageChanged()
            // A new page starts new players; drop empty recordings from the old one.
            model?.recordings.removeAll { $0.state == .recording && $0.bytes == 0 }
            if let rate = model?.playbackRate, rate != 1 { model?.playbackRate = 1 }
        }
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
