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
        didSet { if let selected { UserDefaults.standard.set(controlMode.rawValue, forKey: "controlMode.\(selected.id)") } }
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
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var pointer: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var pointerReceiver: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var generation = UUID()
    private var certificate: String?
    private var motionTask: Task<Void, Never>?
    private var motionToken = UUID()
    private var pendingMotion = (x: 0, y: 0)
    private struct Pending {
        let continuation: CheckedContinuation<[String: Any], Error>
        let timer: Task<Void, Never>
    }
    private var pending: [String: Pending] = [:]

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "televisions"),
           let saved = try? JSONDecoder().decode([Television].self, from: data) {
            televisions = saved
        }
        let id = UserDefaults.standard.string(forKey: "selectedTV")
        selected = televisions.first { $0.id.uuidString == id } ?? televisions.first
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(televisions) { UserDefaults.standard.set(data, forKey: "televisions") }
    }
    func save(_ tv: Television) {
        if let index = televisions.firstIndex(where: { $0.id == tv.id }) { televisions[index] = tv }
        else { televisions.append(tv) }
        connect(to: tv)
    }
    func remove(_ tv: Television) {
        if selected?.id == tv.id { disconnect(); selected = nil; UserDefaults.standard.removeObject(forKey: "selectedTV") }
        televisions.removeAll { $0.id == tv.id }
        UserDefaults.standard.removeObject(forKey: "controlMode.\(tv.id)")
        KeychainStore.delete("key.\(tv.id)"); KeychainStore.delete("cert.\(tv.id)")
    }
    func resetPairing() {
        guard let tv = selected else { return }
        disconnect()
        KeychainStore.delete("key.\(tv.id)"); KeychainStore.delete("cert.\(tv.id)")
        connect(to: tv)
    }
    func disconnect() {
        stopPointerMotion()
        generation = UUID()
        receiver?.cancel(); pointerReceiver?.cancel(); deadline?.cancel(); heartbeat?.cancel()
        socket?.cancel(with: .goingAway, reason: nil); pointer?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        socket = nil; pointer = nil; session = nil
        for item in pending.values { item.timer.cancel(); item.continuation.resume(throwing: Failure.message("Bağlantı kapandı.")) }
        pending.removeAll()
        state = .disconnected; pointerReady = false; volume = nil; muted = false
        foregroundAppID = nil; libraryReady = false
        apps = []; inputs = []; channels = []
    }
    func connect(to tv: Television) {
        disconnect(); error = nil; notice = nil
        guard TVProtocol.validHost(tv.host) else { error = "TV'nin yerel IPv4 adresini gir (ör. 192.168.1.50)."; return }
        selected = tv; UserDefaults.standard.set(tv.id.uuidString, forKey: "selectedTV")
        controlMode = ControlMode(rawValue: UserDefaults.standard.string(forKey: "controlMode.\(tv.id)") ?? "") ?? .automatic
        state = .connecting; certificate = nil
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
        self.socket = socket; socket.resume()
        receiver = Task { [weak self] in
            do {
                try await self?.send(TVProtocol.registration(key: KeychainStore.read("key.\(tv.id)")))
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.generation == token else { return }
                    self.consume(message, token: token)
                }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.disconnect()
                self.error = "TV bağlantısı kesildi. TV'nin açık olduğunu, aynı Wi-Fi'da olduğunu ve yerel ağ iznini kontrol et. \(error.localizedDescription)"
            }
        }
        setDeadline(seconds: 20, token: token, message: "TV'ye ulaşılamadı. IP adresini kontrol edip yeniden dene.")
    }
    private func setDeadline(seconds: UInt64, token: UUID, message: String) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            guard let self, self.generation == token, self.state != .connected else { return }
            self.disconnect(); self.error = message
        }
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
            state = .connected; deadline?.cancel()
            Task { await bootstrap(token: token) }
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 20_000_000_000); try Task.checkCancellation(); try await self?.socket?.ping() }
                    catch {
                        guard let self, !Task.isCancelled, self.generation == token else { return }
                        self.disconnect(); self.error = "TV yanıt vermiyor. Yeniden bağlan."; return
                    }
                }
            }
        } else if type == "response", id == "register" {
            state = .pairing
            setDeadline(seconds: 90, token: token, message: "Eşleştirme onaylanmadı. TV ekranındaki isteği kabul edip yeniden dene.")
        } else if type == "error", id == "register" {
            disconnect(); error = "TV eşleştirmeyi reddetti. TV ekranından bağlantıya izin ver. Gerekirse yeniden eşleştir."
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
                item.continuation.resume(throwing: Failure.message("TV komutu reddetti: \(detail)"))
            } else { item.continuation.resume(returning: payload) }
        }
    }
    private func send(_ object: [String: Any]) async throws {
        guard let socket else { throw Failure.message("Önce bir TV'ye bağlan.") }
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    func request(_ uri: String, _ payload: [String: Any] = [:]) async throws -> [String: Any] {
        guard state == .connected else { throw Failure.message("Önce bir TV'ye bağlan.") }
        let id = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                if let item = self?.pending.removeValue(forKey: id) {
                    item.continuation.resume(throwing: Failure.message("TV komuta yanıt vermedi. Yeniden dene."))
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
    var webFocusEnabled: Bool { UserDefaults.standard.object(forKey: "webFocus") as? Bool ?? true }
    private var webFocusQueue: Task<Void, Never>?
    func key(_ key: RemoteKey) {
        if isBrowserActive, webFocusEnabled, let app = browserAppID, let action = WebFocus.action(for: key) {
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
    func media(_ action: MediaAction) { sendRouted(ControlRouting.media(action, context: controlContext)) }
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
        foregroundAppID = app
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
        await refreshLibrary(reportErrors: false)
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
    func powerOff() {
        Task {
            do {
                guard state == .connected else { throw Failure.message("Önce bir TV'ye bağlan.") }
                // A TV may shut down before acknowledging this request.
                try await send(TVProtocol.request(id: UUID().uuidString, uri: "system/turnOff"))
                disconnect()
                notice = "Kapatma komutu gönderildi."
            } catch { self.error = error.localizedDescription }
        }
    }
    func wake() {
        guard let tv = selected else { error = "Önce Cihazlar bölümünden TV ekle."; return }
        do {
            try WakeOnLAN.send(mac: tv.mac, broadcast: tv.broadcast)
            notice = "Uyandırma paketi gönderildi. TV açılınca Bağlan'a dokun."
        } catch { self.error = error.localizedDescription }
    }
}

private extension URLSessionWebSocketTask {
    func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
