import SwiftUI

@main struct LGKumandaApp: App {
    @StateObject private var client = TVClient()
    @StateObject private var shortcuts = ShortcutStore()
    @StateObject private var box = BoxClient()
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let start = ProcessInfo.processInfo.environment["UITEST_PHONE_BROWSER"].flatMap(URL.init(string:)) {
                    NavigationStack { PhoneBrowserView(start: start) }
                } else { RootView() }
                #else
                RootView()
                #endif
            }.environmentObject(client)
                .environmentObject(box)
                .onAppear {
                    client.keyRouter = { [weak client, weak box] key in
                        guard let client, let box, box.handles(foregroundAppID: client.foregroundAppID) else { return false }
                        return box.send(key)
                    }
                }
                .environmentObject(shortcuts)
                .tint(Theme.accent)
                .preferredColorScheme(.light)
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.58, green: 0.12, blue: 0.27)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}
