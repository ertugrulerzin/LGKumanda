import Foundation
import Network

/// Finds Android TV boxes that advertise the remote service (`_androidtvremote2._tcp`) on the local network.
@MainActor final class BoxDiscovery: ObservableObject {
    struct Found: Identifiable, Equatable { let name: String; let host: String; var id: String { host } }
    @Published private(set) var found: [Found] = []
    @Published private(set) var searching = false
    private var browser: NWBrowser?

    func start() {
        stop()
        found = []; searching = true
        let browser = NWBrowser(for: .bonjour(type: "_androidtvremote2._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                guard case .service(let name, _, _, _) = result.endpoint else { continue }
                Task { @MainActor in
                    guard let host = await Self.resolve(result.endpoint), let self, !self.found.contains(where: { $0.host == host }) else { return }
                    self.found.append(Found(name: name, host: host))
                }
            }
        }
        browser.start(queue: .main)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.searching = false
        }
    }

    func stop() { browser?.cancel(); browser = nil; searching = false }

    /// The IPv4 address behind a Bonjour service, read from a short TCP connection.
    private static func resolve(_ endpoint: NWEndpoint) async -> String? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: endpoint, using: parameters)
        return await withCheckedContinuation { continuation in
            var done = false
            func finish(_ host: String?) {
                guard !done else { return }
                done = true; connection.cancel(); continuation.resume(returning: host)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
                        finish("\(host)".split(separator: "%").first.map(String.init))
                    } else { finish(nil) }
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish(nil) }
        }
    }
}
