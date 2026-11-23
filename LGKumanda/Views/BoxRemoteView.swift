import SwiftUI

/// Which remote the Kumanda tab shows.
enum RemoteTarget: Hashable { case tv, box(UUID) }

/// Remote for one Wi-Fi Android TV box. Laid out like a set-top box remote:
/// navigation on top, the number pad always visible, media and colour keys below.
/// Keys go straight to the box; volume and mute stay on the TV, where the sound plays.
struct BoxRemoteView: View {
    @EnvironmentObject private var client: TVClient
    @EnvironmentObject private var box: BoxClient
    let id: UUID
    @State private var setup = false
    @State private var typed = ""
    @State private var clearTyped: Task<Void, Never>?

    private var name: String { box.boxes.first { $0.id == id }?.title(inputs: client.inputs) ?? "Kutu" }

    var body: some View {
        VStack(spacing: 18) {
            if box.boxes.first(where: { $0.id == id })?.paired == true {
                status
                topRow
                ViewThatFits(in: .horizontal) {
                    cluster(diameter: 212)
                    cluster(diameter: 180)
                }.frame(maxWidth: .infinity)
                numberPad
                mediaRow
                HStack(spacing: 10) {
                    RemoteButton(title: "Rehber", symbol: "list.bullet.rectangle") { press(.guide) }
                    RemoteButton(title: "Bilgi", symbol: "info.circle") { press(.info) }
                    RemoteButton(title: client.muted ? "Sesi aç" : "Sessiz", symbol: client.muted ? "speaker.slash.fill" : "speaker.wave.2") {
                        client.command("audio/setMute", ["mute": !client.muted])
                    }.disabled(client.state != .connected)
                }
                colorKeys
                Button { setup = true } label: {
                    Label("\(name) ayarları", systemImage: "gearshape").font(.footnote)
                }.frame(minHeight: 44).accessibilityIdentifier("boxSettings")
            } else {
                pairingCard
            }
        }
        .sheet(isPresented: $setup) { BoxSetupView(boxID: id) }
        .onAppear { box.select(id) }
    }

    // MARK: Parts

    private var status: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(box.statusText).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.accessibilityIdentifier("boxStatus")
    }
    private var statusColor: Color {
        switch box.state {
        case .connected: return .green
        case .failed: return .orange
        default: return .secondary
        }
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            RemoteButton(title: "Geri", symbol: "arrow.uturn.backward") { press(.back) }
            RemoteButton(title: "Ana sayfa", symbol: "house", prominent: true) { press(.home) }
            RemoteButton(title: "Menü", symbol: "line.3.horizontal") { press(.menu) }
        }
    }

    private func cluster(diameter: CGFloat) -> some View {
        HStack(spacing: 12) {
            Rocker(title: "SES", value: client.volume.map(String.init), plus: "plus", minus: "minus",
                   increaseLabel: "Sesi artır", decreaseLabel: "Sesi azalt",
                   increase: { client.command("audio/volumeUp") }, decrease: { client.command("audio/volumeDown") })
                .frame(width: 56).disabled(client.state != .connected)
            DirectionPad(diameter: diameter, send: { press($0) })
            Rocker(title: "KANAL", value: nil, plus: "chevron.up", minus: "chevron.down",
                   increaseLabel: "Sonraki kanal", decreaseLabel: "Önceki kanal",
                   increase: { press(.channelUp) }, decrease: { press(.channelDown) })
                .frame(width: 56)
        }.fixedSize(horizontal: true, vertical: false)
    }

    /// Digits go to the box on every tap, like a real remote; the box tunes once the number is complete.
    private var numberPad: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Kanal").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(typed.isEmpty ? "—" : typed)
                    .font(.title2.weight(.bold)).monospacedDigit()
                    .accessibilityLabel(typed.isEmpty ? "Kanal numarası girilmedi" : "Girilen kanal \(typed)")
                    .accessibilityIdentifier("boxTypedChannel")
            }.padding(.horizontal, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach([RemoteKey.one, .two, .three, .four, .five, .six, .seven, .eight, .nine], id: \.self) { key in
                    digit(key)
                }
                RemoteButton(title: "Önceki", symbol: "arrow.left.arrow.right") { press(.previous); reset() }
                digit(.zero)
                RemoteButton(title: "OK", prominent: true) { press(.enter); reset() }
            }
        }
        .padding(12)
        .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
    }
    private func digit(_ key: RemoteKey) -> some View {
        RemoteButton(title: key.rawValue) {
            press(key)
            typed = String((typed + key.rawValue).suffix(4))
            clearTyped?.cancel()
            clearTyped = Task {
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { typed = "" }
            }
        }.accessibilityIdentifier("boxDigit\(key.rawValue)")
    }
    /// Keys always go to this tab's box, even if another box was active.
    private func press(_ key: RemoteKey) { box.select(id); box.send(key) }
    private func reset() { clearTyped?.cancel(); typed = "" }

    private var mediaRow: some View {
        HStack(spacing: 10) {
            RemoteButton(title: "Geri sar", symbol: "backward.fill") { press(.rewind) }
            RemoteButton(title: "Durdur/Devam", symbol: "playpause.fill", prominent: true) { box.select(id); box.send(code: BoxClient.playPauseCode) }
                .accessibilityIdentifier("boxPlayPause")
            RemoteButton(title: "İleri sar", symbol: "forward.fill") { press(.fastForward) }
        }
    }

    private var colorKeys: some View {
        HStack(spacing: 12) {
            ForEach([(RemoteKey.red, Color.red, "Kırmızı"), (.green, .green, "Yeşil"), (.yellow, .yellow, "Sarı"), (.blue, .blue, "Mavi")], id: \.0) { key, color, title in
                Button { press(key) } label: {
                    Capsule().fill(color).frame(height: 10).frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.horizontal, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("\(title) tuş")
            }
        }
    }

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Kutuyu bağla", systemImage: "wifi").font(.title3.weight(.bold))
            Text("TV kutuları Wi-Fi ile kumanda edilir. Kutu ve telefon aynı ağda olmalı. Bir kez eşleştirmen yeterli: TV'yi kutunun girişine al, kutunun ekranındaki 6 karakterlik kodu yaz.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { setup = true } label: {
                Text("Kutuyu bul ve eşleştir").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("boxPairCTA")
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Vertical +/– key with a label, shared by the TV and box remotes.
struct Rocker: View {
    let title: String
    let value: String?
    let plus: String
    let minus: String
    let increaseLabel: String
    let decreaseLabel: String
    let increase: () -> Void
    let decrease: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Button(action: increase) { Image(systemName: plus).font(.title3.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52) }
                .accessibilityLabel(increaseLabel)
            VStack(spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5)
                if let value { Text(value).font(.title3.weight(.semibold)).monospacedDigit() }
            }.frame(minHeight: 44)
            Button(action: decrease) { Image(systemName: minus).font(.title3.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52) }
                .accessibilityLabel(decreaseLabel)
        }.foregroundStyle(.primary).frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}
