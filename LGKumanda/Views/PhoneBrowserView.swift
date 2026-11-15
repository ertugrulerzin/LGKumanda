import SwiftUI
import WebKit

/// Shows the page on the phone; every page the user opens here is also opened in the TV browser,
/// so links are picked on the phone and the TV never needs its pointer.
struct PhoneBrowserView: View {
    @EnvironmentObject private var client: TVClient
    let start: URL
    @State private var page = PhoneBrowserPage()
    /// Why the TV touch pad is open; nil when closed.
    @State private var touchPad: TouchPadReason?
    var body: some View {
        PhoneWebView(start: start, page: page, mediaBlocked: {
            if touchPad == nil { touchPad = .videos }
        }) { url in
            if !page.isPresentingPlayer { page.forward(url, client:client) }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tv").foregroundStyle(.secondary)
                Text(page.forwardingFailure ?? (page.forwarding ? "Sayfa TV'ye gönderiliyor…" : "Bağlantıyı telefonda seç. Video için Videolar düğmesini kullan.")).font(.footnote)
                    .foregroundStyle(page.forwardingFailure == nil ? Color.secondary : Color.red).lineLimit(3)
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 8).background(Theme.surface)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing:4) {
                HStack(spacing:8) {
                    Button { page.webView?.goBack() } label: { Image(systemName:"chevron.backward").frame(width:44,height:44) }
                        .disabled(!page.canGoBack).accessibilityLabel("Telefonda geri")
                    Button { page.webView?.goForward() } label: { Image(systemName:"chevron.forward").frame(width:44,height:44) }
                        .disabled(!page.canGoForward).accessibilityLabel("Telefonda ileri")
                    Spacer(minLength:8)
                    Button { touchPad = .videos } label: {
                        Label(page.catalog.videos.isEmpty ? "Videolar" : "Videolar (\(page.catalog.videos.count))",systemImage:"play.rectangle")
                            .font(.subheadline).frame(minHeight:44)
                    }.accessibilityIdentifier("webVideos")
                    Button { touchPad = .button } label: { Image(systemName:"cursorarrow.rays").frame(width:44,height:44) }
                        .disabled(!client.pointerReady).accessibilityLabel("TV'de dokunmatik")
                }
                HStack(spacing:8) {
                    Text("TV").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength:0)
                    browserKey(.left,"chevron.left","TV'de sola")
                    browserKey(.up,"chevron.up","TV'de yukarı")
                    Button { client.key(.enter) } label: { Text("OK").font(.subheadline.weight(.semibold)).frame(minWidth:44,minHeight:44) }
                        .disabled(!client.pointerReady).accessibilityLabel("TV'de OK")
                    browserKey(.down,"chevron.down","TV'de aşağı")
                    browserKey(.right,"chevron.right","TV'de sağa")
                }.buttonStyle(.bordered)
            }.padding(.horizontal,12).padding(.vertical,6).background(Theme.surface)
        }
        .sheet(item: $touchPad, onDismiss: { client.stopPointerMotion() }) { reason in
            if reason == .videos {
                WebVideoSheet(page:page)
                    .onAppear { page.isPresentingPlayer = true }
                    .onDisappear { page.isPresentingPlayer = false }
            }
            else { TVTouchPadSheet() }
        }
        .navigationTitle(page.title.isEmpty ? "Web" : page.title).navigationBarTitleDisplayMode(.inline)
        .onDisappear { page.cancelForwarding() }
    }
    private func browserKey(_ key: RemoteKey, _ symbol: String, _ title: String) -> some View {
        Button { client.key(key) } label: { Image(systemName:symbol).frame(minWidth:36,minHeight:36) }
            .disabled(!client.pointerReady).accessibilityLabel(title)
    }
}

enum TouchPadReason: Identifiable { case button, videos; var id: Self { self } }

/// Temporary mouse pad for things only the TV can do, such as a Cloudflare "verify you are human" box.
struct TVTouchPadSheet: View {
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

@MainActor @Observable final class PhoneBrowserPage {
    weak var webView: WKWebView?
    var title = ""
    var canGoBack = false
    var canGoForward = false
    var url: URL?
    let catalog = WebVideoCatalog()
    var isPresentingPlayer = false
    var forwarding = false
    var forwardingFailure: String?
    @ObservationIgnored private(set) var forwardingTask: Task<Void,Never>?
    @ObservationIgnored private var forwardToken = UUID()

    func forward(_ url: URL, client: TVClient) {
        let token = UUID(); forwardToken = token
        let previous = forwardingTask
        forwarding = true; forwardingFailure = nil
        forwardingTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.forwardToken == token, !Task.isCancelled else { return }
            defer { if self.forwardToken == token { self.forwarding = false } }
            do { try await client.openBrowser(url) }
            catch { if self.forwardToken == token { self.forwardingFailure = error.localizedDescription } }
        }
    }
    func cancelForwarding() {
        forwardToken = UUID(); forwardingTask?.cancel(); forwardingTask = nil; forwarding = false
    }
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
        configuration.userContentController.addUserScript(WKUserScript(source: WebVideoDiscovery.script, injectionTime:.atDocumentStart, forMainFrameOnly:false))
        configuration.userContentController.add(context.coordinator, name:"mediaPlay")
        configuration.userContentController.add(context.coordinator, name:"videoSource")
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
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "videoSource")
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: PhoneWebView
        var sent: URL?
        var firstLoad = true
        var lastMediaBlock = Date.distantPast
        init(_ parent: PhoneWebView) { self.parent = parent }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.webView === parent.page.webView else { return }
            if message.name == "videoSource" {
                parent.page.catalog.receive(message.body)
                return
            }
            guard Date().timeIntervalSince(lastMediaBlock) > 3 else { return }
            lastMediaBlock = Date()
            parent.mediaBlocked()
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = action.request.url?.scheme?.lowercased() ?? ""
            if [.linkActivated,.backForward].contains(action.navigationType),
               action.targetFrame?.isMainFrame != false, ["http","https"].contains(scheme),
               let url = action.request.url, url != sent {
                sent = url
                parent.openOnTV(url)
            }
            decisionHandler(["http", "https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.page.catalog.reset()
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { refresh(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { firstLoad = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { firstLoad = false }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            refresh(webView)
            let initial = firstLoad
            firstLoad = false
            guard let url = webView.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url != sent else { return }
            sent = url
            if initial { return } // The TV follows the initial page's redirects itself.
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
            parent.page.url = webView.url
            parent.page.canGoBack = webView.canGoBack
            parent.page.canGoForward = webView.canGoForward
        }
    }
}
