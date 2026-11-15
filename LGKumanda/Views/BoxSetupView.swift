import SwiftUI

/// Set up Wi-Fi control of an Android TV box (Tivibu and similar): find it, pair once with the code on screen,
/// and link it to the TV input it is plugged into.
struct BoxSetupView: View {
    @EnvironmentObject private var client: TVClient
    @EnvironmentObject private var box: BoxClient
    @Environment(\.dismiss) private var dismiss
    @StateObject private var discovery = BoxDiscovery()
    @State private var manualHost = ""
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if let current = box.box, current.paired {
                    pairedSection(current)
                } else {
                    pairingSection
                }
            }
            .navigationTitle("Wi-Fi ile kutu kumandası").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .task { if box.box?.paired != true { discovery.start() } }
            .onDisappear { discovery.stop(); if box.pairing != .done { box.cancelPairing() } }
        }
    }

    // MARK: Paired

    private func pairedSection(_ current: BoxClient.Box) -> some View {
        Group {
            Section {
                LabeledContent("Kutu", value: current.name)
                LabeledContent("Adres", value: current.host)
                Toggle("Wi-Fi ile kumanda et", isOn: $box.enabled).accessibilityIdentifier("boxEnabled")
            } footer: {
                Text("TV aşağıdaki girişteyken yön, OK, geri, ana ekran, kanal, rakam ve oynatma tuşları kutuya Wi-Fi ile gider. Ses TV'de kalır.")
            }
            Section("Kutunun bağlı olduğu giriş") {
                Picker("Giriş", selection: Binding(get: { current.inputID ?? "" }, set: { box.link(input: $0.isEmpty ? nil : $0) })) {
                    Text("Seçilmedi").tag("")
                    ForEach(hdmiInputs) { input in Text("\(input.title) · \(input.detail)").tag(input.id) }
                }.accessibilityIdentifier("boxInput")
            }
            Section("Deneme") {
                Text(box.statusText).font(.footnote).foregroundStyle(.secondary)
                HStack {
                    ForEach([(RemoteKey.up, "chevron.up"), (.down, "chevron.down"), (.enter, "circle"), (.back, "arrow.uturn.backward"), (.home, "house")], id: \.0) { key, symbol in
                        Button { box.send(key) } label: { Image(systemName: symbol).frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            Section {
                Button("Kutuyu kaldır", role: .destructive) { box.forget(); discovery.start() }
            }
        }
    }

    // MARK: Pairing

    @ViewBuilder private var pairingSection: some View {
        switch box.pairing {
        case .waitingForCode, .verifying:
            Section {
                Text("Kutunun ekranında 6 karakterlik bir kod göründü. TV'yi kutunun girişine al ve kodu yaz.")
                TextField("Örnek: 37D523", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.title2.monospaced()).focused($codeFocused)
                    .onChange(of: code) { _, value in code = String(value.uppercased().filter(\.isHexDigit).prefix(6)) }
                    .onSubmit { box.finishPairing(code: code) }
                    .accessibilityIdentifier("boxCode")
                if let error = box.pairingCodeError { Text(error).foregroundStyle(.red).font(.footnote) }
                Button(box.pairing == .verifying ? "Doğrulanıyor…" : "Eşleştir") { box.finishPairing(code: code) }
                    .disabled(code.count != 6 || box.pairing == .verifying)
            } header: { Text("Eşleştirme kodu") }
            .onAppear { codeFocused = true }
        default:
            Section {
                Text("Tivibu gibi Android TV kutularını HDMI-CEC olmadan, Wi-Fi üzerinden kumanda edebilirsin. Kutu ile iPhone aynı ağda olmalı.")
                    .font(.subheadline)
                if case .failed(let reason) = box.pairing { Text(reason).foregroundStyle(.red).font(.footnote) }
                if box.pairing == .starting { HStack { ProgressView(); Text("Kutuya bağlanılıyor…") } }
            }
            Section {
                ForEach(discovery.found) { found in
                    Button { pair(host: found.host, name: found.name) } label: {
                        LabeledContent(found.name, value: found.host)
                    }.disabled(box.pairing == .starting)
                }
                if discovery.searching { HStack { ProgressView(); Text("Ağda aranıyor…").foregroundStyle(.secondary) } }
                else if discovery.found.isEmpty {
                    Text("Kutu bulunamadı. Kutu açık ve aynı Wi-Fi'da mı?").foregroundStyle(.secondary)
                    Button("Yeniden ara") { discovery.start() }
                }
            } header: { Text("Bulunan kutular") }
            Section {
                TextField("Kutunun IP adresi, örn. 192.168.1.11", text: $manualHost)
                    .keyboardType(.decimalPad).autocorrectionDisabled()
                Button("Bu adresle eşleştir") { pair(host: manualHost.trimmingCharacters(in: .whitespaces), name: "Android TV kutusu") }
                    .disabled(!TVProtocol.validHost(manualHost.trimmingCharacters(in: .whitespaces)) || box.pairing == .starting)
            } header: { Text("Elle ekle") }
        }
    }

    private var hdmiInputs: [TVItem] { client.inputs.filter { $0.id.uppercased().hasPrefix("HDMI") } }

    /// Suggested input: one named like the box (e.g. "tivibu"), otherwise none until the user picks.
    private func suggestedInput(for name: String) -> String? {
        let key = name.lowercased()
        return hdmiInputs.first { input in
            let title = input.title.lowercased()
            return key.contains(title) || title.contains("tivibu") && key.contains("tivibu")
        }?.id
    }

    private func pair(host: String, name: String) {
        code = ""
        discovery.stop()
        Task { await box.startPairing(host: host, name: name, inputID: suggestedInput(for: name)) }
    }
}
