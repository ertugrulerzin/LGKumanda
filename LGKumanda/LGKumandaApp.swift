import SwiftUI

@main struct LGKumandaApp: App {
    @StateObject private var client = TVClient()
    @StateObject private var shortcuts = ShortcutStore()
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
