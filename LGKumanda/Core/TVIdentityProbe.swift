import Foundation
import Security
import CryptoKit

/// Reads the pre-registration webOS hello, without a pairing key or commands.
/// The captured certificate pin remains required even though many TVs share it.
enum TVIdentityProbe {
    static func deviceUUID(from data: Data) -> String? {
        guard data.count <= 65536,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "hello",
              let payload = object["payload"] as? [String: Any],
              let raw = payload["deviceUUID"] as? String,
              let uuid = UUID(uuidString: raw) else { return nil }
        return uuid.uuidString.lowercased()
    }
    static func read(host: String, fingerprint: String) async -> String? {
        guard TVProtocol.validHost(host), !Task.isCancelled else { return nil }
        let delegate = IdentityTrustDelegate(host: host, fingerprint: fingerprint)
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let socket = session.webSocketTask(with: URL(string: "wss://\(host):3001/")!)
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { deadline.cancel(); socket.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
        return await withTaskCancellationHandler {
            socket.resume()
            do {
                try await socket.send(.string("{\"id\":\"hello\",\"type\":\"hello\",\"payload\":{}}"))
                let message = try await socket.receive()
                guard !Task.isCancelled else { return nil }
                switch message {
                case .string(let text): return deviceUUID(from: Data(text.utf8))
                case .data(let bytes): return deviceUUID(from: bytes)
                @unknown default: return nil
                }
            } catch { return nil }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }
}

private final class IdentityTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String
    let fingerprint: String
    init(host: String, fingerprint: String) { self.host = host; self.fingerprint = fingerprint }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host, let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let cert = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(cert) as Data).map { String(format: "%02x", $0) }.joined()
        guard fingerprint == digest else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
