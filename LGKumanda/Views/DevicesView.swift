import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var client: TVClient
    @State private var adding = false
    @StateObject private var discovery = TVDiscovery()
    @State private var editing: Television?
    @State private var reset = false
    @AppStorage("haptics") private var haptics = true
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { Task { await discovery.search(knownHosts: client.televisions.map(\.host)) } } label: {
                        HStack {
                            Label(discovery.searching ? "Televizyonlar aranıyor…" : "Ağda LG TV ara", systemImage: "magnifyingglass")
                            Spacer()
                            if discovery.searching { ProgressView() }
                        }.frame(minHeight: 44)
                    }.disabled(discovery.searching)
                    if discovery.searching {
                        ProgressView(value: Double(discovery.checkedCount), total: Double(max(1, discovery.totalCount)))
                            .accessibilityLabel("Ağ araması")
                        Button("Aramayı durdur") { discovery.cancel() }
                    }
                    ForEach(discovery.found) { tv in
                        Button {
                            discovery.cancel()
                            editing = client.televisions.first(where: { $0.host == tv.host }) ?? tv
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tv.name).foregroundStyle(.primary)
                                Text(tv.host).font(.subheadline).foregroundStyle(.secondary)
                            }.frame(minHeight: 44)
                        }
                    }
                    if discovery.completed && discovery.found.isEmpty {
                        Text(discovery.message ?? "TV bulunamadı. IP adresiyle eklemeyi deneyebilirsin.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if discovery.permissionDenied {
                            Button("Ayarları aç") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    }
                } header: { Text("Yerel ağ") }
                if client.televisions.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("TV'ni bağla", systemImage: "tv.badge.wifi")
                        } description: {
                            Text("iPhone ve LG webOS televizyonun aynı Wi-Fi ağına bağlı olsun. TV'nin IP adresiyle başlayabilirsin.")
                        } actions: {
                            Button("Televizyon ekle") { adding = true }.buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    Section("Televizyonlar") {
                        ForEach(client.televisions) { tv in
                            HStack(spacing: 12) {
                                Image(systemName: "tv").foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tv.name).font(.headline)
                                    Text(tv.host).font(.subheadline).foregroundStyle(.secondary)
                                    if client.selected?.id == tv.id { Text(client.state.label).font(.caption).foregroundStyle(Theme.accent) }
                                }
                                Spacer()
                                editButton(tv)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { client.connect(to: tv) }
                            .accessibilityAction(named: "Bağlan") { client.connect(to: tv) }
                            .swipeActions { Button("Sil", role: .destructive) { client.remove(tv) } }
                        }
                        Button { adding = true } label: { Label("Televizyon ekle", systemImage: "plus") }.frame(minHeight: 44)
                    }
                }
                if let tv = client.selected {
                    Section {
                        LabeledContent("Durum", value: client.state.label)
                        if client.state == .connecting || client.state == .pairing {
                            HStack { ProgressView(); Text(client.state == .pairing ? "TV ekranındaki bağlantı isteğini kabul et." : "Televizyonla bağlantı kuruluyor…").font(.subheadline) }
                            Button("İptal et", role: .cancel) { client.disconnect() }.frame(minHeight: 44)
                        } else if client.state == .connected {
                            Button("Bağlantıyı kes") { client.disconnect() }.frame(minHeight: 44)
                        } else {
                            Button("Bağlan") { client.connect(to: tv) }.frame(minHeight: 44)
                        }
                        Button("TV'yi uyandır") { client.wake() }.frame(minHeight: 44)
                        Button("Yeniden eşleştir", role: .destructive) { reset = true }.frame(minHeight: 44)
                    } header: { Text("Bağlantı") } footer: {
                        Text("İlk bağlantıda TV ekranından izin ver. Sertifika değişirse veya TV sıfırlanırsa yeniden eşleştir.")
                    }
                }
                Section {
                    Toggle("Tuş titreşimi", isOn: $haptics)
                }
                Section("Bağlantı yardımı") {
                    help(title: "Aynı ağa bağlan", text: "iPhone ve TV aynı yerel ağda olmalı. iPhone Ayarlar uygulamasından LG Kumanda için Yerel Ağ iznini aç.")
                    help(title: "TV'nin IP adresini bul", text: "TV Ayarlar → Ağ → Bağlantı bilgileri bölümüne bak. Menü adı modele göre değişebilir.")
                    help(title: "Mobil bağlantıya izin ver", text: "LG Connect Apps veya Mobil TV Açık ayarını etkinleştir. Uyandırmak için TV'nin MAC adresini ekle ve ağ üzerinden açmayı etkinleştir.")
                }
                Section {
                    Text("LG Kumanda bağımsız bir uygulamadır; LG Electronics ile bağlantılı değildir. Özellik desteği TV modeli ve webOS sürümüne göre değişir. Kızılötesi ve TV'nin sesli asistanı desteklenmez. iPhone klavyesindeki dikteyi metin girişi için kullanabilirsin.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cihazlar")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Televizyon ekle") } }
            .sheet(isPresented: $adding) { DeviceEditor() }
            .sheet(item: $editing) { DeviceEditor(existing: $0) }
            .confirmationDialog("Eşleştirme bilgileri silinip yeniden bağlantı kurulacak.", isPresented: $reset, titleVisibility: .visible) {
                Button("Yeniden eşleştir", role: .destructive) { client.resetPairing() }
            }
        }
    }
    private func editButton(_ tv: Television) -> some View {
        Button { editing = tv } label: {
            Image(systemName: "pencil").frame(width: 44, height: 44)
        }.buttonStyle(.borderless).accessibilityLabel("Televizyonu düzenle")
    }
    private func help(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }
}

struct DeviceEditor: View {
    @EnvironmentObject private var client: TVClient
    @Environment(\.dismiss) private var dismiss
    var existing: Television?
    @State private var name = "Salon TV"
    @State private var host = ""
    @State private var secure = true
    @State private var mac = ""
    @State private var broadcast = "255.255.255.255"
    @State private var validation: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad", text: $name).textInputAutocapitalization(.words)
                    TextField("IP adresi · 192.168.1.50", text: $host).keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Televizyon") } footer: { Text("TV'nin ağ ayarlarındaki IPv4 adresini yaz. İlk bağlantıda TV ekranında izin isteği görünecek.") }
                Section {
                    Toggle("Şifreli bağlantı", isOn: $secure)
                } footer: { Text(secure ? "WSS · 3001. TV sertifikası ilk eşleştirmede kaydedilir ve sonraki bağlantılarda doğrulanır." : "WS · 3000. Eski TV'ler için. Yerel ağdaki bağlantı şifrelenmez.") }
                Section {
                    TextField("MAC adresi · AA:BB:CC:DD:EE:FF", text: $mac).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Yayın adresi", text: $broadcast).keyboardType(.decimalPad).autocorrectionDisabled()
                } header: { Text("TV'yi uyandırma · isteğe bağlı") } footer: { Text("TV'de ağ üzerinden açmayı etkinleştir. Wake-on-LAN desteği modele ve ağ bağlantısına bağlıdır.") }
                if let validation { Section { Text(validation).foregroundStyle(.red) } }
            }
            .navigationTitle(existing == nil ? "Televizyon ekle" : "Televizyonu düzenle").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Bağlan", action: save).fontWeight(.semibold) }
            }
            .onAppear {
                if let tv = existing { name = tv.name; host = tv.host; secure = tv.secure; mac = tv.mac; broadcast = tv.broadcast }
            }
        }
    }
    private func save() {
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { validation = "Televizyonuna bir ad ver."; return }
        guard TVProtocol.validHost(address) else { validation = "Geçerli bir yerel IPv4 adresi gir. Örnek: 192.168.1.50"; return }
        let trimmedMAC = mac.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMAC.isEmpty, (try? WakeOnLAN.packet(mac: trimmedMAC)) == nil { validation = "MAC adresini kontrol et. Örnek: AA:BB:CC:DD:EE:FF"; return }
        if !trimmedMAC.isEmpty {
            var test = in_addr()
            guard inet_pton(AF_INET, broadcast, &test) == 1 else { validation = "Yayın adresini kontrol et."; return }
        }
        var tv = existing ?? Television(name: title, host: address)
        if tv.host != address || tv.secure != secure {
            KeychainStore.delete("key.\(tv.id)"); KeychainStore.delete("cert.\(tv.id)")
        }
        tv.name = title; tv.host = address; tv.secure = secure; tv.mac = trimmedMAC; tv.broadcast = broadcast
        client.save(tv); dismiss()
    }
}
