import SwiftUI
import WebKit

/// Shows the page on the phone; every page the user opens here is also opened in the TV browser,
/// so links are picked on the phone and the TV never needs its pointer.
struct PhoneBrowserView: View {
    @EnvironmentObject private var client: TVClient
    let start: URL
    @State private var page = PhoneBrowserPage()
    @State private var failure: String?
    /// Why the TV touch pad is open; nil when closed.
    @State private var touchPad: TouchPadReason?
    var body: some View {
        PhoneWebView(start: start, page: page, mediaBlocked: {
            if touchPad == nil { touchPad = .video }
        }) { url in
            Task {
                do { try await client.openBrowser(url); failure = nil }
                catch { failure = error.localizedDescription }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tv").foregroundStyle(.secondary)
                Text(failure ?? "Dokunduğun bağlantı TV'de açılır. TV doğrulama isterse imleç düğmesine dokun.").font(.footnote)
                    .foregroundStyle(failure == nil ? Color.secondary : Color.red).lineLimit(2)
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 8).background(Theme.surface)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 4) {
                Button { page.webView?.goBack() } label: { Image(systemName: "chevron.backward").frame(width: 44, height: 44) }
                    .disabled(!page.canGoBack).accessibilityLabel("Telefonda geri")
                Button { page.webView?.goForward() } label: { Image(systemName: "chevron.forward").frame(width: 44, height: 44) }
                    .disabled(!page.canGoForward).accessibilityLabel("Telefonda ileri")
                Spacer()
                Button { touchPad = .button } label: { Image(systemName: "cursorarrow.rays").frame(width: 44, height: 44) }
                    .disabled(!client.pointerReady).accessibilityLabel("TV'de dokunmatik")
                Text("TV'de kaydır").font(.caption).foregroundStyle(.secondary)
                Button { client.key(.up) } label: { Image(systemName: "chevron.up").frame(width: 52, height: 44) }
                    .buttonStyle(.bordered).accessibilityLabel("TV sayfasını yukarı kaydır").disabled(!client.pointerReady)
                Button { client.key(.down) } label: { Image(systemName: "chevron.down").frame(width: 52, height: 44) }
                    .buttonStyle(.bordered).accessibilityLabel("TV sayfasını aşağı kaydır").disabled(!client.pointerReady)
            }.padding(.horizontal, 12).padding(.vertical, 6).background(Theme.surface)
        }
        .sheet(item: $touchPad, onDismiss: { client.stopPointerMotion() }) { reason in TVTouchPadSheet(playHint: reason == .video) }
        .navigationTitle(page.title.isEmpty ? "Web" : page.title).navigationBarTitleDisplayMode(.inline)
    }
}

enum TouchPadReason: Identifiable { case button, video; var id: Self { self } }

/// Temporary mouse pad for things only the TV can do, such as a Cloudflare "verify you are human" box.
private struct TVTouchPadSheet: View {
    @EnvironmentObject private var client: TVClient
    @Environment(\.dismiss) private var dismiss
    var playHint = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if playHint {
                    Label("Video telefonda değil TV'de oynatılır. İşaretçiyi TV'deki oynat düğmesine getir ve dokun.", systemImage: "play.tv")
                        .font(.subheadline.weight(.semibold)).accessibilityIdentifier("playOnTVHint")
                }
                Text("İşaretçiyi TV'deki düğmenin ya da güvenlik doğrulaması kutusunun üzerine getir ve dokun. Telefondaki doğrulama TV'ye aktarılmaz; TV'de bir kez yapılması gerekir.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TouchPad(forceMouse: true, quietOverride: false).frame(maxWidth: .infinity).frame(height: 240)
                    .disabled(!client.pointerReady)
                HStack(spacing: 10) {
                    nudge("Sol", "arrow.left", -4, 0)
                    VStack(spacing: 6) { nudge("Yukarı", "arrow.up", 0, -4); nudge("Aşağı", "arrow.down", 0, 4) }
                    nudge("Sağ", "arrow.right", 4, 0)
                    Button { client.pointerMessage("type:click\n\n") } label: {
                        Text("Tıkla").font(.headline).frame(maxWidth: .infinity, minHeight: 64)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("tvClick")
                }.disabled(!client.pointerReady)
                Text("Oklar işaretçiyi küçük adımlarla kaydırır; tam hedeflemek için kullan.").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxHeight: .infinity, alignment: .top).background(Theme.background)
                .navigationTitle("TV'de dokunmatik").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }.presentationDetents([.large])
    }
    private func nudge(_ title: String, _ symbol: String, _ dx: Int, _ dy: Int) -> some View {
        Button { client.jumpPointer(dx: dx, dy: dy) } label: { Image(systemName: symbol).frame(width: 44, height: 29) }
            .buttonStyle(.bordered).buttonRepeatBehavior(.enabled).accessibilityLabel("İşaretçiyi \(title.lowercased()) kaydır")
    }
}

@Observable final class PhoneBrowserPage {
    weak var webView: WKWebView?
    var title = ""
    var canGoBack = false
    var canGoForward = false
}

private struct PhoneWebView: UIViewRepresentable {
    let start: URL
    let page: PhoneBrowserPage
    let mediaBlocked: () -> Void
    let openOnTV: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        // Videos belong on the TV: pause any playback on the phone (all frames, including embedded players) and tell the app.
        let pause = """
        document.addEventListener('play', function (e) {
          var media = e.target; if (!media || !media.pause) return;
          media.pause(); media.muted = true;
          try { window.webkit.messageHandlers.mediaPlay.postMessage(1); } catch (_) {}
        }, true);
        """
        configuration.userContentController.addUserScript(WKUserScript(source: pause, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController.add(context.coordinator, name: "mediaPlay")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.accessibilityIdentifier = "phoneBrowser"
        page.webView = view
        context.coordinator.sent = start
        view.load(URLRequest(url: start))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaPlay")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: PhoneWebView
        var sent: URL?
        var firstLoad = true
        var lastMediaBlock = Date.distantPast
        init(_ parent: PhoneWebView) { self.parent = parent }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard Date().timeIntervalSince(lastMediaBlock) > 3 else { return }
            lastMediaBlock = Date()
            parent.mediaBlocked()
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = action.request.url?.scheme?.lowercased() ?? ""
            decisionHandler(["http", "https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { refresh(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { firstLoad = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { firstLoad = false }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            refresh(webView)
            guard let url = webView.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url != sent else { return }
            sent = url
            if firstLoad { firstLoad = false; return } // the TV already opened the starting page and follows its redirects itself
            parent.openOnTV(url)
        }
        /// Links that would open a new window load in the same view, so the TV still follows.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil { webView.load(action.request) }
            return nil
        }
        private func refresh(_ webView: WKWebView) {
            parent.page.title = webView.title ?? ""
            parent.page.canGoBack = webView.canGoBack
            parent.page.canGoForward = webView.canGoForward
        }
    }
}
