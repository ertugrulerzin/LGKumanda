import Foundation

enum ControlContext: Equatable { case television, application, hdmi }
enum ControlMode: String, CaseIterable, Identifiable {
    case automatic, television, platform
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: return "Otomatik"; case .television: return "TV kanalları"; case .platform: return "Uygulama / HDMI" }
    }
    func context(foregroundID: String?) -> ControlContext {
        if self == .television { return .television }
        if foregroundID?.hasPrefix("com.webos.app.hdmi") == true { return .hdmi }
        if self == .platform { return .application }
        return foregroundID == "com.webos.app.livetv" ? .television : .application
    }
}

enum MediaAction: String, CaseIterable {
    case play, pause, stop, rewind, fastForward
    var key: RemoteKey {
        switch self { case .play: return .play; case .pause: return .pause; case .stop: return .stop; case .rewind: return .rewind; case .fastForward: return .fastForward }
    }
}
enum RoutedControl: Equatable {
    case request(String)
    case key(RemoteKey)
}
enum ControlRouting {
    static func channel(up: Bool, context: ControlContext) -> RoutedControl {
        context == .television ? .request(up ? "tv/channelUp" : "tv/channelDown") : .key(up ? .channelUp : .channelDown)
    }
    static func media(_ action: MediaAction, context: ControlContext) -> RoutedControl {
        context == .television ? .request("media.controls/\(action.rawValue)") : .key(action.key)
    }
    static func appID(forInput id: String) -> String? {
        let normalized = id.lowercased().replacingOccurrences(of: "_", with: "")
        guard normalized.hasPrefix("hdmi"), let number = Int(normalized.dropFirst(4)), number > 0 else { return nil }
        return "com.webos.app.hdmi\(number)"
    }
}
