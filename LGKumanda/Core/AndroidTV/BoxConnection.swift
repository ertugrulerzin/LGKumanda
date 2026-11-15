import Foundation
import Network
import Security

/// TLS connection to an Android TV box with our client certificate, carrying length-prefixed protobuf frames.
/// The box uses a self-signed certificate; it is accepted and kept for the pairing secret.
final class BoxConnection: @unchecked Sendable {
    enum Failure: LocalizedError {
        case closed(String)
        var errorDescription: String? { if case .closed(let reason) = self { return reason }; return nil }
    }
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var framer = ProtoFramer()
    private final class TrustHolder: @unchecked Sendable { var certificate: SecCertificate? }
    private let trust: TrustHolder
    var serverCertificate: SecCertificate? { trust.certificate }
    var onMessage: ((Data) -> Void)?
    var onClose: ((Error?) -> Void)?
    private var closed = false

    init(host: String, port: UInt16, identity: SecIdentity) {
        let queue = DispatchQueue(label: "LGKumanda.box")
        self.queue = queue
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        if let secIdentity = sec_identity_create(identity) { sec_protocol_options_set_local_identity(options, secIdentity) }
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        let holder = TrustHolder()
        trust = holder
        sec_protocol_options_set_verify_block(options, { _, secTrust, complete in
            let ref = sec_trust_copy_ref(secTrust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(ref) as? [SecCertificate] { holder.certificate = chain.first }
            complete(true)
        }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 6
        tcp.enableKeepalive = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
    }

    /// Connects; throws if the box cannot be reached or rejects the certificate.
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !once.done { once.done = true; continuation.resume() }
                    self?.receive()
                case .failed(let error), .waiting(let error):
                    if !once.done { once.done = true; continuation.resume(throwing: Failure.closed(Self.describe(error))) }
                    self?.finish(error)
                case .cancelled:
                    if !once.done { once.done = true; continuation.resume(throwing: Failure.closed("Bağlantı kapandı.")) }
                    self?.finish(nil)
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    func send(_ payload: Data) {
        connection.send(content: ProtoWriter.frame(payload), completion: .contentProcessed { [weak self] error in
            if let error { self?.finish(error) }
        })
    }

    func cancel() { connection.cancel() }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { for frame in self.framer.append(data) { self.onMessage?(frame) } }
            if let error { self.finish(error); return }
            if isComplete { self.finish(nil); return }
            self.receive()
        }
    }

    private func finish(_ error: Error?) {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?(error)
    }

    static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code) where code == .EHOSTUNREACH || code == .ENETUNREACH:
            return "Kutuya ulaşılamadı. iPhone ile kutu aynı Wi-Fi'da mı? Ayarlar > Gizlilik > Yerel Ağ'da LG Kumanda açık olmalı."
        case .posix(let code) where code == .ECONNREFUSED:
            return "Kutu bağlantıyı reddetti. Kutu açık mı?"
        case .tls:
            return "Kutu güvenli bağlantıyı kabul etmedi. Yeniden eşleştir."
        default:
            return "Kutuya bağlanılamadı: \(error.localizedDescription)"
        }
    }
}
