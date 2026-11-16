import SwiftUI

/// Adds or edits an Android TV box controlled over Wi-Fi: find it, pair once with the code on its screen,
/// then name it and link it to the TV input it is plugged into. `boxID == nil` adds a new box.
struct BoxSetupView: View {
    @EnvironmentObject private var client: TVClient
    @EnvironmentObject private var box: BoxClient
    @Environment(\.dismiss) private var dismiss
    @StateObject private var discovery = BoxDiscovery()
    var boxID: UUID? = nil
    @State private var manualHost = ""
    @State private var code = ""
    @State private var name = ""
    @State private var prepared = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if !prepared {
                    EmptyView()
                } else if let current = box.box, current.paired {
                    pairedSection(current)
                } else {
                    pairingSection
                }
            }
            .navigationTitle(boxID == nil && box.box?.paired != true ? "Android TV kutusu ekle" : "Android TV kutusu").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { saveName(); dismiss() } } }
            .task {
                if !prepared {
                    if let boxID { box.select(boxID) } else { box.beginAdding() }
                    name = box.box?.customName == true ? box.box?.name ?? "" : ""
                    prepared = true
                }
                if box.box?.paired != true { discovery.start() }
            }
            .onChange(of: box.pairing) { _, state in
                // The code was on the box's screen, so the TV was showing the box's input.
                if state == .done, box.box?.inputID == nil, let shown = currentHDMIInput { box.link(input: shown) }
            }
            .onChange(of: box.box?.id) { _, _ in name = box.box?.customName == true ? box.box?.name ?? "" : "" }
            .onDisappear { saveName(); discovery.stop(); if box.pairing != .done { box.cancelPairing() } }
        }
    }

    // MARK: Paired

    private func pairedSection(_ current: BoxClient.Box) -> some View {
        Group {
            Section {
                TextField(current.title(inputs: client.inputs), text: $name)
                    .autocorrectionDisabled()
                    .onSubmit(saveName)
                    .accessibilityIdentifier("boxName")
                LabeledContent("Ağdaki adı", value: current.name.isEmpty || current.customName ? "—" : current.name)
                LabeledContent("Adres", value: current.host)
                Toggle("Wi-Fi ile kumanda et", isOn: $box.enabled).accessibilityIdentifier("boxEnabled")
            } header: { Text("Ad") } footer: {
                Text("Boş bırakırsan kutu, bağlı olduğu TV girişinin adıyla görünür. TV aşağıdaki girişteyken tuşlar kutuya Wi-Fi ile gider; ses TV'de kalır.")
            }
            Section {
                Picker("Giriş", selection: Binding(get: { current.inputID ?? "" }, set: { box.link(input: $0.isEmpty ? nil : $0) })) {
                    Text("Seçilmedi").tag("")
                    ForEach(hdmiInputs) { input in Text("\(input.title) · \(input.detail)").tag(input.id) }
                }.accessibilityIdentifier("boxInput")
                if let shown = currentHDMIInput, shown != current.inputID {
                    Button("TV'nin şu anki girişini kullan (\(inputTitle(shown)))") { box.link(input: shown) }
                }
            } header: { Text("Kutunun bağlı olduğu giriş") } footer: {
                Text("Yanlış kutunun açıldığını görürsen burada doğru girişi seç.")
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
                Text("Android TV kutularını (set üstü kutular, Google TV) HDMI-CEC olmadan Wi-Fi üzerinden kumanda edebilirsin. Kutu ile iPhone aynı ağda olmalı. Eşleştirmeden önce TV'yi kutunun girişine al; kod kutunun ekranında çıkar ve giriş otomatik kaydedilir.")
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

    /// The HDMI input the TV shows now. The pairing code appears on the box's screen, so while pairing
    /// the TV is on the box's input; that is a better guess than matching names.
    private var currentHDMIInput: String? {
        hdmiInputs.first { ControlRouting.appID(forInput: $0.id) == client.foregroundAppID }?.id
    }
    private func inputTitle(_ id: String) -> String { hdmiInputs.first { $0.id == id }?.title ?? id }
    private func saveName() {
        guard box.box?.paired == true else { return }
        let current = box.box?.customName == true ? box.box?.name ?? "" : ""
        if name.trimmingCharacters(in: .whitespacesAndNewlines) != current { box.rename(name) }
    }

    private func pair(host: String, name: String) {
        code = ""
        discovery.stop()
        Task { await box.startPairing(host: host, name: name, inputID: currentHDMIInput) }
    }
}
