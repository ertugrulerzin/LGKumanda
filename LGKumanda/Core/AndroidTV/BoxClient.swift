import Foundation
import Network
import Security

/// Android TV boxes (set-top boxes, Google TV and similar) controlled over Wi-Fi with the Android TV Remote
/// protocol v2, instead of HDMI-CEC. Pairing (port 6467) happens once per box with a code shown on the box;
/// keys then go to port 6466. Several boxes can be saved; one is active (connected) at a time. While the TV
/// shows the HDMI input a box is linked to, the remote's keys are sent to that box.
@MainActor final class BoxClient: ObservableObject {
    struct Box: Codable, Equatable, Identifiable {
        var id = UUID()
        var host: String
        /// Name found on the network or typed by the user.
        var name: String
        /// True once the user renamed the box; otherwise the linked TV input's title is shown.
        var customName = false
        /// TV input the box is connected to, e.g. "HDMI_3".
        var inputID: String?
        var paired = false
        var enabled = true

        init(id: UUID = UUID(), host: String, name: String, customName: Bool = false, inputID: String? = nil, paired: Bool = false, enabled: Bool = true) {
            self.id = id; self.host = host; self.name = name; self.customName = customName
            self.inputID = inputID; self.paired = paired; self.enabled = enabled
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            host = try c.decode(String.self, forKey: .host)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            customName = try c.decodeIfPresent(Bool.self, forKey: .customName) ?? false
            inputID = try c.decodeIfPresent(String.self, forKey: .inputID)
            paired = try c.decodeIfPresent(Bool.self, forKey: .paired) ?? false
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
        /// Shown on the remote's tab: the user's name, else the TV input's title (e.g. "TVP"), else the network name.
        func title(inputs: [TVItem]) -> String {
            let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if customName, !typed.isEmpty { return typed }
            if let inputID, let input = inputs.first(where: { $0.id == inputID }) {
                let label = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty, label.uppercased().replacingOccurrences(of: " ", with: "_") != inputID.uppercased() { return label }
            }
            if !typed.isEmpty { return typed }
            return inputID.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "Android TV"
        }
    }
    enum State: Equatable { case idle, connecting, connected, failed(String) }
    enum PairingState: Equatable { case idle, starting, waitingForCode, verifying, done, failed(String) }

    @Published private(set) var boxes: [Box] = [] { didSet { persist() } }
    @Published private(set) var activeID: UUID? { didSet { UserDefaults.standard.set(activeID?.uuidString, forKey: Self.activeKey) } }
    /// The active box: the one being paired, connected or edited.
    var box: Box? { boxes.first { $0.id == activeID } }
    var pairedBoxes: [Box] { boxes.filter(\.paired) }
    @Published private(set) var state: State = .idle
    @Published private(set) var pairing: PairingState = .idle
    @Published private(set) var currentApp = ""
    @Published private(set) var deviceModel = ""
    /// Whether keys go to the active box over Wi-Fi.
    var enabled: Bool {
        get { box?.enabled ?? false }
        set {
            updateActive { $0.enabled = newValue }
            if !newValue { disconnect() }
        }
    }

    private static let storeKey = "androidTVBoxes"
    private static let activeKey = "androidTVBoxes.active"
    private static let legacyKey = "androidTVBox"
    private static let legacyEnabledKey = "androidTVBox.enabled"
    var onCommandError: ((String) -> Void)?
    private var remoteSession = BoxRemoteSession()
    private var generation = UUID()
    private var keyTask: Task<Void, Never>?
    private var remote: BoxConnection?
    private var pairingConnection: BoxConnection?
    private var connectTask: Task<Bool, Never>?
    private var readyWaiter: CheckedContinuation<Void, Never>?
    private var lastHeard: ContinuousClock.Instant?

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.storeKey), let saved = try? JSONDecoder().decode([Box].self, from: data) {
            boxes = saved
        } else if let data = defaults.data(forKey: Self.legacyKey), var single = try? JSONDecoder().decode(Box.self, from: data) {
            // Earlier builds kept a single box; carry its pairing over unchanged.
            single.enabled = defaults.object(forKey: Self.legacyEnabledKey) as? Bool ?? true
            boxes = [single]
        }
        let saved = defaults.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))
        activeID = boxes.contains { $0.id == saved } ? saved : boxes.first(where: \.paired)?.id
    }
    private func updateActive(_ change: (inout Box) -> Void) {
        guard let index = boxes.firstIndex(where: { $0.id == activeID }) else { return }
        change(&boxes[index])
    }
    /// Makes a saved box the active one; an open connection to another box is closed.
    func select(_ id: UUID) {
        guard id != activeID, boxes.contains(where: { $0.id == id }) else { return }
        cancelPairing(); disconnect()
        activeID = id
    }
    /// Clears the active box so the setup screen offers to pair a new one.
    func beginAdding() {
        cancelPairing(); disconnect()
        activeID = nil
    }
    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updateActive { $0.name = trimmed; $0.customName = !trimmed.isEmpty }
    }

    /// Set while the user explicitly picks the TV remote on the box's input; keys then stay on the TV.
    @Published var suspended = false
    /// The paired box plugged into the input the TV currently shows, if any.
    func box(forForeground foregroundAppID: String?) -> Box? {
        guard let foregroundAppID else { return nil }
        return boxes.first { $0.paired && $0.enabled && $0.inputID.flatMap(ControlRouting.appID(forInput:)) == foregroundAppID }
    }
    /// True when the TV currently shows the input of a paired box.
    func isLinked(foregroundAppID: String?) -> Bool { box(forForeground: foregroundAppID) != nil }
    /// Sends a TV-remote key to the box on the TV's current input, making it active first.
    func route(_ key: RemoteKey, foregroundAppID: String?) -> Bool {
        guard !suspended, let target = box(forForeground: foregroundAppID) else { return false }
        select(target.id)
        return send(key)
    }
    /// True when keys for the TV's current foreground app should go to the box.
    func handles(foregroundAppID: String?) -> Bool {
        !suspended && isLinked(foregroundAppID: foregroundAppID)
    }

    func link(input: String?) { updateActive { $0.inputID = input } }

    var statusText: String {
        switch state {
        case .connected: return remoteSession.isOn == false ? "Kutu beklemede. Açık değilse kendi kumandasından aç." : "Kutu Wi-Fi ile kumanda ediliyor."
        case .connecting: return "Kutuya bağlanılıyor…"
        case .failed(let reason): return reason
        case .idle: return "Tuşlar kutuya Wi-Fi ile gönderilecek."
        }
    }


    func forget() {
        disconnect(); cancelPairing()
        let removed = activeID
        boxes.removeAll { $0.id == removed }
        activeID = boxes.first(where: \.paired)?.id
        // The client certificate is shared by all boxes; drop it only with the last one.
        if boxes.isEmpty { try? BoxCertificate.reset() }
    }

    // MARK: Pairing

    /// Connects to the pairing port; on success the box shows a 6-character code.
    func startPairing(host: String, name: String, inputID: String?) async {
        cancelPairing(); disconnect()
        pairing = .starting
        if let existing = boxes.first(where: { $0.host == host }) {
            // Re-pairing a saved box keeps its name; the TV's current input (where the code shows) wins.
            activeID = existing.id
            updateActive { $0.paired = false; if let inputID { $0.inputID = inputID } }
        } else {
            let new = Box(host: host, name: name, inputID: inputID)
            boxes.append(new)
            activeID = new.id
        }
        do {
            let connection = BoxConnection(host: host, port: 6467, identity: try BoxCertificate.identity())
            pairingConnection = connection
            connection.onMessage = { [weak self, weak connection] frame in Task { @MainActor in
                guard let connection, self?.pairingConnection === connection else { return }
                self?.handlePairing(frame)
            } }
            connection.onClose = { [weak self, weak connection] error in
                Task { @MainActor in
                    guard let self, let connection, self.pairingConnection === connection else { return }
                    self.pairingConnection = nil
                    if self.pairing != .done, self.pairing != .idle {
                        self.pairing = .failed(Self.closeReason(error) ?? "Kutu eşleştirmeyi kapattı. Yeniden dene.")
                    }
                }
            }
            try await connection.start()
            guard pairingConnection === connection else { return }
            connection.send(Self.pairingMessage { $0.message(10) { r in r.string(1, "atvremote"); r.string(2, "Kumanda") } })
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
        // A box that never finished pairing is not kept.
        if boxes.contains(where: { !$0.paired }) {
            boxes.removeAll { !$0.paired }
            if !boxes.contains(where: { $0.id == activeID }) { activeID = boxes.first?.id }
        }
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
            updateActive { $0.paired = true }
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
        // The box pings every few seconds. Silence means it gave the session to another
        // remote (it keeps only one) without closing ours, so open a fresh one.
        if state == .connected, let lastHeard, ContinuousClock.now - lastHeard > .seconds(12) {
            remote?.onClose = nil; remote?.cancel(); remote = nil
            isReady = false
            state = .idle
        }
        if state == .connected { return true }
        if let connectTask { return await connectTask.value }
        guard let box, box.paired else { return false }
        let token = generation
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            self.state = .connecting
            self.isReady = false
            self.remoteSession = BoxRemoteSession()
            do {
                let connection = BoxConnection(host: box.host, port: 6466, identity: try BoxCertificate.identity())
                connection.onMessage = { [weak self, weak connection] frame in Task { @MainActor in
                    guard let connection else { return }
                    self?.handleRemote(frame, from: connection)
                } }
                connection.onClose = { [weak self, weak connection] error in
                    Task { @MainActor in
                        guard let self, let connection, self.generation == token, self.remote === connection else { return }
                        self.remote = nil
                        self.isReady = false
                        self.readyWaiter?.resume(); self.readyWaiter = nil
                        self.state = .failed(Self.closeReason(error) ?? "Kutu bağlantısı kapandı.")
                    }
                }
                self.remote = connection
                self.lastHeard = .now
                try await connection.start()
                guard self.generation == token, self.remote === connection, !Task.isCancelled else {
                    connection.cancel(); return false
                }
                // The box first configures the session; keys sent before it is active are ignored.
                let ready = await self.waitUntilReady(timeout: 5)
                guard ready, self.generation == token, self.remote === connection, !Task.isCancelled else {
                    connection.onClose = nil; connection.cancel()
                    if self.generation == token, self.remote === connection {
                        self.remote = nil
                        self.state = .failed("Kutu kumanda oturumunu başlatmadı. Kutu açık mı?")
                    }
                    return false
                }
                self.state = .connected
                return true
            } catch {
                guard self.generation == token, !Task.isCancelled else { return false }
                self.remote = nil
                self.state = .failed(error.localizedDescription)
                return false
            }
        }
        connectTask = task
        let result = await task.value
        if generation == token { connectTask = nil }
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
            do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) } catch { return }
            self?.readyWaiter?.resume(); self?.readyWaiter = nil
        }
        await withCheckedContinuation { readyWaiter = $0 }
        timer.cancel()
        return isReady
    }

    func disconnect() {
        generation = UUID()
        connectTask?.cancel(); connectTask = nil
        keyTask?.cancel(); keyTask = nil
        remote?.onClose = nil
        remote?.cancel(); remote = nil
        isReady = false
        readyWaiter?.resume(); readyWaiter = nil
        state = .idle
    }

    /// Sends a remote key to the box, connecting first if needed. Returns false if the key has no box equivalent.
    @discardableResult func send(_ key: RemoteKey) -> Bool {
        guard let code = Self.keyCode(for: key) else { return false }
        return send(code: code)
    }
    /// Android KEYCODE_MEDIA_PLAY_PAUSE: one key that pauses and resumes, like the box's own remote.
    nonisolated static let playPauseCode = 85
    /// Types a channel number on the box (e.g. "119" sends 1, 1, 9). Keys are queued in order.
    @discardableResult func enterChannel(_ number: String) -> Bool {
        let digits = Self.channelDigits(number)
        guard !digits.isEmpty else { return false }
        for code in digits { send(code: code) }
        return true
    }
    /// Android key codes for a typed channel number; KEYCODE_0 is 7. Non-digits are ignored.
    nonisolated static func channelDigits(_ number: String) -> [Int] {
        number.compactMap { $0.wholeNumberValue }.filter { (0...9).contains($0) }.prefix(5).map { 7 + $0 }
    }
    /// Sends an Android key code to the box, connecting first if needed.
    @discardableResult func send(code: Int) -> Bool {
        let previous = keyTask
        let token = generation
        keyTask = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == token, self.enabled, !Task.isCancelled else { return }
            guard await self.connect(), let remote = self.remote else {
                guard self.generation == token, !Task.isCancelled else { return }
                self.onCommandError?(self.statusText)
                return
            }
            guard self.generation == token, self.enabled, !Task.isCancelled else { return }
            var w = ProtoWriter()
            w.message(10) { $0.varint(1, code); $0.varint(2, 3) }
            remote.send(w.data)
        }
        return true
    }

    /// Replaces the text in the box's focused text field (Android TV keyboard). Queued after keys.
    @discardableResult func sendText(_ text: String) -> Bool {
        guard box?.paired == true, enabled, !text.isEmpty else { return false }
        let previous = keyTask
        let token = generation
        keyTask = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == token, self.enabled, !Task.isCancelled else { return }
            guard await self.connect(), let remote = self.remote else {
                guard self.generation == token, !Task.isCancelled else { return }
                self.onCommandError?(self.statusText)
                return
            }
            guard self.generation == token, !Task.isCancelled else { return }
            guard self.remoteSession.supportsText else {
                self.onCommandError?("Kutu Wi-Fi ile metin girişini desteklemiyor. Yön tuşlarıyla ekran klavyesini kullan.")
                return
            }
            remote.send(self.remoteSession.textEdit(text))
        }
        return true
    }

    private func handleRemote(_ frame: Data, from connection: BoxConnection) {
        guard remote === connection else { return }
        lastHeard = .now
        let reply = remoteSession.receive(frame)
        deviceModel = remoteSession.model
        currentApp = remoteSession.currentApp
        guard remoteSession.supportsKeys else {
            state = .failed("Kutu Wi-Fi kumanda tuşlarını desteklediğini bildirmedi.")
            connection.cancel()
            return
        }
        if !reply.isEmpty { connection.send(reply) }
        if remoteSession.ready { markReady() }
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
        if let data = try? JSONEncoder().encode(boxes) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
        UserDefaults.standard.removeObject(forKey: Self.legacyKey)
    }
}
