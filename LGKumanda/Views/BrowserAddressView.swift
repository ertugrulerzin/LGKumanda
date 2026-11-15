import SwiftUI

struct BrowserAddressView: View {
    @EnvironmentObject private var client: TVClient
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var sending = false
    @State private var failure: String?
    @State private var mirroring: URL?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Adres ya da aranacak kelimeleri yaz. Sayfa hem TV'de hem burada açılır; bağlantılara telefonda dokun, TV aynı sayfayı açar. TV'de işaretçi gerekmez.")
                    .font(.body).padding(.top, 20)
                Label(client.selected?.name ?? "Önce bir TV'ye bağlan", systemImage: "tv")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.background)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let failure { Text(failure).font(.footnote).foregroundStyle(.red) }
                        HStack(spacing: 10) {
                            TextField("Adres veya Google araması", text: $address)
                                .keyboardType(.webSearch).textContentType(.URL)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focused).submitLabel(.go).onSubmit { open() }
                                .padding(14).background(Theme.background, in: RoundedRectangle(cornerRadius: 16))
                                .accessibilityIdentifier("browserAddressInput")
                            PasteButton(payloadType: String.self) { values in
                                if let value = values.first { address = value; failure = nil }
                            }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).accessibilityLabel("Adres veya arama yapıştır")
                        }
                        Button(action: open) {
                            HStack {
                                if sending { ProgressView().tint(.white) }
                                Text(sending ? "Gönderiliyor…" : isSearch ? "Google'da ara" : "TV'de aç").fontWeight(.semibold)
                                Image(systemName: isSearch ? "magnifyingglass" : "arrow.up.right")
                            }.frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent)
                            .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending || client.state != .connected)
                    }.padding(16).background(Theme.surface)
                }
                .navigationTitle("Web adresi").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
                .onAppear { focused = true }
                .onChange(of: address) { _, _ in failure = nil }
                .navigationDestination(item: $mirroring) { url in PhoneBrowserView(start: url) }
        }
    }
    private var isSearch: Bool { (try? BrowserAddress.target(address))?.isSearch ?? false }
    private func open() {
        guard !sending else { return }
        do {
            let target = try BrowserAddress.target(address)
            failure = nil; sending = true
            Task {
                defer { sending = false }
                do {
                    try await client.openBrowser(target.url)
                    focused = false
                    mirroring = target.url
                } catch { failure = error.localizedDescription }
            }
        } catch { failure = error.localizedDescription }
    }
}
