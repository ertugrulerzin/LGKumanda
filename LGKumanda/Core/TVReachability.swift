import Foundation
import Network

/// Waits until a TV accepts TCP on its webOS port. Used after a wake attempt to
/// report what actually happened instead of "packets sent".
enum TVReachability {
    static func isListening(host: String, port: UInt16, timeout: Duration = .seconds(1)) async -> Bool {
        guard TVProtocol.validHost(host), let port = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let result = OneShot()
        let value = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                result.set(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: result.finish(true)
                    case .failed, .cancelled: result.finish(false)
                    case .waiting: result.finish(false)
                    default: break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
                Task {
                    try? await Task.sleep(for: timeout)
                    result.finish(false)
                }
            }
        } onCancel: { result.finish(false) }
        connection.cancel()
        return value
    }
    static func waitUntilListening(host: String, port: UInt16, within seconds: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if await isListening(host: host, port: port) { return true }
            try? await Task.sleep(for: .milliseconds(800))
        }
        return false
    }
}

private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var done = false
    private var early: Bool?
    func set(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.lock()
        if let early { lock.unlock(); continuation.resume(returning: early); return }
        self.continuation = continuation
        lock.unlock()
    }
    func finish(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        if let continuation { self.continuation = nil; continuation.resume(returning: value) } else { early = value }
    }
}
