import SwiftUI

struct ShortcutStrip: View {
    @EnvironmentObject private var client: TVClient
    @EnvironmentObject private var shortcuts: ShortcutStore
    @State private var launching: String?
    var body: some View {
        let items = shortcuts.items(for: client.selected?.id)
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        RemoteButton(title: item.title, symbol: item.symbol) {
                            launching = item.id
                            Task {
                                defer { launching = nil }
                                do { try await client.activate(item) } catch { client.error = error.localizedDescription }
                            }
                        }.frame(width: 108)
                            .disabled(client.state != .connected || launching != nil || !available(item))
                            .accessibilityIdentifier("shortcut.\(item.id)")
                            .contextMenu {
                                Button("Kısayolu kaldır", systemImage: "star.slash", role: .destructive) {
                                    if let tv = client.selected { shortcuts.remove(item.id, tv: tv.id) }
                                }
                            }
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityLabel("Ana ekran kısayolları")
        }
    }
    private func available(_ item: TVShortcut) -> Bool {
        (item.kind == .app ? client.apps : client.inputs).contains { $0.id == item.targetID }
    }
}

struct ShortcutEditor: View {
    @EnvironmentObject private var client: TVClient
    @EnvironmentObject private var shortcuts: ShortcutStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var naming: TVShortcut?
    @State private var title = ""
    @State private var renaming = false
    private var items: [TVShortcut] { shortcuts.items(for: client.selected?.id) }
    private var apps: [TVItem] { client.apps.filter { !$0.id.hasPrefix("com.webos.app.hdmi") && matches($0) } }
    private var inputs: [TVItem] { client.inputs.filter(matches) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if items.isEmpty { Text("Henüz kısayol yok. Aşağıdan uygulama veya HDMI girişi ekle.").foregroundStyle(.secondary) }
                    ForEach(items) { item in
                        Button { rename(item) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).foregroundStyle(Theme.accent).frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).foregroundStyle(.primary)
                                    Text(item.kind == .input ? "HDMI girişi" : "TV uygulaması").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("editShortcut.\(item.id)")
                    }.onDelete { offsets in
                        guard let tv = client.selected else { return }
                        let ids = offsets.map { items[$0].id }
                        for id in ids { shortcuts.remove(id, tv: tv.id) }
                    }.onMove { source, destination in
                        guard let tv = client.selected else { return }
                        var list = items; list.move(fromOffsets: source, toOffset: destination)
                        shortcuts.reorder(list.map(\.id), tv: tv.id)
                    }
                } header: { Text("Ana ekranda") } footer: {
                    Text("Adını değiştirmek için kısayola dokun. Silmek için sola kaydır; sıralamak için Düzenle'yi kullan.")
                }
                if client.state == .connected {
                    Section("TV uygulamaları") {
                        ForEach(apps) { item in addRow(TVShortcut.fromApp(item, inputs: client.inputs)) }
                        if apps.isEmpty { Text("Uygulama bulunamadı. Listeyi yenileyebilirsin.").foregroundStyle(.secondary) }
                    }
                    Section {
                        ForEach(inputs) { item in
                            addRow(TVShortcut(kind: .input, targetID: item.id, title: item.title), detail: item.detail)
                        }
                    } header: { Text("HDMI girişleri") } footer: {
                        Text("Tivibu veya TVP kutusunun bağlı olduğu girişi seç. Kısayola istediğin adı verebilirsin.")
                    }
                    Section {
                        Button("Önerilen kısayolları geri getir") {
                            if let tv = client.selected { shortcuts.restore(tv: tv.id, apps: client.apps, inputs: client.inputs) }
                        }.frame(minHeight: 44).disabled(!client.libraryReady)
                    }
                } else {
                    Section { Text("Yeni kısayol eklemek için önce Cihazlar'dan TV'ye bağlan.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Kısayollar").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Uygulama veya giriş ara")
            .refreshable { await client.refreshLibrary(reportErrors: false) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .alert("Kısayol adı", isPresented: $renaming) {
                TextField("Ad", text: $title)
                Button("İptal", role: .cancel) { naming = nil }
                Button("Kaydet") {
                    if var item = naming, let tv = client.selected {
                        item.title = title; shortcuts.put(item, tv: tv.id)
                    }
                    naming = nil
                }
            } message: { Text("Bu ad yalnızca kumandandaki kısayolda görünür.") }
        }
    }
    private func matches(_ item: TVItem) -> Bool {
        search.isEmpty || item.title.localizedCaseInsensitiveContains(search) || item.detail.localizedCaseInsensitiveContains(search)
    }
    private func rename(_ item: TVShortcut) { naming = item; title = item.title; renaming = true }
    private func addRow(_ item: TVShortcut, detail: String = "") -> some View {
        let exists = items.contains { $0.id == item.id }
        return Button { rename(item) } label: {
            HStack {
                Image(systemName: item.symbol).foregroundStyle(Theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).foregroundStyle(.primary)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: exists ? "checkmark" : "plus.circle").foregroundStyle(Theme.accent)
            }.frame(minHeight: 44)
        }.accessibilityLabel("\(item.title), \(exists ? "kısayolu düzenle" : "kısayol ekle")")
    }
}

struct HDMIHelpView: View {
    @EnvironmentObject private var client: TVClient
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var opening = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section("Kutuya geç") {
                    Picker("Tivibu / TVP girişi", selection: $input) {
                        Text("Giriş seç").tag("")
                        ForEach(client.inputs) { item in Text("\(item.title) · \(item.detail)" + (item.simplinkName.map { " · \($0)" } ?? "")).tag(item.id) }
                    }
                    Button(opening ? "Açılıyor…" : "Seçili girişi aç") {
                        opening = true
                        Task {
                            defer { opening = false }
                            do { try await client.switchInput(input); client.controlMode = .automatic }
                            catch { self.error = error.localizedDescription }
                        }
                    }.frame(minHeight: 44).disabled(input.isEmpty || opening || client.state != .connected)
                }
                Section("SIMPLINK durumu") {
                    ForEach(client.inputs.filter { $0.id.uppercased().hasPrefix("HDMI") }) { item in
                        LabeledContent("\(item.title) · \(item.detail)", value: item.simplinkName ?? "Cihaz görünmüyor")
                    }
                    Text("Tuşlar kutuya yalnızca TV'nin SIMPLINK listesinde görünen cihaza iletilir. Cihaz görünmüyorsa kutunun ayarlarında HDMI-CEC'i aç, HDMI kablosunu çıkarıp tak veya TV'de SIMPLINK'i kapatıp aç. Kutu CEC desteklemiyorsa ağ üzerinden yönetilemez.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("TV'de SIMPLINK (HDMI-CEC) ve kutuda HDMI-CEC açık olmalı. Menü adları modele göre değişebilir.")
                    Text("Yön ve OK tuşlarını dene. Tuşlar önce TV'ye gönderilir; kutuya iletilmesi TV ve kutunun desteğine bağlıdır.")
                    DirectionPad(diameter: 212).frame(maxWidth: .infinity).padding(.vertical, 12).disabled(!client.pointerReady)
                } header: { Text("Yön ve OK testi") }
                Section("Çalışmazsa") {
                    Text("LG'nin fiziksel kumandasıyla da dene. Fiziksel kumanda çalışsa bile kızılötesi kullanıyor olabilir; bu kontrol ağ üzerinden aktarılamayabilir. Kutunun marka ve modeliyle ayrıca kontrol yöntemi belirlenmesi gerekir.")
                    Text("HDMI kutusuna TV'nin metin klavyesi veya fare imleci aktarılmaz. Ekrandaki klavyede yön tuşlarıyla gezinebilirsin.")
                }.font(.subheadline)
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("HDMI kutusu").navigationBarTitleDisplayMode(.inline)
            .refreshable { await client.refreshLibrary() }
            .task { await client.refreshLibrary(reportErrors: false) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }
}
