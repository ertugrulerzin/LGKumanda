import Foundation

/// Screen-off/audio-only mode still accepts commands; standby does not mean
/// the network socket closed. Keep power and transport status separate.
enum TVPowerState: Equatable {
    case unknown, active, standby, screenOff, screenSaver
    var isStandby: Bool { self == .standby }
    static func read(_ payload: [String: Any]) -> TVPowerState {
        guard let raw = payload["state"] as? String else { return .unknown }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "active": return .active
        case "active standby":
            // During startup/shutdown some firmware reports an intermediate
            // standby state with processing still in progress.
            if let processing = payload["processing"] as? String, !processing.isEmpty { return .unknown }
            return .standby
        case "suspend", "power off": return .standby
        case "screen off": return .screenOff
        case "screen saver": return .screenSaver
        default: return .unknown
        }
    }
}
