import Foundation

/// Remote v2 negotiation: SetActive is not readiness; RemoteStart completes it.
struct BoxRemoteSession {
    /// Ping, key, IME (text), power, volume, app links.
    static let requestedFeatures = 1 | 2 | 4 | 32 | 64 | 512
    private(set) var features = requestedFeatures
    private(set) var ready = false
    private(set) var isOn: Bool?
    private(set) var model = ""
    private(set) var currentApp = ""
    /// The box's text-field counters; a text edit must echo them back.
    private(set) var imeCounter = 0
    private(set) var imeField = 0
    var supportsKeys: Bool { features & 2 != 0 }
    var supportsText: Bool { features & 4 != 0 }

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
        } else if let edit = message.message(21) {
            imeCounter = edit.int(1) ?? imeCounter
            imeField = edit.int(2) ?? imeField
        } else if let show = message.message(22) {
            imeField = show.message(2)?.int(1) ?? imeField
        } else if let ime = message.message(20) {
            currentApp = ime.message(1)?.string(12) ?? currentApp
        }
        return reply.data
    }

    /// RemoteImeBatchEdit that replaces the focused text field's content with `text`.
    func textEdit(_ text: String) -> Data {
        let end = text.count - 1
        var w = ProtoWriter()
        w.message(21) { e in
            e.varint(1, imeCounter); e.varint(2, imeField)
            e.message(3) { i in
                i.varint(1, 1)
                i.message(2) { f in f.varint(1, end); f.varint(2, end); f.string(3, text) }
            }
        }
        return w.data
    }
}
