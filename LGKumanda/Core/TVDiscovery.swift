import Foundation
import Darwin
import Security

@MainActor final class TVDiscovery: ObservableObject {
    @Published private(set) var searching = false
    @Published private(set) var found: [Television] = []
    @Published private(set) var completed = false
    @Published private(set) var message: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var checkedCount = 0
    @Published private(set) var totalCount = 0
    private var generation = UUID()
    private var identityHosts: [String: String] = [:]
    private var preferredHosts = Set<String>()

    func cancel() {
        generation = UUID(); searching = false; completed = false
    }
    func search(knownHosts: [String] = [], useMulticast: Bool = true) async {
        guard !searching else { return }
        let token = UUID(); generation = token
        searching = true; completed = false; found = []; message = nil; permissionDenied = false
        identityHosts = [:]; preferredHosts = Set(knownHosts)
        checkedCount = 0; totalCount = 0
        defer { if generation == token { searching = false; completed = true } }
        let subnets = LocalSubnet.wifi()
        guard !subnets.isEmpty else {
            message = "Wi-Fi bağlantısı bulunamadı. iPhone'u TV ile aynı Wi-Fi ağına bağla."
            return
        }
        var hosts = knownHosts.filter { host in subnets.contains { $0.contains(host) } }
        hosts += subnets.flatMap(\.scanHosts)
        var seen = Set<String>()
        hosts = hosts.filter { seen.insert($0).inserted }
        totalCount = hosts.count
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2
        let session = URLSession(configuration: config, delegate: LocalDiscoveryDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        async let multicastLocations: [String] = Task.detached(priority: .utility) {
            useMulticast ? Self.probe() : []
        }.value
        await withTaskGroup(of: Identification.self) { group in
            var next = 0
            // A small concurrency window keeps the phone and Wi-Fi responsive.
            for _ in 0..<min(24, hosts.count) {
                let host = hosts[next]; next += 1
                group.addTask { await Self.identifyHost(host, session: session) }
            }
            for await result in group {
                guard generation == token, !Task.isCancelled else { group.cancelAll(); break }
                checkedCount += 1
                if result.denied { permissionDenied = true }
                if let tv = result.television { append(tv, identity: result.identity) }
                if permissionDenied && found.isEmpty { group.cancelAll(); break }
                if next < hosts.count {
                    let host = hosts[next]; next += 1
                    group.addTask { await Self.identifyHost(host, session: session) }
                }
            }
        }
        guard generation == token else { return }
        for location in await multicastLocations {
            guard generation == token, let url = URL(string: location), !found.contains(where: { $0.host == url.host }) else { continue }
            let result = await Self.identify(url: url, session: session)
            if let tv = result.television { append(tv, identity: result.identity) }
        }
        guard generation == token else { return }
        if found.isEmpty {
            message = permissionDenied
                ? "Yerel ağ izni kapalı. Ayarlar'dan LG Kumanda için Yerel Ağ iznini aç, sonra yeniden ara."
                : "TV bulunamadı. TV'nin açık ve aynı Wi-Fi'da olduğundan emin ol. İstersen IP adresiyle ekle."
        }
    }
    private func append(_ tv: Television, identity: String?) {
        guard !found.contains(where: { $0.host == tv.host }) else { return }
        if let identity, let existing = identityHosts[identity] {
            // A single TV can expose both Wi-Fi and Ethernet addresses.
            if preferredHosts.contains(tv.host), !preferredHosts.contains(existing),
               let index = found.firstIndex(where: { $0.host == existing }) {
                found[index] = tv
                identityHosts[identity] = tv.host
            }
            return
        }
        if let identity { identityHosts[identity] = tv.host }
        found.append(tv)
    }
    private struct Identification: @unchecked Sendable {
        var television: Television?
        var identity: String?
        var denied = false
    }
    nonisolated private static func identifyHost(_ host: String, session: URLSession) async -> Identification {
        let description = await identify(url: URL(string: "http://\(host):1311/")!, session: session)
        guard description.television == nil, !description.denied, !Task.isCancelled else { return description }
        if await answersAsLGTelevision(host) {
            return Identification(television: Television(name: "LG webOS TV", host: host))
        }
        return description
    }
    // Read only the TLS certificate. Discovery never registers, sends pairing
    // credentials, or changes the trust used by TVClient for actual control.
    nonisolated static func answersAsLGTelevision(_ host: String, port: Int = 3001) async -> Bool {
        guard TVProtocol.validHost(host), (1...65535).contains(port), !Task.isCancelled else { return false }
        let delegate = LGDiscoveryCertificateDelegate(host: host)
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        _ = try? await session.data(from: URL(string: "https://\(host):\(port)/")!)
        return !Task.isCancelled && delegate.recognized
    }
    nonisolated static func isLGTelevisionCertificate(_ certificate: SecCertificate) -> Bool {
        let names = [SecCertificateCopyNormalizedSubjectSequence(certificate), SecCertificateCopyNormalizedIssuerSequence(certificate)]
        return names.compactMap { $0 as Data? }.contains { distinguishedNameHasLGOrganization($0) }
    }
    nonisolated static func distinguishedNameHasLGOrganization(_ data: Data) -> Bool {
        // X.509 Name: SEQUENCE of SETs of SEQUENCE { OID, string }. Restrict
        // recognition to the organization attribute (2.5.4.10), not arbitrary
        // certificate bytes or a common name merely mentioning LG.
        struct DER {
            let bytes: [UInt8]
            var offset = 0
            mutating func read() -> (tag: UInt8, bytes: [UInt8])? {
                guard offset + 2 <= bytes.count else { return nil }
                let tag = bytes[offset]; offset += 1
                var length = Int(bytes[offset]); offset += 1
                if length & 0x80 != 0 {
                    let count = length & 0x7f
                    guard count > 0, count <= 4, offset + count <= bytes.count else { return nil }
                    length = 0
                    for _ in 0..<count { length = (length << 8) | Int(bytes[offset]); offset += 1 }
                }
                guard length <= bytes.count - offset else { return nil }
                defer { offset += length }
                return (tag, Array(bytes[offset..<offset + length]))
            }
        }
        var root = DER(bytes: Array(data))
        guard let name = root.read(), name.tag == 0x30, root.offset == root.bytes.count else { return false }
        var sequence = DER(bytes: name.bytes)
        while let set = sequence.read() {
            guard set.tag == 0x31 else { return false }
            var attributes = DER(bytes: set.bytes)
            while let attribute = attributes.read() {
                guard attribute.tag == 0x30 else { return false }
                var pair = DER(bytes: attribute.bytes)
                guard let oid = pair.read(), oid.tag == 0x06, let value = pair.read() else { return false }
                guard oid.bytes == [0x55, 0x04, 0x0a] else { continue }
                let encoding: String.Encoding
                switch value.tag {
                case 0x0c, 0x13, 0x14, 0x16: encoding = .utf8
                case 0x1e: encoding = .utf16BigEndian
                default: continue
                }
                let organization = String(data: Data(value.bytes), encoding: encoding)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["lg electronics", "lg electronics inc.", "lg electronics inc"].contains(organization ?? "") { return true }
            }
        }
        return false
    }
    nonisolated private static func identify(url: URL, session: URLSession) async -> Identification {
        guard let host = url.host, TVProtocol.validHost(host), url.scheme == "http" else { return Identification() }
        do {
            var request = URLRequest(url: url); request.timeoutInterval = 1.5
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  data.count <= 65536, let device = deviceDescription(from: data) else { return Identification() }
            return Identification(television: Television(name: device.name, host: host), identity: device.identity)
        } catch { return Identification(denied: isLocalNetworkDenied(error)) }
    }
    nonisolated static func isLocalNetworkDenied(_ error: Error) -> Bool {
        let error = error as NSError
        let description = error.userInfo.map { "\($0.key) \($0.value)" }.joined(separator: " ").lowercased()
        return description.contains("local network") && (description.contains("prohibited") || description.contains("denied"))
    }
    nonisolated static func deviceName(from data: Data) -> String? { deviceDescription(from: data)?.name }
    nonisolated static func deviceDescription(from data: Data) -> (name: String, identity: String?)? {
        let delegate = DeviceDescriptionParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "lg electronics",
              delegate.services.contains(where: { $0.contains("urn:lge-com:service:webos-second-screen:") }) else { return nil }
        let name = delegate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = delegate.identity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (name.isEmpty ? "LG webOS TV" : name, identity.isEmpty ? nil : identity)
    }
    nonisolated static func location(from response: String) -> String? {
        let lines = response.components(separatedBy: "\r\n")
        guard lines.contains(where: { $0.localizedCaseInsensitiveContains("urn:lge-com:service:webos-second-screen:1") }) else { return nil }
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "location" else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: value), url.scheme == "http", let host = url.host,
                  TVProtocol.validHost(host), url.user == nil, url.password == nil else { return nil }
            return value
        }
        return nil
    }
    nonisolated private static func probe() -> [String] {
        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return [] }
        defer { Darwin.close(descriptor) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = UInt16(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &target.sin_addr)
        let query = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:lge-com:service:webos-second-screen:1\r\n\r\n"
        let data = Data(query.utf8)
        let sent = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.sendto(descriptor, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == data.count else { return [] }
        var locations = Set<String>()
        let end = Date().addingTimeInterval(4)
        var buffer = [UInt8](repeating: 0, count: 8192)
        while Date() < end {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count > 0, let location = location(from: String(decoding: buffer.prefix(count), as: UTF8.self)) { locations.insert(location) }
        }
        return locations.sorted()
    }
}

private final class DeviceDescriptionParser: NSObject, XMLParserDelegate {
    var name = ""
    var manufacturer = ""
    var identity = ""
    var services: [String] = []
    private var field = ""
    private var value = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if ["friendlyName", "manufacturer", "serviceType", "UDN"].contains(elementName) { field = elementName; value = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if !field.isEmpty { value += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == field else { return }
        if field == "friendlyName" && name.isEmpty { name = value }
        if field == "manufacturer" && manufacturer.isEmpty { manufacturer = value }
        if field == "serviceType" { services.append(value) }
        if field == "UDN" && identity.isEmpty { identity = value }
        field = ""; value = ""
    }
}

private final class LocalDiscoveryDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Discovery must not leave the local device that is being identified.
        let allowed = request.url?.scheme == "http" && request.url?.host == task.originalRequest?.url?.host
        completionHandler(allowed ? request : nil)
    }
}

private final class LGDiscoveryCertificateDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String
    private let lock = NSLock()
    private var matched = false
    var recognized: Bool { lock.lock(); defer { lock.unlock() }; return matched }
    init(host: String) { self.host = host }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == host, let trust = challenge.protectionSpace.serverTrust,
           let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first {
            let result = TVDiscovery.isLGTelevisionCertificate(leaf)
            lock.lock(); matched = result; lock.unlock()
        }
        // Recognizing an advertised brand is not authentication. Do not finish
        // the handshake or send HTTP / WebSocket registration during discovery.
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
