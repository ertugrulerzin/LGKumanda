import AppKit
import SwiftUI
import WebKit

@main
struct YakalaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Yakala") {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowToolbarStyle(.unifiedCompact)
    }
}

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                AddressBar(browser: model.browser)
                Divider()
                ZStack {
                    WebViewHost(webView: model.browser.webView)
                    if model.browser.address.isEmpty {
                        StartHint()
                    }
                }
            }
            .frame(minWidth: 560)

            Sidebar(model: model)
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)
        }
    }
}

struct StartHint: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Videonun olduğu sayfayı aç")
                .font(.title3.weight(.semibold))
            Text("Adres çubuğuna sayfa adresini yaz ve videoyu oynat.\nBulunan videolar sağda listelenir.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct AddressBar: View {
    @Bindable var browser: BrowserModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!browser.canGoBack)
                .help("Geri")
            Button { browser.webView.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!browser.canGoForward)
                .help("İleri")
            Button {
                if browser.isLoading { browser.webView.stopLoading() } else { browser.webView.reload() }
            } label: {
                Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(browser.isLoading ? "Durdur" : "Yenile")

            TextField("Adres veya arama", text: $browser.address)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { browser.go() }

            AdBlockButton(blocker: browser.adBlocker) { browser.webView.reload() }

            Button("") { focused = true }
                .keyboardShortcut("l", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            if browser.isLoading {
                ProgressView().progressViewStyle(.linear).controlSize(.mini).offset(y: 6)
            }
        }
        .onAppear { focused = true }
    }
}

struct Sidebar: View {
    @Bindable var model: AppModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Bulunanlar (\(model.visibleDetected.count))").tag(0)
                Text("İndirmeler (\(model.downloads.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()

            if tab == 0 {
                if model.visibleDetected.isEmpty {
                    EmptyNote(
                        icon: "film",
                        text: "Henüz video bulunamadı.\nSayfadaki videoyu oynatmayı ya da sayfayı yenilemeyi dene."
                    )
                } else {
                    List(model.visibleDetected) { item in
                        DetectedRow(item: item) {
                            model.download(item)
                            tab = 1
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                if model.downloads.isEmpty {
                    EmptyNote(icon: "tray", text: "İndirme yok.\nDosyalar İndirilenler klasörüne kaydedilir.")
                } else {
                    let stopped = model.downloads.filter {
                        if case .failed = $0.state { return true }
                        return $0.state == .paused
                    }
                    if !stopped.isEmpty {
                        HStack {
                            Text("\(stopped.count) indirme bekliyor").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Tümünü sürdür") { model.resumeAll() }.controlSize(.small)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    List(model.downloads) { item in
                        DownloadRow(item: item, model: model)
                    }
                    .listStyle(.inset)
                }
            }
        }
    }
}

struct EmptyNote: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title).foregroundStyle(.tertiary)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary).font(.callout)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Badge: View {
    let text: String
    var color: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }
}

struct DetectedRow: View {
    @Bindable var item: DetectedMedia
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Badge(text: item.kind.badge)
                if item.isLive { Badge(text: "CANLI", color: .red) }
                Text(item.title).lineLimit(1).truncationMode(.middle)
            }
            Text(item.url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(item.url.absoluteString)

            switch item.status {
            case .probing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("İnceleniyor…").font(.caption).foregroundStyle(.secondary)
                }
            case .failed(let msg):
                Text(msg).font(.caption).foregroundStyle(.red)
            case .ready:
                if !item.summary.isEmpty {
                    Text(item.summary).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if item.variants.count > 1 {
                        Picker("Kalite", selection: $item.selected) {
                            ForEach(item.variants, id: \.self) { v in
                                Text(v.label).tag(Optional(v))
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: 180)
                    }
                    if !item.subtitleTracks.isEmpty {
                        Picker("Altyazı", selection: $item.subtitleSelection) {
                            Text("Tüm altyazılar").tag("all")
                            Text("Altyazısız").tag("none")
                            Divider()
                            ForEach(item.subtitleTracks, id: \.self) { r in
                                Text(r.name ?? r.language ?? "Altyazı").tag(r.url?.absoluteString ?? "")
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: 140)
                    }
                    Spacer()
                    Button(item.isLive ? "Kaydet" : "İndir", action: onDownload)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Adresi kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
            }
        }
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { model.remove(item) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Listeden kaldır")
            }

            switch item.state {
            case .running, .muxing:
                if let p = item.progress, item.state == .running {
                    ProgressView(value: p).controlSize(.small)
                } else {
                    ProgressView().progressViewStyle(.linear).controlSize(.small)
                }
            case .failed(let msg):
                Text(msg).font(.caption).foregroundStyle(.red)
            default:
                EmptyView()
            }

            HStack {
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                actions.controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var actions: some View {
        switch item.state {
        case .running:
            if item.isLive {
                Button("Kaydı bitir") { model.finishLive(item) }
            } else {
                Button("Duraklat") { model.pause(item) }
            }
        case .paused:
            Button("Devam et") { model.start(item) }
        case .failed:
            Button("Tekrar dene") { model.start(item) }
        case .done(let url):
            Button("Finder'da göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Aç") { NSWorkspace.shared.open(url) }
        case .muxing:
            EmptyView()
        }
    }
}

struct AdBlockButton: View {
    @Bindable var blocker: AdBlocker
    let reload: () -> Void
    @State private var open = false

    private var siteAllowed: Bool { blocker.isAllowed(blocker.currentHost) }
    private var active: Bool { blocker.enabled && !siteAllowed }

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: active ? "shield.lefthalf.filled" : "shield.slash")
                .foregroundStyle(active ? Color.green : Color.secondary)
        }
        .help("Reklam engelleyici")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { blocker.enabled }, set: { blocker.enabled = $0; reload() })) {
                    Text("Reklam engelleyici").font(.headline)
                }
                .toggleStyle(.switch)

                if let host = blocker.currentHost {
                    Toggle(isOn: Binding(get: { !siteAllowed }, set: { _ in blocker.toggleCurrentSite(); reload() })) {
                        Text("\(host) için açık").lineLimit(1).truncationMode(.middle)
                    }
                    .disabled(!blocker.enabled)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    if blocker.isUpdating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Filtre listeleri güncelleniyor…")
                        }
                    } else if blocker.ruleCount > 0 {
                        Text("\(blocker.ruleCount.formatted()) kural etkin")
                    } else {
                        Text("Filtre listeleri henüz yüklenmedi")
                    }
                    if let date = blocker.lastUpdate {
                        Text("Son güncelleme: \(date.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    Text(AdBlocker.sources.map(\.name).joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    if let error = blocker.error {
                        Text(error).foregroundStyle(.red)
                    }
                }
                .font(.caption)

                HStack {
                    Text("Pop-up pencereler de engellenir.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Güncelle") { Task { await blocker.update(); reload() } }
                        .disabled(blocker.isUpdating)
                        .controlSize(.small)
                }
            }
            .padding(14)
            .frame(width: 300)
        }
    }
}
