import SwiftUI

enum LibraryKind {
    case apps, inputs, channels
    var title: String { switch self { case .apps: return "Uygulamalar"; case .inputs: return "Girişler"; case .channels: return "Kanallar" } }
    var symbol: String { switch self { case .apps: return "square.grid.2x2"; case .inputs: return "cable.connector"; case .channels: return "tv" } }
}

struct LibraryView: View {
    @EnvironmentObject private var client: TVClient
    @EnvironmentObject private var shortcuts: ShortcutStore
    @Environment(\.dismiss) private var dismiss
    let kind: LibraryKind
    @State private var search = ""
    @State private var loading = false
    @State private var operationError: String?
    private var items: [TVItem] { switch kind { case .apps: return client.apps; case .inputs: return client.inputs; case .channels: return client.channels } }
    private var filtered: [TVItem] { search.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.detail.contains(search) } }
    var body: some View {
        NavigationStack {
            List {
                if client.state != .connected {
                    ContentUnavailableView("Önce TV'ye bağlan", systemImage: "wifi.slash", description: Text("Cihazlar bölümünden televizyonunu ekle veya yeniden bağlan."))
                } else if loading && items.isEmpty {
                    HStack { Spacer(); ProgressView("TV'den alınıyor…"); Spacer() }.padding(.vertical, 40)
                } else if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "\(kind.title) henüz alınamadı" : "Sonuç bulunamadı", systemImage: kind.symbol,
                                           description: Text(search.isEmpty ? "Listeyi yenile. TV bu özelliği desteklemiyor olabilir." : "Başka bir ad veya kanal numarası dene."))
                } else {
                    ForEach(filtered) { item in
                        HStack {
                            Button { activate(item) } label: {
                                HStack(spacing: 14) {
                                    if kind == .channels {
                                        Text(item.detail).font(.headline).monospacedDigit().frame(minWidth: 38).foregroundStyle(Theme.accent)
                                    } else { Image(systemName: kind.symbol).foregroundStyle(Theme.accent).frame(width: 32) }
                                    Text(item.title).foregroundStyle(.primary)
                                    Spacer()
                                }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel(item.title)
                            if kind != .channels {
                                let candidate = shortcut(for: item)
                                let pinned = shortcuts.items(for: client.selected?.id).contains { $0.id == candidate.id }
                                Button {
                                    guard let tv = client.selected else { return }
                                    if pinned { shortcuts.remove(candidate.id, tv: tv.id) }
                                    else { shortcuts.put(candidate, tv: tv.id) }
                                } label: { Image(systemName: pinned ? "star.fill" : "star").frame(width: 44, height: 44) }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("\(item.title) kısayolunu \(pinned ? "kaldır" : "ekle")")
                            }
                        }
                    }
                }
            }
            .navigationTitle(kind.title)
            .alert("İşlem tamamlanamadı", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
                Button("Tamam", role: .cancel) { operationError = nil }
            } message: { Text(operationError ?? "") }
            .searchable(text: $search, prompt: kind == .channels ? "Kanal ara" : "Adına göre ara")
            .refreshable { await reload() }
            .toolbar {
                if kind == .inputs { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Listeyi yenile").disabled(loading || client.state != .connected)
                }
            }
        }
    }
    private func reload() async { loading = true; defer { loading = false }; await client.refreshLibrary() }
    private func shortcut(for item: TVItem) -> TVShortcut {
        kind == .inputs ? TVShortcut(kind: .input, targetID: item.id, title: item.title) : TVShortcut.fromApp(item, inputs: client.inputs)
    }
    private func activate(_ item: TVItem) {
        Task {
            do {
                switch kind {
                case .apps: try await client.activate(shortcut(for: item))
                case .channels: _ = try await client.request("tv/openChannel", ["channelId": item.id])
                case .inputs: try await client.switchInput(item.id); dismiss()
                }
            } catch {
                operationError = error.localizedDescription
            }
        }
    }
}
