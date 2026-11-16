import SwiftUI

struct RootView: View {
    @EnvironmentObject private var client: TVClient
    @EnvironmentObject private var shortcuts: ShortcutStore
    @EnvironmentObject private var box: BoxClient
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            RemoteView(openDevices: { tab = 3 }).tabItem { Label("Kumanda", systemImage: "appletvremote.gen4") }.tag(0)
            LibraryView(kind: .apps).tabItem { Label("Uygulamalar", systemImage: "square.grid.2x2") }.tag(1)
            LibraryView(kind: .channels).tabItem { Label("Kanallar", systemImage: "tv") }.tag(2)
            KeyboardView(isSheet: false).tabItem { Label("Klavye", systemImage: "keyboard") }.tag(4)
            DevicesView().tabItem { Label("Cihazlar", systemImage: "wifi") }.tag(3)
        }
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { client.error != nil }, set: { if !$0 { client.error = nil } })) {
            Button("Tamam", role: .cancel) { client.error = nil }
        } message: { Text(client.error ?? "") }
        .sheet(isPresented: $client.browserAddressRequested) { BrowserAddressView() }
        .task { if let tv = client.selected, client.state == .disconnected { client.connect(to: tv) } }
        .onChange(of: client.libraryReady) { _, ready in
            if ready { shortcuts.seed(tv: client.selected?.id, apps: client.apps, inputs: client.inputs) }
        }
        .onChange(of: phase) { _, phase in
            if phase == .background { client.disconnect(); box.disconnect() }
            else if phase == .active, let tv = client.selected, client.state == .disconnected { client.connect(to: tv) }
        }
    }
}

struct RemoteButton: View {
    let title: String
    var symbol: String? = nil
    var prominent = false
    var color: Color? = nil
    let action: () -> Void
    @AppStorage("haptics") private var haptics = true
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button {
            if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            action()
        } label: {
            VStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.title3.weight(.medium)) }
                Text(title).font(symbol == nil ? .body.weight(.semibold) : .caption.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(prominent ? Color.white : (color ?? Color.primary))
            .background(prominent ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressStyle())
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

struct RemoteView: View {
    @EnvironmentObject private var client: TVClient
    @EnvironmentObject private var box: BoxClient
    let openDevices: () -> Void
    @State private var mode = 0
    @State private var keyboard = false
    @State private var sources = false
    @State private var powerOff = false
    @State private var editingShortcuts = false
    @State private var hdmiHelp = false
    private var connected: Bool { client.state == .connected }
    private var keysAvailable: Bool { client.pointerReady || box.handles(foregroundAppID: client.foregroundAppID) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    connection
                    ShortcutStrip()
                    if let notice = client.notice {
                        HStack(alignment: .top) {
                            Image(systemName: "info.circle")
                            Text(notice).font(.footnote)
                            Spacer(minLength: 0)
                            Button { client.notice = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Bilgiyi kapat")
                        }.foregroundStyle(.secondary)
                    }
                    if connected, let input = client.activeInputWithoutSimplink, !box.handles(foregroundAppID: client.foregroundAppID) {
                        Button { hdmiHelp = true } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                Text("\(input.title) girişindeki cihaz SIMPLINK'te görünmüyor. Yön ve OK tuşları bu kutuya ulaşmayabilir. Kutuyu Wi-Fi ile kumanda etmek için dokun.")
                                    .font(.footnote).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }.foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).accessibilityIdentifier("simplinkWarning")
                    }
                    if connected, box.handles(foregroundAppID: client.foregroundAppID) {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi")
                            Text(box.statusText).font(.footnote)
                            Spacer(minLength: 0)
                        }.foregroundStyle(.secondary).accessibilityIdentifier("boxStatus")
                    }
                    if connected, box.handles(foregroundAppID: client.foregroundAppID) {
                        BoxQuickControls()
                    }
                    HStack(spacing: 12) {
                        RemoteButton(title: connected ? "Kapat" : "Uyandır", symbol: "power", color: Theme.accent) {
                            if connected { powerOff = true } else { client.wake() }
                        }
                        RemoteButton(title: "Giriş", symbol: "rectangle.on.rectangle") { sources = true }.disabled(!connected)
                        RemoteButton(title: "Klavye", symbol: "keyboard") { keyboard = true }.disabled(!connected)
                    }
                    VStack(spacing: 18) {
                        Picker("Kontrol biçimi", selection: $mode) {
                            Text("Yön tuşları").tag(0)
                            Text("Dokunmatik").tag(1)
                        }.pickerStyle(.segmented)
                        if mode == 1 {
                            if client.isHDMIActive { Text("HDMI: işaretçisiz gezinme").font(.caption).foregroundStyle(.secondary) }
                            else { PointerModePicker() }
                        }
                        ViewThatFits(in: .horizontal) {
                                navigationCluster(diameter: 212)
                                navigationCluster(diameter: 180)
                        }.frame(maxWidth: .infinity)
                        HStack(spacing: 12) {
                            RemoteButton(title: "Geri", symbol: "arrow.uturn.backward") { client.key(.back) }
                            RemoteButton(title: "TV ana ekranı", symbol: "house", prominent: true) { client.key(.home) }
                            RemoteButton(title: "Ayarlar", symbol: "gearshape") { client.key(.settings) }
                        }.disabled(!keysAvailable)
                    }.disabled(!connected)
                    HStack(spacing: 12) {
                        RemoteButton(title: client.muted ? "Sesi aç" : "Sessiz", symbol: client.muted ? "speaker.slash.fill" : "speaker.wave.2") {
                            client.command("audio/setMute", ["mute": !client.muted])
                        }
                        RemoteButton(title: "Rehber", symbol: "list.bullet.rectangle") { client.key(.guide) }.disabled(!keysAvailable)
                    }.disabled(!connected)
                    extraControls.disabled(!connected)
                    Text("LG webOS için bağımsız kumanda.").font(.footnote).foregroundStyle(.secondary).padding(.bottom, 12)
                }
                .padding(.horizontal, 20).padding(.top, 8)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Kumanda")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editingShortcuts = true } label: { Image(systemName: "star") }
                        .accessibilityLabel("Kısayolları düzenle").disabled(client.selected == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Kanal ve medya tuşları", selection: $client.controlMode) {
                            ForEach(ControlMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }
                        Button("HDMI kutusu yardımı") { hdmiHelp = true }
                    } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Kontrol hedefi")
                }
            }
            .sheet(isPresented: $keyboard) { KeyboardView() }
            .sheet(isPresented: $sources) { LibraryView(kind: .inputs) }
            .sheet(isPresented: $editingShortcuts) { ShortcutEditor() }
            .sheet(isPresented: $hdmiHelp) { HDMIHelpView() }
            .confirmationDialog("Televizyon kapatılsın mı?", isPresented: $powerOff, titleVisibility: .visible) {
                Button("TV'yi kapat", role: .destructive) {
                    client.powerOff()
                }
            }
        }
    }
    private var connection: some View {
        Button(action: openDevices) {
            HStack(spacing: 12) {
                Image(systemName: "tv").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.selected?.name ?? "Televizyonunu ekle").font(.headline).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Circle().fill(connected ? Color.green : Color.secondary).frame(width: 6, height: 6)
                        Text(client.selected == nil ? "Aynı Wi-Fi üzerinden bağlan" : client.connectionLabel + (connected ? " · " + client.controlLabel : "")).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if client.state == .connecting || client.state == .pairing { ProgressView() }
                else { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary) }
            }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
    private func navigationCluster(diameter: CGFloat) -> some View {
        HStack(spacing: 12) {
            rocker(title: "SES", value: client.volume.map(String.init) ?? "—", plus: "plus", minus: "minus",
                   increase: { client.command("audio/volumeUp") }, decrease: { client.command("audio/volumeDown") }).frame(width: 56)
            if mode == 0 { DirectionPad(diameter: diameter).disabled(!keysAvailable) }
            else { TouchPad(forceCursorless: client.isHDMIActive).frame(width: diameter, height: diameter).disabled(!keysAvailable) }
            rocker(title: "KANAL", value: nil, plus: "chevron.up", minus: "chevron.down",
                   increase: { client.channel(up: true) }, decrease: { client.channel(up: false) }).frame(width: 56)
                .disabled(client.controlContext != .television && !keysAvailable)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private func rocker(title: String, value: String?, plus: String, minus: String, increase: @escaping () -> Void, decrease: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: increase) { Image(systemName: plus).font(.title3.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52) }.accessibilityLabel(title == "SES" ? "Sesi artır" : "Sonraki kanal")
            VStack(spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5)
                if let value { Text(value).font(.title3.weight(.semibold)).monospacedDigit() }
            }.frame(minHeight: 44)
            Button(action: decrease) { Image(systemName: minus).font(.title3.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52) }.accessibilityLabel(title == "SES" ? "Sesi azalt" : "Önceki kanal")
        }.foregroundStyle(.primary).frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private var extraControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Diğer tuşlar").font(.title2.weight(.bold))
            HStack(spacing: 10) {
                RemoteButton(title: "Geri sar", symbol: "backward.fill") { client.media(.rewind) }
                RemoteButton(title: "Oynat", symbol: "play.fill") { client.media(.play) }
                RemoteButton(title: "Duraklat", symbol: "pause.fill") { client.media(.pause) }
                RemoteButton(title: "İleri sar", symbol: "forward.fill") { client.media(.fastForward) }
            }.disabled(client.controlContext != .television && !keysAvailable)
            HStack(spacing: 10) {
                RemoteButton(title: "Durdur", symbol: "stop.fill") { client.media(.stop) }.disabled(client.controlContext != .television && !keysAvailable)
                RemoteButton(title: "Bilgi", symbol: "info.circle") { client.key(.info) }.disabled(!keysAvailable)
                RemoteButton(title: "Çıkış", symbol: "rectangle.portrait.and.arrow.right") { client.key(.exit) }.disabled(!keysAvailable)
            }
            numericPad.disabled(!keysAvailable)
            HStack(spacing: 12) {
                colorKey("Kırmızı", key: .red, color: .red, shape: "circle.fill")
                colorKey("Yeşil", key: .green, color: .green, shape: "square.fill")
                colorKey("Sarı", key: .yellow, color: .yellow, shape: "triangle.fill")
                colorKey("Mavi", key: .blue, color: .blue, shape: "diamond.fill")
            }.disabled(!keysAvailable)
            HStack(spacing: 10) {
                RemoteButton(title: "Altyazı") { client.key(.subtitles) }
                RemoteButton(title: "Teletekst") { client.key(.teletext) }
                RemoteButton(title: "Liste") { client.key(.list) }
            }.disabled(!keysAvailable)
            RemoteButton(title: "Menü", symbol: "line.3.horizontal") { client.key(.menu) }.disabled(!keysAvailable)
        }
    }
    private var numericPad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach([RemoteKey.one, .two, .three, .four, .five, .six, .seven, .eight, .nine], id: \.self) { key in
                RemoteButton(title: key.rawValue) { client.key(key) }
            }
            RemoteButton(title: "–") { client.key(.dash) }
            RemoteButton(title: "0") { client.key(.zero) }
            RemoteButton(title: "Önceki") { client.key(.previous) }
        }
    }
    private func colorKey(_ title: String, key: RemoteKey, color: Color, shape: String) -> some View {
        Button { client.key(key) } label: {
            VStack(spacing: 4) {
                Image(systemName: shape).foregroundStyle(color).font(.title3)
                Text(title).font(.caption2).foregroundStyle(.primary)
            }.frame(maxWidth: .infinity, minHeight: 56).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        }.accessibilityLabel("\(title) tuş")
    }
}

/// Shown while keys go to the Wi-Fi box: type a channel number and pause/resume in one tap.
struct BoxQuickControls: View {
    @EnvironmentObject private var box: BoxClient
    @State private var channel = ""
    @FocusState private var typing: Bool
    var body: some View {
        HStack(spacing: 10) {
            TextField("Kanal no", text: $channel)
                .keyboardType(.numberPad)
                .focused($typing)
                .font(.title3.weight(.semibold)).monospacedDigit()
                .padding(.horizontal, 14).frame(minHeight: 56)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                .onChange(of: channel) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(5))
                    if digits != value { channel = digits }
                }
                .onSubmit(go)
                .accessibilityIdentifier("boxChannelField")
            Button(action: go) {
                Text("Git").font(.body.weight(.semibold)).frame(minWidth: 56, minHeight: 56)
            }
            .foregroundStyle(.white)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
            .disabled(channel.isEmpty)
            .accessibilityLabel("Kanala git")
            RemoteButton(title: "Durdur/Devam", symbol: "playpause.fill") { box.send(code: BoxClient.playPauseCode) }
                .frame(maxWidth: 120)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Git", action: go).disabled(channel.isEmpty)
            }
        }
    }
    private func go() {
        guard box.enterChannel(channel) else { return }
        channel = ""
        typing = false
    }
}

struct DirectionPad: View {
    @EnvironmentObject private var client: TVClient
    var diameter: CGFloat = 212
    private var centerSize: CGFloat { diameter * 0.36 }
    private var edge: CGFloat { (diameter - centerSize) / 2 }
    var body: some View {
        VStack(spacing: 0) {
            direction("Yukarı", symbol: "chevron.up", key: .up).frame(width: centerSize, height: edge)
            HStack(spacing: 0) {
                direction("Sol", symbol: "chevron.left", key: .left).frame(width: edge, height: centerSize)
                Button { client.key(.enter) } label: {
                    Text("OK").font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: centerSize, height: centerSize).background(Theme.accent, in: Circle())
                }.buttonStyle(PressStyle()).accessibilityLabel("Tamam")
                direction("Sağ", symbol: "chevron.right", key: .right).frame(width: edge, height: centerSize)
            }
            direction("Aşağı", symbol: "chevron.down", key: .down).frame(width: centerSize, height: edge)
        }.frame(width: diameter, height: diameter).background(Theme.surface, in: Circle())
    }
    private func direction(_ title: String, symbol: String, key: RemoteKey) -> some View {
        Button { client.key(key) } label: { Image(systemName: symbol).font(.title2.weight(.medium)).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle()) }
            .buttonStyle(PressStyle()).foregroundStyle(.primary).accessibilityLabel(title)
    }
}
