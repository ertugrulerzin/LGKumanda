import Foundation

/// Remote v2 negotiation: SetActive is not readiness; RemoteStart completes it.
struct BoxRemoteSession {
    static let requestedFeatures = 1 | 2 | 32 | 64 | 512
    private(set) var features = requestedFeatures
    private(set) var ready = false
    private(set) var isOn: Bool?
    private(set) var model = ""
    private(set) var currentApp = ""
    var supportsKeys: Bool { features & 2 != 0 }

    mutating func receive(_ frame: Data) -> Data {
        guard let message = ProtoMessage(frame) else { return Data() }
        var reply = ProtoWriter()
        if let configure = message.message(1) {
            model = configure.message(2)?.string(1) ?? model
            features = Self.requestedFeatures & (configure.int(1) ?? Self.requestedFeatures)
            ready = false
            reply.message(1) { c in
                c.varint(1, features)
                c.message(2) { d in d.varint(3, 1); d.string(4, "1"); d.string(5, "atvremote"); d.string(6, "1.0.0") }
            }
        } else if message.has(2) {
            reply.message(2) { $0.varint(1, features) }
        } else if let start = message.message(40) {
            ready = true
            isOn = (start.int(1) ?? 0) != 0
        } else if let ping = message.message(8) {
            reply.message(9) { $0.varint(1, ping.int(1) ?? 0) }
        } else if let ime = message.message(20) {
            currentApp = ime.message(1)?.string(12) ?? currentApp
        }
        return reply.data
    }
}
