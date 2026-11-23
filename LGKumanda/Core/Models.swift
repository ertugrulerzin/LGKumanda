import Foundation

struct Television: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var host: String
    var secure = true
    var mac = ""
    var broadcast = "255.255.255.255"
    var deviceUUID: String?
}

struct TVItem: Identifiable, Equatable {
    let id: String
    let title: String
    var detail: String = ""
    /// SIMPLINK (HDMI-CEC) device the TV sees on this input, if any.
    var simplinkName: String? = nil
}

enum ConnectionState: Equatable {
    case disconnected, connecting, pairing, connected
    var label: String {
        switch self {
        case .disconnected: return "Bağlı değil"
        case .connecting: return "Bağlanıyor…"
        case .pairing: return "TV'den onay bekleniyor"
        case .connected: return "Bağlı"
        }
    }
}

enum RemoteKey: String, CaseIterable {
    case up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT", enter = "ENTER"
    case home = "HOME", back = "BACK", exit = "EXIT", menu = "MENU"
    case guide = "GUIDE", info = "INFO", list = "LIST", settings = "QMENU"
    case red = "RED", green = "GREEN", yellow = "YELLOW", blue = "BLUE"
    case zero = "0", one = "1", two = "2", three = "3", four = "4"
    case five = "5", six = "6", seven = "7", eight = "8", nine = "9"
    case dash = "DASH", previous = "FLASHBK", subtitles = "CC", teletext = "TEXT"
    case channelUp = "CHANNELUP", channelDown = "CHANNELDOWN"
    case play = "PLAY", pause = "PAUSE", stop = "STOP", rewind = "REWIND", fastForward = "FASTFORWARD"
    var wireMessage: String { "type:button\nname:\(rawValue)\n\n" }
}

enum TVProtocol {
    static func simplinkName(_ input: [String: Any]) -> String? {
        let devices = input["subList"] as? [[String: Any]] ?? []
        guard let device = devices.first(where: { ($0["id"] as? String)?.uppercased() == "SIMPLINK" }) ?? devices.first else { return nil }
        let name = (device["osdName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "HDMI cihazı" : name
    }
    static let permissions = ["LAUNCH", "CONTROL_AUDIO", "CONTROL_INPUT_MEDIA_PLAYBACK",
        "CONTROL_INPUT_TV", "CONTROL_POWER", "READ_CURRENT_CHANNEL", "READ_INPUT_DEVICE_LIST",
        "READ_NETWORK_STATE", "READ_RUNNING_APPS", "READ_TV_CHANNEL_LIST", "READ_POWER_STATE",
        "CONTROL_INPUT_TEXT", "CONTROL_MOUSE_AND_KEYBOARD", "READ_INSTALLED_APPS"]

    static func registration(key: String?) -> [String: Any] {
        var payload: [String: Any] = ["forcePairing": false, "pairingType": "PROMPT",
            "manifest": ["manifestVersion": 1, "appVersion": "1.0", "permissions": permissions]]
        if let key { payload["client-key"] = key }
        return ["id": "register", "type": "register", "payload": payload]
    }

    static func request(id: String, uri: String, payload: [String: Any] = [:], subscribe: Bool = false) -> [String: Any] {
        ["id": id, "type": subscribe ? "subscribe" : "request", "uri": "ssap://\(uri)", "payload": payload]
    }

    static func audioStatus(_ payload: [String: Any]) -> (volume: Int?, muted: Bool?) {
        let status = payload["volumeStatus"] as? [String: Any] ?? payload
        return (status["volume"] as? Int, status["mute"] as? Bool ?? status["muted"] as? Bool)
    }

    static func validHost(_ host: String) -> Bool {
        // Restrict credentials and certificate trust to an explicitly entered private IPv4 address.
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let bytes = parts.compactMap { UInt8($0) }
        guard bytes.count == 4 else { return false }
        return bytes[0] == 10 || (bytes[0] == 192 && bytes[1] == 168) ||
            (bytes[0] == 172 && (16...31).contains(bytes[1])) || (bytes[0] == 169 && bytes[1] == 254)
    }
}

struct PointerDeltaFilter {
    private var remainderX = 0.0
    private var remainderY = 0.0
    mutating func move(dx: Double, dy: Double, gain: Double) -> (Int, Int) {
        guard dx.isFinite, dy.isFinite, gain.isFinite else { return (0, 0) }
        let sensitivity = max(0.2, min(2, gain))
        let x = max(-32, min(32, dx * sensitivity + remainderX))
        let y = max(-32, min(32, dy * sensitivity + remainderY))
        let step = (Int(x), Int(y))
        remainderX = x - Double(step.0); remainderY = y - Double(step.1)
        return step
    }
}

/// Splits a jump into protocol-sized moves (±32 per message), bounded to roughly one screen.
enum PointerJump {
    static let limit = 2000
    static func steps(dx: Int, dy: Int) -> [(Int, Int)] {
        var x = max(-limit, min(limit, dx)), y = max(-limit, min(limit, dy))
        var result: [(Int, Int)] = []
        while x != 0 || y != 0 {
            let sx = max(-32, min(32, x)), sy = max(-32, min(32, y))
            result.append((sx, sy)); x -= sx; y -= sy
        }
        return result
    }
}
