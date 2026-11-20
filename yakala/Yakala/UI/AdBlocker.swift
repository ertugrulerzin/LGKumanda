import Foundation
import Observation
import WebKit

/// AdGuard-style blocker: downloads filter lists, converts them to WebKit content rules
/// and lets WebKit block requests and hide ad elements natively.
@MainActor
@Observable
final class AdBlocker {
    struct Source: Sendable {
        let id: String
        let name: String
        let url: URL
    }

    static let sources = [
        Source(id: "yakala.easylist", name: "EasyList", url: URL(string: "https://easylist.to/easylist/easylist.txt")!),
        Source(id: "yakala.easyprivacy", name: "EasyPrivacy", url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!),
        Source(id: "yakala.turkish", name: "AdGuard Türkçe", url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/13.txt")!),
    ]
    static let refreshInterval: TimeInterval = 4 * 24 * 3600

    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "adblock.enabled")
            apply()
        }
    }
    var allowlist: [String] {
        didSet { defaults.set(allowlist, forKey: "adblock.allowlist") }
    }
    var ruleCount: Int
    var lastUpdate: Date?
    var isUpdating = false
    var error: String?
    private(set) var currentHost: String?

    @ObservationIgnored private var lists: [WKContentRuleList] = []
    @ObservationIgnored private weak var controller: WKUserContentController?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let store = WKContentRuleListStore.default()!

    init() {
        enabled = defaults.object(forKey: "adblock.enabled") as? Bool ?? true
        allowlist = defaults.stringArray(forKey: "adblock.allowlist") ?? []
        ruleCount = defaults.integer(forKey: "adblock.ruleCount")
        lastUpdate = defaults.object(forKey: "adblock.lastUpdate") as? Date
    }

    var isReady: Bool { !lists.isEmpty }

    func attach(_ controller: WKUserContentController) {
        self.controller = controller
        Task {
            for s in Self.sources {
                if let list = try? await store.contentRuleList(forIdentifier: s.id) { lists.append(list) }
            }
            apply()
            if lists.count < Self.sources.count || (lastUpdate.map { -$0.timeIntervalSinceNow > Self.refreshInterval } ?? true) {
                await update()
            }
        }
    }

    // MARK: Per-site

    func isAllowed(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return allowlist.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Called before each main-frame navigation; rule lists apply to loads that start after this.
    func prepare(for url: URL?) {
        currentHost = url?.host?.lowercased()
        apply()
    }

    func toggleCurrentSite() {
        guard let host = currentHost else { return }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if isAllowed(host) {
            allowlist.removeAll { host == $0 || host.hasSuffix("." + $0) }
        } else {
            allowlist.append(site)
        }
        apply()
    }

    private func apply() {
        guard let controller else { return }
        controller.removeAllContentRuleLists()
        guard enabled, !isAllowed(currentHost) else { return }
        lists.forEach(controller.add)
    }

    // MARK: Updating

    func update() async {
        guard !isUpdating else { return }
        isUpdating = true
        error = nil
        defer { isUpdating = false }

        var fresh: [WKContentRuleList] = []
        var count = 0
        var failures: [String] = []
        for s in Self.sources {
            do {
                let text = try await HTTP.text(URLRequest(url: s.url, timeoutInterval: 60))
                let rules = await Task.detached(priority: .utility) { FilterConverter.convert(text) }.value
                let (list, used) = try await compileDroppingBadRules(rules, id: s.id)
                fresh.append(list)
                count += used
            } catch {
                failures.append(s.name)
                if let old = try? await store.contentRuleList(forIdentifier: s.id) { fresh.append(old) }
            }
        }
        if !fresh.isEmpty { lists = fresh }
        if count > 0 {
            ruleCount = count
            lastUpdate = Date()
            defaults.set(count, forKey: "adblock.ruleCount")
            defaults.set(lastUpdate, forKey: "adblock.lastUpdate")
        }
        if !failures.isEmpty { error = "Güncellenemedi: " + failures.joined(separator: ", ") }
        apply()
    }

    /// WebKit rejects a whole list for a single rule it cannot compile; find and drop such rules.
    private func compileDroppingBadRules(_ rules: [ContentRule], id: String) async throws -> (WKContentRuleList, Int) {
        if let list = try? await compile(rules, id: id) { return (list, rules.count) }
        let good = try await validSubset(rules)
        try? await store.removeContentRuleList(forIdentifier: "yakala.probe")
        guard let list = try await compile(good, id: id) else { throw DownloadError.empty }
        return (list, good.count)
    }

    private func validSubset(_ rules: [ContentRule]) async throws -> [ContentRule] {
        if rules.isEmpty { return [] }
        if (try? await compile(rules, id: "yakala.probe")) != nil { return rules }
        if rules.count == 1 { return [] }
        let mid = rules.count / 2
        let left = try await validSubset(Array(rules[..<mid]))
        let right = try await validSubset(Array(rules[mid...]))
        return left + right
    }

    private func compile(_ rules: [ContentRule], id: String) async throws -> WKContentRuleList? {
        try await store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: try FilterConverter.json(rules))
    }
}
