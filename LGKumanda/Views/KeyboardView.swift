import SwiftUI

struct KeyboardView: View {
    @EnvironmentObject private var client: TVClient
    @EnvironmentObject private var box: BoxClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    var isSheet = true
    @State private var text = ""
    @State private var sending = false
    @State private var result: String?
    @State private var failure: String?
    @State private var browserAddress = false
    @FocusState private var focused: Bool
    @AppStorage("pointerSensitivity") private var sensitivity = 0.8
    @AppStorage("cursorless") private var cursorless = true
    private var connected: Bool { client.state == .connected }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Text(client.selected?.name ?? "Önce Cihazlar'dan TV ekle").lineLimit(1)
                        Spacer()
                        Label(client.connectionLabel, systemImage: connected ? "checkmark.circle.fill" : "wifi.slash")
                            .foregroundStyle(connected ? Theme.accent : .secondary)
                    }.font(.caption)
                    if client.isHDMIActive {
                        Text("HDMI kutusunda yön tuşlarını kullan. TV'nin metin klavyesi ve fare imleci kutuya aktarılmaz.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else { PointerModePicker() }
                    TouchPad(forceCursorless: client.isHDMIActive).frame(height: focused ? (textSize.isAccessibilitySize ? 210 : 148) : 240)
                        .disabled(!connected || !(client.pointerReady || box.handles(foregroundAppID: client.foregroundAppID)))
                    if !focused {
                        if cursorless || client.isHDMIActive {
                            Label("İmleci oynatmadan gezin", systemImage: "pawprint")
                                .font(.subheadline.weight(.medium))
                            Text("Kaydırmalar yön tuşu, dokunuşlar OK olarak gönderilir. Fare moduna istediğin zaman geçebilirsin.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Image(systemName: "tortoise")
                                Slider(value: $sensitivity, in: 0.2...2.0, step: 0.1).accessibilityLabel("Fare hassasiyeti")
                                Image(systemName: "hare")
                            }.frame(minHeight: 44)
                            Text("Fare hassasiyeti").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Yazmadan önce TV'de arama veya metin alanını seç. iPhone klavyesindeki mikrofonla dikte de kullanabilirsin.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 12)
            }
            .scrollDismissesKeyboard(.never)
            .background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle("Klavye ve fare").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { browserAddress = true } label: { Image(systemName: "link") }
                        .accessibilityLabel("Web adresi aç").disabled(!connected || client.browserAppID == nil)
                }
                if isSheet { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
                else { ToolbarItem(placement: .topBarTrailing) { Button(focused ? "Gizle" : "Yaz") { focused.toggle() } } }
            }
            .sheet(isPresented: $browserAddress) { BrowserAddressView() }
            .onAppear { focused = connected && !client.isHDMIActive }
            .onDisappear { focused = false; client.stopPointerMotion() }
            .onChange(of: client.isHDMIActive) { _, hdmi in if hdmi { focused = false } }
            .onChange(of: text) { _, _ in result = nil }
        }
    }
    private var composer: some View {
        VStack(spacing: 4) {
            if let failure { Text(failure).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
            if let result { Label(result, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("TV'ye yaz…", text: $text, axis: .vertical)
                    .lineLimit(1...4).padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 16))
                    .focused($focused).submitLabel(.send).onSubmit { send() }
                    .accessibilityIdentifier("tvTextInput")
                Button(action: send) {
                    Group {
                        if sending { ProgressView().tint(.white) }
                        else { Image(systemName: "arrow.up").font(.title3.weight(.semibold)) }
                    }.foregroundStyle(.white).frame(width: 48, height: 48)
                        .background(Theme.accent, in: Circle())
                }.disabled(text.isEmpty || sending || !connected || client.isHDMIActive)
                    .opacity(text.isEmpty || !connected || client.isHDMIActive ? 0.4 : 1)
                    .accessibilityLabel("Metni TV'ye gönder")
            }
            HStack(spacing: 12) {
                Button { command("com.webos.service.ime/sendEnterKey") } label: { Label("TV Enter", systemImage: "return") }
                    .disabled(!connected || client.isHDMIActive)
                Spacer(minLength: 0)
                Button { command("com.webos.service.ime/deleteCharacters", ["count": 1]) } label: { Image(systemName: "delete.left") }
                    .disabled(!connected || client.isHDMIActive).accessibilityLabel("TV'de son karakteri sil")
                Button { focused.toggle() } label: { Image(systemName: focused ? "keyboard.chevron.compact.down" : "keyboard") }
                    .accessibilityLabel(focused ? "iPhone klavyesini gizle" : "iPhone klavyesini aç")
            }.buttonStyle(.borderless).font(.subheadline).frame(minHeight: 44)
        }.padding(.horizontal, 16).padding(.top, 10)
            .background(Theme.surface)
    }
    private func send() {
        guard !text.isEmpty, !sending, connected, !client.isHDMIActive else { return }
        let value = text
        sending = true; failure = nil; result = nil
        Task {
            defer { sending = false }
            do {
                _ = try await client.request("com.webos.service.ime/insertText", ["text": value, "replace": 0])
                // Keep any text entered while awaiting acknowledgement.
                if text.hasPrefix(value) { text = String(text.dropFirst(value.count)) }
                result = "Metin TV'ye gönderildi."
            } catch { failure = error.localizedDescription }
        }
    }
    private func command(_ uri: String, _ payload: [String: Any] = [:]) {
        Task { do { _ = try await client.request(uri, payload); failure = nil } catch { failure = error.localizedDescription } }
    }
}
