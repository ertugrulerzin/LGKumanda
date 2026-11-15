import Foundation
import Network
import Security

/// An Android TV box (Tivibu, Google TV and similar) controlled over Wi-Fi with the Android TV Remote protocol v2,
/// instead of HDMI-CEC. Pairing (port 6467) happens once with a code shown on the box; keys then go to port 6466.
/// While the TV shows the HDMI input the box is linked to, the remote's keys are sent to the box.
@MainActor final class BoxClient: ObservableObject {
    struct Box: Codable, Equatable {
        var host: String
        var name: String
        /// TV input the box is connected to, e.g. "HDMI_3".
        var inputID: String?
        var paired = false
    }
    enum State: Equatable { case idle, connecting, connected, failed(String) }
    enum PairingState: Equatable { case idle, starting, waitingForCode, verifying, done, failed(String) }

    @Published private(set) var box: Box? { didSet { persist() } }
    @Published private(set) var state: State = .idle
    @Published private(set) var pairing: PairingState = .idle
    @Published private(set) var currentApp = ""
    @Published private(set) var deviceModel = ""
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) } }

    private static let storeKey = "androidTVBox"
    private static let enabledKey = "androidTVBox.enabled"
    /// Features we ask for: ping, keys, power, volume, app links.
    private static let features = 1 | 2 | 32 | 64 | 512
    private var remote: BoxConnection?
    private var pairingConnection: BoxConnection?
    private var connectTask: Task<Bool, Never>?
    private var readyWaiter: CheckedContinuation<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey) {
            box = try? JSONDecoder().decode(Box.self, from: data)
        }
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// True when keys for the TV's current foreground app should go to the box.
    func handles(foregroundAppID: String?) -> Bool {
        guard enabled, let box, box.paired, let input = box.inputID else { return false }
        return ControlRouting.appID(forInput: input) == foregroundAppID
    }

    func link(input: String?) { box?.inputID = input }

    var statusText: String {
        let name = box?.name ?? "Kutu"
        switch state {
        case .connected: return "\(name) Wi-Fi ile kumanda ediliyor."
        case .connecting: return "\(name) kutusuna bağlanılıyor…"
        case .failed(let reason): return reason
        case .idle: return "Tuşlar \(name) kutusuna Wi-Fi ile gönderilecek."
        }
    }

    func forget() {
        disconnect(); cancelPairing()
        box = nil
        try? BoxCertificate.reset()
    }

    // MARK: Pairing

    /// Connects to the pairing port; on success the box shows a 6-character code.
    func startPairing(host: String, name: String, inputID: String?) async {
        cancelPairing(); disconnect()
        pairing = .starting
        box = Box(host: host, name: name, inputID: inputID ?? box?.inputID, paired: false)
        do {
            let connection = BoxConnection(host: host, port: 6467, identity: try BoxCertificate.identity())
            pairingConnection = connection
            connection.onMessage = { [weak self] frame in Task { @MainActor in self?.handlePairing(frame) } }
            connection.onClose = { [weak self] error in
                Task { @MainActor in
                    guard let self, self.pairingConnection === connection else { return }
                    self.pairingConnection = nil
                    if self.pairing != .done, self.pairing != .idle {
                        self.pairing = .failed(Self.closeReason(error) ?? "Kutu eşleştirmeyi kapattı. Yeniden dene.")
                    }
                }
            }
            try await connection.start()
            connection.send(Self.pairingMessage { $0.message(10) { r in r.string(1, "atvremote"); r.string(2, "LG Kumanda") } })
        } catch {
            pairing = .failed(error.localizedDescription)
        }
    }

    /// Sends the code shown on the box. The first two characters are a checksum of the rest.
    func finishPairing(code: String) {
        guard pairing == .waitingForCode, let connection = pairingConnection else { return }
        guard let server = connection.serverCertificate.flatMap(BoxCertificate.rsaNumbers),
              let client = (try? BoxCertificate.certificate()).flatMap(BoxCertificate.rsaNumbers) else {
            pairing = .failed("Kutunun sertifikası okunamadı. Yeniden dene."); return
        }
        guard let secret = BoxCertificate.pairingSecret(code: code, client: client, server: server) else {
            pairing = .waitingForCode
            pairingCodeError = "Kod hatalı. Kutunun ekranındaki 6 karakteri kontrol et."
            return
        }
        pairingCodeError = nil
        pairing = .verifying
        connection.send(Self.pairingMessage { $0.message(40) { $0.bytes(1, secret) } })
    }
    @Published private(set) var pairingCodeError: String?

    func cancelPairing() {
        pairingConnection?.onClose = nil
        pairingConnection?.cancel(); pairingConnection = nil
        if pairing != .done { pairing = .idle }
    }

    private func handlePairing(_ frame: Data) {
        guard let message = ProtoMessage(frame) else { return }
        guard message.int(2) == 200 else {
            pairing = .failed(pairing == .verifying ? "Kod kabul edilmedi. Yeniden eşleştir." : "Kutu eşleştirmeyi reddetti.")
            cancelPairingConnectionOnly(); return
        }
        if message.has(11) {          // pairing request ack: offer a 6-character hexadecimal code shown on the box
            pairingConnection?.send(Self.pairingMessage { $0.message(20) { o in
                o.message(1) { e in e.varint(1, 3); e.varint(2, 6) }
                o.varint(3, 1)
            } })
        } else if message.has(20) {   // options: confirm the configuration
            pairingConnection?.send(Self.pairingMessage { $0.message(30) { c in
                c.message(1) { e in e.varint(1, 3); e.varint(2, 6) }
                c.varint(2, 1)
            } })
        } else if message.has(31) {   // configuration ack: the box now shows the code
            pairing = .waitingForCode
        } else if message.has(41) {   // secret ack: paired
            pairing = .done
            box?.paired = true
            cancelPairingConnectionOnly()
            Task { _ = await connect() }
        }
    }
    private func cancelPairingConnectionOnly() {
        pairingConnection?.onClose = nil
        pairingConnection?.cancel(); pairingConnection = nil
    }
    private static func pairingMessage(_ build: (inout ProtoWriter) -> Void) -> Data {
        var w = ProtoWriter()
        w.varint(1, 2); w.varint(2, 200)
        build(&w)
        return w.data
    }

    // MARK: Remote

    /// Opens the remote session if needed. Returns false if the box cannot be reached.
    @discardableResult func connect() async -> Bool {
        if state == .connected { return true }
        if let connectTask { return await connectTask.value }
        guard let box, box.paired else { return false }
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            self.state = .connecting
            self.isReady = false
            do {
                let connection = BoxConnection(host: box.host, port: 6466, identity: try BoxCertificate.identity())
                connection.onMessage = { [weak self] frame in Task { @MainActor in self?.handleRemote(frame, from: connection) } }
                connection.onClose = { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.remote === connection else { return }
                        self.remote = nil
                        self.isReady = false
                        self.readyWaiter?.resume(); self.readyWaiter = nil
                        self.state = .failed(Self.closeReason(error) ?? "Kutu bağlantısı kapandı.")
                    }
                }
                self.remote = connection
                try await connection.start()
                // The box first configures the session; keys sent before it is active are ignored.
                let ready = await self.waitUntilReady(timeout: 5)
                guard ready, self.remote === connection else {
                    connection.onClose = nil; connection.cancel(); self.remote = nil
                    self.state = .failed("Kutu kumanda oturumunu başlatmadı. Kutu açık mı?")
                    return false
                }
                self.state = .connected
                return true
            } catch {
                self.remote = nil
                self.state = .failed(error.localizedDescription)
                return false
            }
        }
        connectTask = task
        let result = await task.value
        connectTask = nil
        return result
    }

    private var isReady = false
    private func markReady() {
        isReady = true
        readyWaiter?.resume(); readyWaiter = nil
    }
    private func waitUntilReady(timeout: Double) async -> Bool {
        if isReady { return true }
        let timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self?.readyWaiter?.resume(); self?.readyWaiter = nil
        }
        await withCheckedContinuation { readyWaiter = $0 }
        timer.cancel()
        return isReady
    }

    func disconnect() {
        remote?.onClose = nil
        remote?.cancel(); remote = nil
        isReady = false
        readyWaiter?.resume(); readyWaiter = nil
        state = .idle
    }

    /// Sends a remote key to the box, connecting first if needed. Returns false if the key has no box equivalent.
    @discardableResult func send(_ key: RemoteKey) -> Bool {
        guard let code = Self.keyCode(for: key) else { return false }
        Task {
            guard await connect(), let remote else { return }
            var w = ProtoWriter()
            w.message(10) { $0.varint(1, code); $0.varint(2, 3) }
            remote.send(w.data)
        }
        return true
    }

    private func handleRemote(_ frame: Data, from connection: BoxConnection) {
        guard let message = ProtoMessage(frame) else { return }
        var reply = ProtoWriter()
        if let configure = message.message(1) {
            deviceModel = configure.message(2)?.string(1) ?? deviceModel
            let supported = configure.int(1) ?? Self.features
            reply.message(1) { c in
                c.varint(1, Self.features & supported)
                c.message(2) { d in d.varint(3, 1); d.string(4, "1"); d.string(5, "atvremote"); d.string(6, "1.0.0") }
            }
        } else if message.has(2) {
            reply.message(2) { $0.varint(1, Self.features) }
            markReady()
        } else if message.has(40) {
            markReady()
        } else if let ping = message.message(8) {
            reply.message(9) { $0.varint(1, ping.int(1) ?? 0) }
        } else if let ime = message.message(20) {
            currentApp = ime.message(1)?.string(12) ?? currentApp
        }
        if !reply.data.isEmpty { connection.send(reply.data) }
    }

    /// Android key codes for the LG remote keys; keys without a box meaning (volume, mute) stay on the TV.
    nonisolated static func keyCode(for key: RemoteKey) -> Int? {
        switch key {
        case .up: return 19
        case .down: return 20
        case .left: return 21
        case .right: return 22
        case .enter: return 23
        case .home: return 3
        case .back, .exit: return 4
        case .menu: return 82
        case .guide: return 172
        case .info: return 165
        case .settings: return 176
        case .red: return 183
        case .green: return 184
        case .yellow: return 185
        case .blue: return 186
        case .zero: return 7
        case .one: return 8
        case .two: return 9
        case .three: return 10
        case .four: return 11
        case .five: return 12
        case .six: return 13
        case .seven: return 14
        case .eight: return 15
        case .nine: return 16
        case .previous: return 229
        case .subtitles: return 175
        case .teletext: return 233
        case .channelUp: return 166
        case .channelDown: return 167
        case .play: return 126
        case .pause: return 127
        case .stop: return 86
        case .rewind: return 89
        case .fastForward: return 90
        case .list, .dash: return nil
        }
    }

    private static func closeReason(_ error: Error?) -> String? {
        guard let error else { return nil }
        if let nw = error as? NWError { return BoxConnection.describe(nw) }
        return error.localizedDescription
    }

    private func persist() {
        if let box, let data = try? JSONEncoder().encode(box) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.storeKey) }
    }
}
