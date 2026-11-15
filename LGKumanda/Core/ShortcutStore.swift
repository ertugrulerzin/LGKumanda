import Foundation

struct TVShortcut: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case app, input }
    var kind: Kind
    var targetID: String
    var title: String
    var id: String { "\(kind.rawValue):\(targetID)" }
    static func fromApp(_ item: TVItem, inputs: [TVItem]) -> TVShortcut {
        if let input = inputs.first(where: { ControlRouting.appID(forInput: $0.id) == item.id }) {
            return TVShortcut(kind: .input, targetID: input.id, title: input.title)
        }
        return TVShortcut(kind: .app, targetID: item.id, title: item.title)
    }
    var symbol: String {
        if kind == .input { return "cable.connector" }
        let name = (targetID + " " + title).lowercased()
        if name.contains("browser") || name.contains("tarayıcı") { return "globe" }
        if name.contains("youtube") { return "play.rectangle.fill" }
        if name.contains("netflix") { return "play.rectangle" }
        return "square.grid.2x2"
    }
    static func suggested(apps: [TVItem], inputs: [TVItem] = []) -> [TVShortcut] {
        let patterns: [(String, [String])] = [
            ("Netflix", ["netflix"]),
            ("YouTube", ["youtube"]),
            ("Web tarayıcısı", ["com.webos.app.browser", "web browser", "web tarayıcısı", "internet browser"]),
            ("TV+", ["com.tvplus.app"])
        ]
        var result: [TVShortcut] = []
        for (title, candidates) in patterns {
            if let app = apps.first(where: { item in
                guard !item.id.hasPrefix("com.webos.app.hdmi") else { return false }
                let text = (item.id + " " + item.title).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                return candidates.contains { text.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))) }
            }), !result.contains(where: { $0.targetID == app.id }) {
                result.append(TVShortcut(kind: .app, targetID: app.id, title: title))
            }
        }
        for input in inputs where ["tivibu", "tvp"].contains(input.title.lowercased()) {
            result.append(TVShortcut(kind: .input, targetID: input.id, title: input.title.lowercased() == "tvp" ? "TVP" : "Tivibu"))
        }
        return result
    }
}

@MainActor final class ShortcutStore: ObservableObject {
    @Published private(set) var lists: [String: [TVShortcut]]
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "homeShortcuts"), let stored = try? JSONDecoder().decode([String: [TVShortcut]].self, from: data) { lists = stored }
        else { lists = [:] }
    }
    func items(for tv: UUID?) -> [TVShortcut] { tv.flatMap { lists[$0.uuidString] } ?? [] }
    func seed(tv: UUID?, apps: [TVItem], inputs: [TVItem] = []) {
        guard let tv, !apps.isEmpty, lists[tv.uuidString] == nil else { return }
        lists[tv.uuidString] = TVShortcut.suggested(apps: apps, inputs: inputs); persist()
    }
    func put(_ shortcut: TVShortcut, tv: UUID) {
        var items = items(for: tv)
        var value = shortcut; value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.title.isEmpty, !value.targetID.isEmpty else { return }
        if let index = items.firstIndex(where: { $0.id == value.id }) { items[index] = value }
        else { items.append(value) }
        lists[tv.uuidString] = items; persist()
    }
    func remove(_ id: String, tv: UUID) {
        lists[tv.uuidString] = items(for: tv).filter { $0.id != id }; persist()
    }
    func reorder(_ ids: [String], tv: UUID) {
        let current = items(for: tv)
        guard ids.count == current.count, Set(ids) == Set(current.map(\.id)) else { return }
        lists[tv.uuidString] = ids.compactMap { id in current.first { $0.id == id } }; persist()
    }
    func restore(tv: UUID, apps: [TVItem], inputs: [TVItem]) { lists[tv.uuidString] = TVShortcut.suggested(apps: apps, inputs: inputs); persist() }
    private func persist() {
        if let data = try? JSONEncoder().encode(lists) { defaults.set(data, forKey: "homeShortcuts") }
    }
}
