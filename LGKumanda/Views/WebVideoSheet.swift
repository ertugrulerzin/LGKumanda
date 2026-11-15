import SwiftUI

/// All actions are explicit taps; page scripts can discover addresses, never command the TV.
struct WebVideoSheet: View {
    @EnvironmentObject private var client: TVClient
    @Environment(\.dismiss) private var dismiss
    let page: PhoneBrowserPage
    @State private var busy = false
    @State private var pending: String?
    @State private var failure: String?
    @State private var notice: String?
    @State private var showPointer = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(client.selected?.name ?? "Önce bir TV'ye bağlan", systemImage:"tv")
                    Text("Sayfadaki videoyu seçip TV oynatıcısında açmayı deneyebilirsin. Oturum isteyen veya korumalı videolar TV tarayıcısında açılmayı gerektirebilir.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("webVideoFailure") }
                    if let notice { Text(notice).accessibilityIdentifier("webVideoNotice") }
                }
                Section("Bulunan video kaynakları") {
                    if page.catalog.videos.isEmpty {
                        VStack(alignment:.leading,spacing:8) {
                            Text("Henüz video bağlantısı bulunmadı").font(.headline)
                            Text("Sayfada videoyu aç veya oynat düğmesine dokun. Bağlantı bulunamazsa aşağıdaki TV kontrollerini kullan.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical,8).accessibilityIdentifier("webVideosEmpty")
                    }
                    ForEach(Array(page.catalog.videos.enumerated()),id:\.element.id) { index, video in
                        VStack(alignment:.leading,spacing:8) {
                            Text(video.title).font(.headline).lineLimit(2)
                            Text("Kaynak \(index + 1) · \(video.format) · \(video.sourceLabel)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Button {
                                run(video.id) {
                                    try await client.openWebVideo(video)
                                    notice = "Video adresi TV'ye gönderildi. Açılmazsa TV tarayıcısında devam et."
                                }
                            } label: {
                                HStack {
                                    if pending == video.id { ProgressView() }
                                    Label("TV oynatıcısında aç",systemImage:"play.tv")
                                }.frame(minHeight:44)
                            }.buttonStyle(.borderedProminent)
                                .disabled(busy || client.state != .connected)
                                .accessibilityIdentifier("openWebVideo.\(index)")
                        }.padding(.vertical,8)
                    }
                }
                Section("TV'de video kontrolü") {
                    if let session = client.webVideoSession {
                        Label(session.video.title,systemImage:"play.rectangle").font(.subheadline)
                        Text("TV oynatıcısına gönderilen video").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("TV tarayıcısındaki oynatıcıyı yön tuşları veya hassas tıklama ile seç. Bu düğmeler TV'ye oynatma komutu gönderir.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing:12) {
                        media(.play,"Oynat","play.fill")
                        media(.pause,"Duraklat","pause.fill")
                        media(.stop,"Durdur","stop.fill")
                    }
                    HStack(spacing:12) {
                        media(.rewind,"Geri sar","backward.fill")
                        media(.fastForward,"İleri sar","forward.fill")
                    }
                    HStack(spacing:12) {
                        Button { run { _ = try await client.request("audio/volumeDown") } } label: {
                            Label("Ses kıs",systemImage:"speaker.wave.1").frame(maxWidth:.infinity,minHeight:44)
                        }
                        Button { run { _ = try await client.request("audio/volumeUp") } } label: {
                            Label("Ses aç",systemImage:"speaker.wave.3").frame(maxWidth:.infinity,minHeight:44)
                        }
                    }.buttonStyle(.bordered).disabled(busy || client.state != .connected)
                }
                Section("TV tarayıcısında devam") {
                    Button { run {
                        guard let url = page.url else { throw TVClient.Failure.message("Sayfa adresi henüz hazır değil.") }
                        try await client.openBrowser(url)
                        notice = "Sayfa TV tarayıcısına gönderildi."
                    } } label: {
                        Label("Bu sayfayı TV tarayıcısında aç",systemImage:"globe").frame(minHeight:44)
                    }.disabled(busy || client.state != .connected || !validPage)
                    Button { showPointer = true } label: {
                        Label("TV'de hassas tıklama",systemImage:"cursorarrow.rays").frame(minHeight:44)
                    }.disabled(!client.pointerReady).accessibilityIdentifier("webVideoPointer")
                    Text("Video adresleri bu uygulamada kalıcı olarak kaydedilmez. TV'nin adresi açabilmesi ve video biçimini desteklemesi gerekir.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Web videoları").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Bitti") { dismiss() } } }
                .sheet(isPresented:$showPointer) { TVTouchPadSheet(playHint:true) }
        }
    }
    private var validPage: Bool { ["http","https"].contains(page.url?.scheme?.lowercased() ?? "") }
    private func media(_ action: MediaAction, _ title: String, _ symbol: String) -> some View {
        Button { run { try await client.controlWebVideo(action) } } label: {
            VStack(spacing:6) { Image(systemName:symbol); Text(title).font(.caption) }
                .frame(maxWidth:.infinity,minHeight:54)
        }.buttonStyle(.bordered).disabled(busy || client.state != .connected)
            .accessibilityLabel("TV'de \(title.lowercased())")
    }
    private func run(_ id: String? = nil, action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; pending = id; failure = nil; notice = nil
        Task { @MainActor in
            defer { busy = false; pending = nil }
            await page.forwardingTask?.value
            do { try await action() }
            catch { failure = error.localizedDescription }
        }
    }
}
