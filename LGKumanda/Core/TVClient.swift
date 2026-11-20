import Foundation
import CryptoKit
import Security

private final class TVTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String
    let fingerprint: String?
    let received: @Sendable (String) -> Void
    init(host: String, fingerprint: String?, received: @escaping @Sendable (String) -> Void) {
        self.host = host; self.fingerprint = fingerprint; self.received = received
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        guard challenge.protectionSpace.host == host, TVProtocol.validHost(host),
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let cert = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format: "%02x", $0) }.joined()
        guard fingerprint == nil || fingerprint == digest else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        // Trust on first pairing; subsequent connections must present the same certificate.
        received(digest)
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

@MainActor final class TVClient: ObservableObject {
    @Published var televisions: [Television] = [] { didSet { persist() } }
    @Published private(set) var selected: Television?
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var powerState: TVPowerState = .unknown
    /// A wake packet went out and the TV has not answered yet.
    @Published private(set) var waking = false
    var connectionLabel: String { powerState.isStandby ? "TV kapalı" : state.label }
    @Published private(set) var volume: Int?
    @Published private(set) var muted = false
    @Published private(set) var pointerReady = false
    @Published private(set) var apps: [TVItem] = []
    @Published private(set) var inputs: [TVItem] = []
    @Published private(set) var channels: [TVItem] = []
    @Published private(set) var libraryReady = false
    @Published private(set) var foregroundAppID: String?
    @Published var browserAddressRequested = false
    var browserAppID: String? { apps.first { $0.id.hasPrefix("com.webos.app.browser") }?.id }
    @Published var controlMode: ControlMode = .automatic {
        didSet { if let selected { preferences.set(controlMode.rawValue, forKey: "controlMode.\(selected.id)") } }
    }
    var controlContext: ControlContext { controlMode.context(foregroundID: foregroundAppID) }
    var isHDMIActive: Bool { foregroundAppID?.hasPrefix("com.webos.app.hdmi") == true }
    var isBrowserActive: Bool { foregroundAppID != nil && foregroundAppID == browserAppID }
    /// Active HDMI input, when the TV reports no SIMPLINK device on it (remote keys cannot reach the box).
    var activeInputWithoutSimplink: TVItem? {
        guard let input = inputs.first(where: { ControlRouting.appID(forInput: $0.id) == foregroundAppID }) else { return nil }
        return input.simplinkName == nil ? input : nil
    }
    var controlLabel: String {
        if controlContext == .television { return "TV kanalları" }
        if let input = inputs.first(where: { ControlRouting.appID(forInput: $0.id) == foregroundAppID }) { return "\(input.title) · HDMI" }
        return apps.first(where: { $0.id == foregroundAppID })?.title ?? "Uygulama / HDMI"
    }
    @Published var error: String?
    @Published var notice: String?
    @Published private(set) var webVideoSession: WebVideoSession?
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var pointer: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var pointerReceiver: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var generation = UUID()
    private var certificate: String?
    private var addressRecoveryTask: Task<Void, Never>?
    private var addressRecoveryAllowed = true
    private var persistAddressOnRegistration = false
    private var motionTask: Task<Void, Never>?
    private var motionToken = UUID()
    private var pendingMotion = (x: 0, y: 0)
    private struct Pending {
        let continuation: CheckedContinuation<[String: Any], Error>
        let timer: Task<Void, Never>
    }
    private var pending: [String: Pending] = [:]

    enum Failure: LocalizedError {
        case message(String), rejected(String), timeout
        var errorDescription: String? {
            switch self {
            case .message(let text), .rejected(let text): return text
            case .timeout: return "TV komuta yanıt vermedi. Yeniden dene."
            }
        }
    }

    private let preferences: UserDefaults
    private let readDeviceIdentity: @Sendable (String, String) async -> String?
    private let findTVAddress: @MainActor (Television, String) async -> TVAddressRecovery.Result
    private let probeWakeMAC: @Sendable (String) async -> String?
    init(preferences: UserDefaults = .standard,
         wakeMACProbe: @escaping @Sendable (String) async -> String? = { await WakeOnLAN.discoverMAC(host: $0) },
         identityReader: @escaping @Sendable (String, String) async -> String? = { await TVIdentityProbe.read(host: $0, fingerprint: $1) },
         addressFinder: @escaping @MainActor (Television, String) async -> TVAddressRecovery.Result = { await TVAddressRecovery.find($0, fingerprint: $1) }) {
        self.preferences = preferences
        self.readDeviceIdentity = identityReader
        self.findTVAddress = addressFinder
        self.probeWakeMAC = wakeMACProbe
        if let data = preferences.data(forKey: "televisions"),
           let saved = try? JSONDecoder().decode([Television].self, from: data) {
            televisions = saved
        }
        let id = preferences.string(forKey: "selectedTV")
        selected = televisions.first { $0.id.uuidString == id } ?? televisions.first
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(televisions) { preferences.set(data, forKey: "televisions") }
    }
    func save(_ tv: Television) {
        if let index = televisions.firstIndex(where: { $0.id == tv.id }) { televisions[index] = tv }
        else { televisions.append(tv) }
        connect(to: tv)
    }
    func remove(_ tv: Television) {
        if selected?.id == tv.id { disconnect(); selected = nil; preferences.removeObject(forKey: "selectedTV") }
        televisions.removeAll { $0.id == tv.id }
        preferences.removeObject(forKey: "controlMode.\(tv.id)")
        KeychainStore.delete("key.\(tv.id)"); KeychainStore.delete("cert.\(tv.id)")
    }
    func resetPairing() {
        guard let tv = selected else { return }
        disconnect()
        KeychainStore.delete("key.\(tv.id)"); KeychainStore.delete("cert.\(tv.id)")
        connect(to: tv)
    }
    private var wakeTask: Task<Void, Never>?
    private var powerOnWatch: Task<Void, Never>?
    /// A booting TV can briefly report standby; such reports are ignored until this instant.
    private var ignoreStandbyUntil: ContinuousClock.Instant?
    func disconnect() {
        powerOnWatch?.cancel(); powerOnWatch = nil
        waking = false
        wakeTask?.cancel(); wakeTask = nil
        resetConnection()
    }
    /// Closes the current connection but keeps a running power-on watch alive.
    private func resetConnection() {
        #if DEBUG
        if previewMode { return }
        #endif
        addressRecoveryTask?.cancel(); addressRecoveryTask = nil
        persistAddressOnRegistration = false
        webVideoSession = nil
        stopPointerMotion()
        generation = UUID()
        receiver?.cancel(); pointerReceiver?.cancel(); deadline?.cancel(); heartbeat?.cancel()
        socket?.cancel(with: .goingAway, reason: nil); pointer?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        socket = nil; pointer = nil; session = nil
        for item in pending.values { item.timer.cancel(); item.continuation.resume(throwing: Failure.message("Bağlantı kapandı.")) }
        pending.removeAll()
        powerState = .unknown
        state = .disconnected; pointerReady = false; volume = nil; muted = false
        foregroundAppID = nil; libraryReady = false
        apps = []; inputs = []; channels = []
    }
    func connect(to tv: Television) {
        #if DEBUG
        if previewMode { return }
        #endif
        connect(to: tv, allowAddressRecovery: true, persistNewAddress: false)
    }
    private func connect(to tv: Television, allowAddressRecovery: Bool, persistNewAddress: Bool) {
        resetConnection(); error = nil; notice = nil
        guard TVProtocol.validHost(tv.host) else { error = "TV'nin yerel IPv4 adresini gir (ör. 192.168.1.50)."; return }
        selected = tv; preferences.set(tv.id.uuidString, forKey: "selectedTV")
        controlMode = ControlMode(rawValue: preferences.string(forKey: "controlMode.\(tv.id)") ?? "") ?? .automatic
        state = .connecting; certificate = nil
        addressRecoveryAllowed = allowAddressRecovery
        persistAddressOnRegistration = persistNewAddress
        let token = generation
        let delegate = TVTrustDelegate(host: tv.host, fingerprint: KeychainStore.read("cert.\(tv.id)")) { [weak self] fingerprint in
            Task { @MainActor in if self?.generation == token { self?.certificate = fingerprint } }
        }
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        let url = URL(string: "\(tv.secure ? "wss" : "ws")://\(tv.host):\(tv.secure ? 3001 : 3000)")!
        let socket = session.webSocketTask(with: url)
        self.socket = socket
        receiver = Task { [weak self] in
            do {
                // DHCP may have given the old address to another LG TV with
                // the same factory certificate. Verify UUID before any key.
                if tv.secure, let expectedUUID = tv.deviceUUID,
                   let fingerprint = KeychainStore.read("cert.\(tv.id)") {
                    let actualUUID = await self?.readDeviceIdentity(tv.host, fingerprint)
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    guard actualUUID == expectedUUID else {
                        self.connectionFailed(token: token, message: "Kayıtlı TV bu adreste doğrulanamadı.")
                        return
                    }
                }
                guard self?.generation == token, !Task.isCancelled else { return }
                socket.resume()
                try await self?.send(TVProtocol.registration(key: KeychainStore.read("key.\(tv.id)")))
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.generation == token else { return }
                    self.consume(message, token: token)
                }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.connectionFailed(token: token, message: "TV bağlantısı kesildi. TV'nin açık olduğunu, aynı Wi-Fi'da olduğunu ve yerel ağ iznini kontrol et. \(error.localizedDescription)")
            }
        }
        // While a woken TV boots, a stalled attempt is dropped quickly and the watch retries.
        setDeadline(seconds: waking ? 4 : 20, token: token, message: "TV'ye ulaşılamadı. IP adresini kontrol edip yeniden dene.")
    }
    private func setDeadline(seconds: UInt64, token: UUID, message: String) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            guard let self, self.generation == token, self.state != .connected else { return }
            self.connectionFailed(token: token, message: message)
        }
    }
    private func connectionFailed(token: UUID, message: String) {
        guard generation == token else { return }
        guard addressRecoveryAllowed, state != .pairing, let tv = selected, tv.secure, tv.deviceUUID != nil,
              televisions.contains(where: { $0.id == tv.id }),
              let fingerprint = KeychainStore.read("cert.\(tv.id)") else {
            resetConnection()
            // While waiting for a TV to boot, failed attempts are retried silently.
            if powerOnWatch == nil { error = message }
            return
        }
        resetConnection()
        let recoveryToken = generation
        state = .connecting
        error = nil
        notice = "TV'nin güncel ağ adresi aranıyor…"
        let finder = findTVAddress
        addressRecoveryTask = Task { [weak self] in
            let result = await finder(tv, fingerprint)
            guard let self, self.generation == recoveryToken, !Task.isCancelled,
                  self.selected?.id == tv.id else { return }
            self.addressRecoveryTask = nil
            switch result {
            case .found(let updated):
                // Keep the UUID, saved key, pin and shortcuts. Commit the new
                // address only after the pinned TV accepts registration.
                self.connect(to: updated, allowAddressRecovery: false, persistNewAddress: updated.host != tv.host)
                self.notice = updated.host == tv.host ? "TV yeniden bulundu; bağlanılıyor…" : "TV'nin yeni adresi bulundu; bağlanılıyor…"
            case .ambiguous:
                self.disconnect(); self.notice = nil
                self.error = "Birden fazla TV eşleşti. Cihazlar bölümünden doğru televizyonu seç."
            case .permissionDenied:
                self.disconnect(); self.notice = nil
                self.error = "Yerel ağ izni kapalı. Ayarlar'dan Kumanda için Yerel Ağ iznini aç."
            case .notFound, .cancelled:
                self.disconnect(); self.notice = nil
                self.error = "Kayıtlı TV ağda bulunamadı. TV'nin açık ve aynı yerel ağda olduğunu kontrol edip yeniden bağlan."
            }
        }
    }
    /// Reuse the saved record when manual discovery finds its new address.
    /// Ambiguous pins never merge records or transfer pairing credentials.
    func savedTelevision(for candidate: Television, candidates: [Television], fingerprints: [String: String]) -> Television? {
        if let existing = televisions.first(where: { $0.host == candidate.host }) {
            if let expected = existing.deviceUUID, let actual = candidate.deviceUUID, expected != actual { return nil }
            if let expected = KeychainStore.read("cert.\(existing.id)"), let actual = fingerprints[candidate.host], expected != actual { return nil }
            return existing
        }
        guard let deviceUUID = candidate.deviceUUID, let fingerprint = fingerprints[candidate.host],
              Set(candidates.filter { $0.deviceUUID == deviceUUID && fingerprints[$0.host] == fingerprint }.map(\.host)).count == 1 else { return nil }
        let matches = televisions.filter { $0.secure && $0.deviceUUID == deviceUUID && KeychainStore.read("cert.\($0.id)") == fingerprint }
        guard matches.count == 1, var saved = matches.first else { return nil }
        saved.host = candidate.host
        return saved
    }
    private func consume(_ message: URLSessionWebSocketTask.Message, token: UUID) {
        let data: Data
        switch message { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: return }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = object["type"] as? String ?? ""
        let id = object["id"] as? String ?? ""
        let payload = object["payload"] as? [String: Any] ?? [:]
        if type == "registered" {
            guard state != .connected, let tv = selected, let key = payload["client-key"] as? String else { return }
            guard KeychainStore.save(key, account: "key.\(tv.id)") else {
                disconnect(); error = "Eşleştirme anahtarı güvenle kaydedilemedi. Yeniden dene."; return
            }
            if let certificate, !KeychainStore.save(certificate, account: "cert.\(tv.id)") {
                disconnect(); error = "TV sertifikası kaydedilemedi. Yeniden eşleştir."; return
            }
            if persistAddressOnRegistration, let index = televisions.firstIndex(where: { $0.id == tv.id }) {
                televisions[index].host = tv.host
                selected = televisions[index]
                notice = "TV'nin IP adresi otomatik güncellendi."
            }
            persistAddressOnRegistration = false
            addressRecoveryAllowed = true
            state = .connected; deadline?.cancel()
            if waking { waking = false; notice = nil }
            Task { await bootstrap(token: token) }
            heartbeat = Task { [weak self] in
                var queryPower = true
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(5))
                        guard let self, self.generation == token, self.state == .connected else { return }
                        if queryPower {
                            do {
                                let payload = try await self.request("com.webos.service.tvpower/power/getPowerState", timeout: .seconds(3))
                                guard self.generation == token else { return }
                                self.updatePowerState(payload)
                            } catch Failure.rejected {
                                // Older firmware may not offer the power API.
                                queryPower = false
                            }
                        }
                        guard self.generation == token, !Task.isCancelled else { return }
                        try await self.socket?.ping(timeout: .seconds(3))
                    } catch {
                        guard let self, !Task.isCancelled, self.generation == token else { return }
                        self.connectionFailed(token: token, message: "TV yanıt vermiyor. Bağlantı yeniden kontrol ediliyor.")
                        return
                    }
                }
            }
        } else if type == "response", id == "register" {
            state = .pairing
            setDeadline(seconds: 90, token: token, message: "Eşleştirme onaylanmadı. TV ekranındaki isteği kabul edip yeniden dene.")
        } else if type == "error", id == "register" {
            disconnect(); error = "TV eşleştirmeyi reddetti. TV ekranından bağlantıya izin ver. Gerekirse yeniden eşleştir."
        } else if id == "power" {
            if type == "response", payload["returnValue"] as? Bool != false { updatePowerState(payload) }
        } else if id == "foreground" {
            if let app = payload["appId"] as? String { foregroundAppID = app }
        } else if id == "audio" {
            let status = TVProtocol.audioStatus(payload)
            if let value = status.volume { volume = value }
            if let value = status.muted { muted = value }
        } else if let item = pending.removeValue(forKey: id) {
            item.timer.cancel()
            if type == "error" || payload["returnValue"] as? Bool == false {
                let detail = object["error"] as? String ?? payload["errorText"] as? String ?? "İşlem desteklenmiyor."
                item.continuation.resume(throwing: Failure.rejected("TV komutu reddetti: \(detail)"))
            } else { item.continuation.resume(returning: payload) }
        }
    }
    private func send(_ object: [String: Any]) async throws {
        #if DEBUG
        if previewMode { return }
        #endif
        guard let socket else { throw Failure.message("Önce bir TV'ye bağlan.") }
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    #if DEBUG
    /// Screenshot/demo mode: commands succeed without a TV on the network.
    var previewMode = false
    #endif
    func request(_ uri: String, _ payload: [String: Any] = [:], timeout: Duration = .seconds(10)) async throws -> [String: Any] {
        #if DEBUG
        if previewMode { return [:] }
        #endif
        guard state == .connected else { throw Failure.message("Önce bir TV'ye bağlan.") }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task { [weak self] in
                do { try await Task.sleep(for: timeout) } catch { return }
                if let item = self?.pending.removeValue(forKey: id) {
                    item.continuation.resume(throwing: Failure.timeout)
                }
            }
            pending[id] = Pending(continuation: continuation, timer: timer)
            Task {
                do { try await send(TVProtocol.request(id: id, uri: uri, payload: payload)) }
                catch {
                    if let item = pending.removeValue(forKey: id) { item.timer.cancel(); item.continuation.resume(throwing: error) }
                }
            }
        }
    }
    func command(_ uri: String, _ payload: [String: Any] = [:]) {
        let token = generation
        Task { do { _ = try await request(uri, payload) } catch { if generation == token { self.error = error.localizedDescription } } }
    }
    /// Arrows and OK move a highlight between links in the TV browser instead of needing the pointer (see WebFocus).
    var webFocusEnabled: Bool { preferences.object(forKey: "webFocus") as? Bool ?? true }
    private var webFocusQueue: Task<Void, Never>?
    /// True after a web video was stretched and clicked; rewind/forward then go to the player as real arrow keys.
    private var webPlayerShown = false
    /// Lets another controller (an HDMI box over Wi-Fi) take keys; returns true when it handled the key.
    var keyRouter: ((RemoteKey) -> Bool)?
    func key(_ key: RemoteKey) {
        if keyRouter?(key) == true { return }
        if isBrowserActive, webFocusEnabled, let app = browserAppID, let action = WebFocus.action(for: key) {
            webPlayerShown = false
            let previous = webFocusQueue
            webFocusQueue = Task { [weak self] in
                await previous?.value
                guard let self else { return }
                do {
                    _ = try await self.request("system.launcher/launch", ["id": app, "params": ["target": WebFocus.url(action)]])
                    if key == .enter {
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        self.pointerMessage(key.wireMessage)
                    }
                } catch { self.pointerMessage(key.wireMessage) }
            }
            return
        }
        pointerMessage(key.wireMessage)
    }
    func channel(up: Bool) { sendRouted(ControlRouting.channel(up: up, context: controlContext)) }
    func media(_ action: MediaAction) {
        if isBrowserActive, webFocusEnabled, pointerReady, let app = browserAppID {
            switch action {
            case .play, .pause: playWebVideo(app: app); return
            case .rewind, .fastForward where webPlayerShown:
                pointerMessage((action == .rewind ? RemoteKey.left : .right).wireMessage); return
            default: break
            }
        }
        sendRouted(ControlRouting.media(action, context: controlContext))
    }
    /// Play/pause for a web video: the page script loads the player and stretches it over the page (WebFocus `play`),
    /// then a real click lands in the screen centre. Real clicks reach cross-origin players; page scripts cannot.
    private func playWebVideo(app: String) {
        let previous = webFocusQueue
        let shown = webPlayerShown
        webFocusQueue = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                _ = try await self.request("system.launcher/launch", ["id": app, "params": ["target": WebFocus.url(.play)]])
                // A first press may click the poster and wait for the player to load inside the page.
                try await Task.sleep(nanoseconds: shown ? 300_000_000 : 2_200_000_000)
                guard let pointer = self.pointer else { return }
                for step in PointerJump.absolute(x: 960, y: 540) {
                    try await pointer.send(.string("type:move\ndx:\(step.0)\ndy:\(step.1)\ndown:0\n\n"))
                    try await Task.sleep(nanoseconds: 12_000_000)
                }
                try await pointer.send(.string("type:click\n\n"))
                self.webPlayerShown = true
            } catch { self.error = "Video oynatılamadı. Sayfada oynatıcı veya afiş seçili olsun." }
        }
    }
    private func sendRouted(_ action: RoutedControl) {
        switch action { case .request(let uri): command(uri); case .key(let key): self.key(key) }
    }
    func launchApp(_ id: String) async throws {
        guard apps.contains(where: { $0.id == id }) else { throw Failure.message("Uygulama bu TV'de bulunamadı. Uygulama listesini yenile.") }
        _ = try await request("system.launcher/launch", ["id": id])
        foregroundAppID = id
        if id == browserAppID { browserAddressRequested = true }
    }
    func openBrowser(_ url: URL) async throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let app = browserAppID else {
            throw Failure.message("TV'nin web tarayıcısı bulunamadı veya web adresi geçersiz. Uygulama listesini yenile.")
        }
        _ = try await request("system.launcher/open", ["target": url.absoluteString])
        webVideoSession = nil
        foregroundAppID = app
    }
    func openWebVideo(_ video: WebVideo) async throws {
        let token = generation
        let response = try await request("media.viewer/open", video.openPayload)
        guard token == generation, state == .connected else { throw Failure.message("TV bağlantısı değişti. Yeniden dene.") }
        webVideoSession = WebVideoSession(video: video, viewerID: response["id"] as? String, sessionID: response["sessionId"] as? String)
        if let id = webVideoSession?.viewerID { foregroundAppID = id }
    }
    func controlWebVideo(_ action: MediaAction) async throws {
        guard state == .connected else { throw Failure.message("Önce bir TV'ye bağlan.") }
        if webVideoSession != nil { _ = try await request("media.controls/\(action.rawValue)") }
        else {
            guard pointerReady else { throw Failure.message("TV tuş bağlantısı hazır değil. Yeniden bağlan.") }
            pointerMessage(action.key.wireMessage)
        }
    }
    func switchInput(_ id: String) async throws {
        guard inputs.contains(where: { $0.id == id }) else { throw Failure.message("Giriş bu TV'de bulunamadı. Giriş listesini yenile.") }
        _ = try await request("tv/switchInput", ["inputId": id])
        foregroundAppID = ControlRouting.appID(forInput: id)
    }
    func activate(_ shortcut: TVShortcut) async throws {
        if shortcut.kind == .input { try await switchInput(shortcut.targetID) }
        else { try await launchApp(shortcut.targetID) }
    }
    func movePointer(dx: Int, dy: Int) {
        guard pointerReady else { return }
        pendingMotion.x = max(-64, min(64, pendingMotion.x + dx))
        pendingMotion.y = max(-64, min(64, pendingMotion.y + dy))
        guard motionTask == nil else { return }
        let token = motionToken
        motionTask = Task { [weak self] in
            guard let self else { return }
            defer { if motionToken == token { motionTask = nil } }
            while !Task.isCancelled, motionToken == token, let pointer {
                let dx = max(-32, min(32, pendingMotion.x))
                let dy = max(-32, min(32, pendingMotion.y))
                if dx == 0 && dy == 0 { return }
                pendingMotion.x -= dx; pendingMotion.y -= dy
                do {
                    try await pointer.send(.string("type:move\ndx:\(dx)\ndy:\(dy)\ndown:0\n\n"))
                    try await Task.sleep(nanoseconds: 16_000_000)
                } catch { return }
            }
        }
    }
    /// Moves the pointer to its destination at once, so there is no gliding cursor on screen.
    func jumpPointer(dx: Int, dy: Int) {
        guard pointerReady, let pointer, dx != 0 || dy != 0 else { return }
        stopPointerMotion()
        let steps = PointerJump.steps(dx: dx, dy: dy)
        Task {
            for step in steps {
                do { try await pointer.send(.string("type:move\ndx:\(step.0)\ndy:\(step.1)\ndown:0\n\n")) } catch { return }
            }
        }
    }
    func stopPointerMotion() {
        motionToken = UUID(); motionTask?.cancel(); motionTask = nil; pendingMotion = (0, 0)
    }
    func pointerMessage(_ message: String) {
        guard pointerReady, let pointer else { error = "İşaretçi bağlantısı hazır değil. TV'ye yeniden bağlan; bazı modeller bu tuşları desteklemeyebilir."; return }
        Task { do { try await pointer.send(.string(message)) } catch { self.error = "Tuş gönderilemedi. Yeniden bağlan." } }
    }
    private func bootstrap(token: UUID) async {
        try? await send(TVProtocol.request(id: "power", uri: "com.webos.service.tvpower/power/getPowerState", subscribe: true))
        try? await send(TVProtocol.request(id: "audio", uri: "audio/getVolume", subscribe: true))
        try? await send(TVProtocol.request(id: "foreground", uri: "com.webos.applicationManager/getForegroundAppInfo", subscribe: true))
        do {
            let result = try await request("com.webos.service.networkinput/getPointerInputSocket")
            guard generation == token, let path = result["socketPath"] as? String, let url = URL(string: path),
                  url.host == selected?.host, ["ws", "wss"].contains(url.scheme ?? ""), let session else {
                throw Failure.message("TV işaretçi adresi geçerli değil.")
            }
            let input = session.webSocketTask(with: url); pointer = input; input.resume()
            try await input.ping()
            guard generation == token else { return }
            pointerReady = true
            pointerReceiver = Task { [weak self] in
                do { while !Task.isCancelled { _ = try await input.receive() } }
                catch { guard self?.generation == token, !Task.isCancelled else { return }; self?.pointerReady = false }
            }
        } catch {
            guard generation == token else { return }
            notice = "TV işaretçi bağlantısını açmadı. Yön ve kumanda tuşları kullanılamayabilir."
        }
        guard generation == token else { return }
        async let identity: Void = captureDeviceUUID(token: token)
        await refreshLibrary(reportErrors: false)
        await identity
        await captureWakeIdentity(token: token)
    }
    private func captureDeviceUUID(token: UUID) async {
        guard generation == token, let tv = selected, tv.secure,
              let fingerprint = KeychainStore.read("cert.\(tv.id)") else { return }
        let deviceUUID = await readDeviceIdentity(tv.host, fingerprint)
        guard generation == token, let deviceUUID, selected?.id == tv.id,
              let index = televisions.firstIndex(where: { $0.id == tv.id }), televisions[index].deviceUUID != deviceUUID else { return }
        televisions[index].deviceUUID = deviceUUID
        selected = televisions[index]
    }
    private func captureWakeIdentity(token: UUID) async {
        guard generation == token, let tv = selected, tv.mac.isEmpty else { return }
        var identity: (mac: String, broadcast: String?)?
        if let info = try? await request("com.webos.service.connectionmanager/getinfo"), generation == token {
            let status = (try? await request("com.webos.service.connectionmanager/getStatus")) ?? [:]
            identity = WakeOnLAN.networkIdentity(info: info, status: status, host: tv.host)
        }
        // Some firmware lists no usable MAC; the TV's DIAL reply names the one that wakes it.
        if identity == nil, generation == token, let mac = await probeWakeMAC(tv.host) { identity = (mac, nil) }
        guard generation == token, selected?.id == tv.id, let identity,
              let index = televisions.firstIndex(where: { $0.id == tv.id }), televisions[index].mac.isEmpty else { return }
        var updated = televisions[index]
        updated.mac = identity.mac
        if updated.broadcast == "255.255.255.255", let broadcast = identity.broadcast { updated.broadcast = broadcast }
        televisions[index] = updated
        selected = updated
    }
    func refreshLibrary(reportErrors: Bool = true) async {
        guard state == .connected else { return }
        let token = generation
        libraryReady = false
        defer { if generation == token { libraryReady = true } }
        for (uri, field) in [("com.webos.applicationManager/listLaunchPoints", "launchPoints"), ("tv/getExternalInputList", "devices"), ("tv/getChannelList", "channelList")] {
            do {
                let result = try await request(uri)
                guard generation == token else { return }
                let rows = result[field] as? [[String: Any]] ?? []
                let items = rows.compactMap { row -> TVItem? in
                    let id = row["id"] as? String ?? row["channelId"] as? String
                    guard let id else { return nil }
                    return TVItem(id: id, title: row["title"] as? String ?? row["label"] as? String ?? row["channelName"] as? String ?? id,
                                  detail: field == "devices" ? id.replacingOccurrences(of: "_", with: " ") : row["channelNumber"] as? String ?? "",
                                  simplinkName: field == "devices" ? TVProtocol.simplinkName(row) : nil)
                }
                if field == "launchPoints" { apps = items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
                else if field == "devices" { inputs = items }
                else { channels = items }
            } catch { if reportErrors, generation == token { self.error = error.localizedDescription } }
        }
    }
    func updatePowerState(_ payload: [String: Any]) {
        let reported = TVPowerState.read(payload)
        guard reported != .unknown else { return }
        if reported.isStandby {
            if let until = ignoreStandbyUntil, ContinuousClock.now < until { return }
            // A confirmed power event must not start DHCP recovery and leave
            // the UI claiming the powered-off TV is still connected.
            resetConnection()
            powerState = .standby
            error = nil
            notice = "TV kapalı. Yeniden açmak için Uyandır'ı kullanabilirsin."
            if let tv = selected { watchForPowerOn(tv, requireClosedFirst: true, timeout: nil) }
        } else { powerState = reported }
    }
    func powerOff() {
        Task {
            do {
                guard state == .connected else { throw Failure.message("Önce bir TV'ye bağlan.") }
                // A TV may shut down before acknowledging this request.
                try await send(TVProtocol.request(id: UUID().uuidString, uri: "system/turnOff"))
                disconnect()
                notice = "Kapatma komutu gönderildi."
                if let tv = selected { watchForPowerOn(tv, requireClosedFirst: true, timeout: nil) }
            } catch { self.error = error.localizedDescription }
        }
    }
    func wake() {
        guard let tv = selected else { error = "Önce Cihazlar bölümünden TV ekle."; return }
        guard !tv.mac.isEmpty else {
            error = "Uyandırma için TV'nin MAC adresi kayıtlı olmalı. TV'yi bir kez açıkken bağla; otomatik alınamazsa Cihazı düzenle bölümüne TV'nin etkin Wi-Fi veya Ethernet MAC adresini gir."
            return
        }
        wakeTask?.cancel()
        error = nil
        notice = "TV açılıyor…"
        waking = true
        wakeTask = Task {
            let delivery: WakeOnLAN.Delivery
            do { delivery = try await WakeOnLAN.send(mac: tv.mac, host: tv.host, broadcast: tv.broadcast) }
            catch is CancellationError { return }
            catch { self.waking = false; self.notice = nil; self.error = error.localizedDescription; return }
            guard !Task.isCancelled else { return }
            self.notice = "TV açılıyor…"
            self.watchForPowerOn(tv, requireClosedFirst: false, timeout: .seconds(40)) { [weak self] in
                guard let self else { return }
                self.waking = false
                guard self.state == .disconnected else { return }
                if delivery.broadcast, tv.deviceUUID != nil {
                    // The TV may have woken with a new DHCP address; connecting runs address recovery.
                    self.connect(to: tv)
                    self.notice = "TV eski adresinde yanıt vermedi; ağda aranıyor…"
                } else {
                    self.notice = nil
                    self.error = Self.wakeFailure(delivery)
                }
            }
        }
    }
    /// Waits for the TV to answer on its webOS port and connects, retrying while it boots.
    /// Right after a power-off the port can stay open briefly, so a standby watch only
    /// reconnects after it has seen the port closed (the TV was really turned back on).
    private func watchForPowerOn(_ tv: Television, requireClosedFirst: Bool, timeout: Duration?, onTimeout: (() -> Void)? = nil) {
        powerOnWatch?.cancel()
        let port: UInt16 = tv.secure ? 3001 : 3000
        powerOnWatch = Task { [weak self] in
            let start = ContinuousClock.now
            var seenClosed = !requireClosedFirst
            var lastAttempt: ContinuousClock.Instant?
            while !Task.isCancelled {
                guard let client = self, client.selected?.id == tv.id else { return }
                if client.state == .connected { client.powerOnWatch = nil; return }
                if let timeout, ContinuousClock.now - start > timeout {
                    client.powerOnWatch = nil
                    onTimeout?()
                    return
                }
                let open = await TVReachability.isListening(host: tv.host, port: port, timeout: client.waking ? .milliseconds(800) : .seconds(1))
                guard !Task.isCancelled else { return }
                if !open {
                    seenClosed = true
                } else if seenClosed, client.state == .disconnected,
                          lastAttempt.map({ ContinuousClock.now - $0 > (client.waking ? .seconds(2) : .seconds(4)) }) ?? true {
                    lastAttempt = .now
                    client.ignoreStandbyUntil = .now + .seconds(30)
                    client.connect(to: tv, allowAddressRecovery: false, persistNewAddress: false)
                    client.notice = "TV açıldı, bağlanılıyor…"
                }
                // After a wake the TV answers within seconds; check often so it connects at once.
                try? await Task.sleep(for: client.waking ? .seconds(1) : .seconds(2))
            }
        }
    }
    // Tested on a Tivibu (ZTE Android TV) box: it stays awake while the TV is off and
    // a WAKEUP/POWER key over Wi-Fi does not turn the TV on through HDMI-CEC, so the
    // box is not a fallback for waking the TV.
    nonisolated static func wakeFailure(_ delivery: WakeOnLAN.Delivery) -> String {
        if !delivery.broadcast {
            return "TV açılmadı. iPhone, uygulamanın ağa yayın (broadcast) paketi göndermesine henüz izin vermiyor; bu izin Apple'ın onayını bekliyor. Paket yalnızca TV'nin son bilinen adresine gidebildi ve kapalı TV bunu genelde almaz. Şimdilik TV'yi kendi kumandasıyla aç."
        }
        return "Uyandırma paketi gönderildi ama TV 20 saniyede yanıt vermedi. TV'de Mobil ile TV Açma (Wi-Fi ile aç) ayarını ve kayıtlı MAC adresini kontrol et."
    }
}

private extension URLSessionWebSocketTask {
    func ping(timeout: Duration = .seconds(3)) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = PingCompletion(continuation)
            let timer = Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                if completion.finish(URLError(.timedOut)) { self.cancel(with: .goingAway, reason: nil) }
            }
            completion.setTimer(timer)
            sendPing { _ = completion.finish($0) }
        }
    }
}

private final class PingCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var timer: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func setTimer(_ task: Task<Void, Never>) {
        lock.lock()
        if continuation != nil { timer = task; lock.unlock() }
        else { lock.unlock(); task.cancel() }
    }
    @discardableResult func finish(_ error: Error?) -> Bool {
        lock.lock()
        guard let continuation else { lock.unlock(); return false }
        self.continuation = nil
        let timer = self.timer; self.timer = nil
        lock.unlock()
        timer?.cancel()
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
        return true
    }
}

#if DEBUG
extension TVClient {
    /// App Store screenshots only (UITEST_SCREENSHOTS): shows a connected TV with sample content.
    /// Never compiled into release builds.
    func loadScreenshotPreview() {
        previewMode = true
        let tv = Television(name: "Salon TV", host: "192.168.1.20")
        televisions = [tv]
        selected = tv
        state = .connected
        powerState = .active
        volume = 14
        pointerReady = true
        apps = [("com.webos.app.livetv", "Canlı TV"), ("com.webos.app.browser", "Web Tarayıcı"), ("com.webos.app.photovideo", "Fotoğraf ve Video"),
                ("com.webos.app.music", "Müzik"), ("com.webos.app.igallery", "Galeri"), ("com.webos.app.notificationcenter", "Bildirimler")]
            .map { TVItem(id: $0.0, title: $0.1) }
        inputs = [TVItem(id: "HDMI_1", title: "Oyun konsolu", detail: "HDMI 1", simplinkName: "Oyun konsolu"),
                  TVItem(id: "HDMI_2", title: "HDMI 2", detail: "HDMI 2"),
                  TVItem(id: "HDMI_3", title: "TVP", detail: "HDMI 3")]
        channels = [("1", "Haber"), ("2", "Belgesel"), ("3", "Spor"), ("4", "Çocuk"), ("5", "Müzik"), ("6", "Sinema")]
            .map { TVItem(id: "ch\($0.0)", title: $0.1, detail: $0.0) }
        // The TV shows the box's input, so the box tab opens without switching inputs.
        foregroundAppID = "com.webos.app.hdmi3"
        libraryReady = true
    }
}
#endif
