import Foundation

/// One WebKit content-blocker rule (the JSON format WKContentRuleListStore compiles).
struct ContentRule: Codable, Equatable, Sendable {
    struct Trigger: Codable, Equatable, Sendable {
        var urlFilter: String
        var caseSensitive: Bool?
        var ifDomain: [String]?
        var unlessDomain: [String]?
        var resourceType: [String]?
        var loadType: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case caseSensitive = "url-filter-is-case-sensitive"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
            case resourceType = "resource-type"
            case loadType = "load-type"
        }
    }

    struct Action: Codable, Equatable, Sendable {
        var type: String
        var selector: String?
    }

    var trigger: Trigger
    var action: Action

    static func block(_ t: Trigger) -> ContentRule { ContentRule(trigger: t, action: Action(type: "block")) }
    static func allow(_ t: Trigger) -> ContentRule { ContentRule(trigger: t, action: Action(type: "ignore-previous-rules")) }
    static func hide(_ selector: String, _ t: Trigger) -> ContentRule {
        ContentRule(trigger: t, action: Action(type: "css-display-none", selector: selector))
    }
}

/// Converts Adblock Plus / EasyList / AdGuard filter syntax to WebKit content-blocker rules.
/// Covers network rules, their common options, exceptions, and plain element hiding.
/// Scriptlets, CSS injection, extended selectors and regex rules are skipped.
enum FilterConverter {
    static let maxRules = 150_000

    private static let allTypes = ["script", "image", "style-sheet", "font", "raw", "media", "document"]
    private static let typeMap: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style-sheet", "font": "font",
        "media": "media", "xmlhttprequest": "raw", "xhr": "raw", "websocket": "raw", "other": "raw",
        "subdocument": "document", "frame": "document", "popup": "popup", "ping": "ping",
    ]
    private static let ignoredOptions: Set<String> = ["important", "~important", "object", "~object", "object-subrequest"]
    private static let unsupportedSelector = [
        ":has(", ":-abp", ":contains", ":has-text", ":xpath", ":style(", ":matches-css", ":upward",
        ":remove(", ":min-text-length", ":watch-attr", ":nth-ancestor", ":matches-attr", ":matches-path",
        ":matches-media", ":others(", ":if(", ":if-not(", ":is(", "[-ext-", ":-ext-",
    ]

    static func convert(_ text: String) -> [ContentRule] {
        var blocks: [ContentRule] = []
        var exceptions: [ContentRule] = []
        var siteAllows: [ContentRule] = []
        var generic: [String] = []
        var genericExceptions = Set<String>()
        var specific: [String: (ContentRule.Trigger, [String])] = [:]
        var specificOrder: [String] = []

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { continue }

            if let r = line.range(of: "#@#") {
                if line[..<r.lowerBound].isEmpty { genericExceptions.insert(String(line[r.upperBound...])) }
                continue
            }
            if line.contains("#?#") || line.contains("#$#") || line.contains("#%#") || line.contains("$$")
                || line.contains("#@?#") || line.contains("#@$#") { continue }
            if let r = line.range(of: "##") {
                let selector = String(line[r.upperBound...])
                guard isUsable(selector: selector) else { continue }
                let domainPart = String(line[..<r.lowerBound])
                if domainPart.isEmpty {
                    generic.append(selector)
                } else if let trigger = domainTrigger(domainPart, separator: ",") {
                    let key = (trigger.ifDomain ?? []).joined(separator: ",") + "|" + (trigger.unlessDomain ?? []).joined(separator: ",")
                    if specific[key] == nil { specificOrder.append(key); specific[key] = (trigger, []) }
                    specific[key]!.1.append(selector)
                }
                continue
            }

            let isException = line.hasPrefix("@@")
            let body = isException ? String(line.dropFirst(2)) : line
            guard let parsed = network(body) else { continue }
            if isException {
                if parsed.wholeSite {
                    if let domains = parsed.trigger.ifDomain {
                        siteAllows.append(.allow(ContentRule.Trigger(urlFilter: ".*", ifDomain: domains)))
                    } else if let host = hostOnly(body) {
                        siteAllows.append(.allow(ContentRule.Trigger(urlFilter: ".*", ifDomain: ["*" + host])))
                    }
                } else {
                    exceptions.append(.allow(parsed.trigger))
                }
            } else if !parsed.wholeSite {
                blocks.append(.block(parsed.trigger))
            }
        }

        var rules = blocks
        let selectors = generic.filter { !genericExceptions.contains($0) }
        for batch in stride(from: 0, to: selectors.count, by: 40) {
            let group = selectors[batch..<min(batch + 40, selectors.count)].joined(separator: ", ")
            rules.append(.hide(group, ContentRule.Trigger(urlFilter: ".*")))
        }
        for key in specificOrder {
            guard let (trigger, sels) = specific[key] else { continue }
            for batch in stride(from: 0, to: sels.count, by: 20) {
                rules.append(.hide(sels[batch..<min(batch + 20, sels.count)].joined(separator: ", "), trigger))
            }
        }
        rules += exceptions
        rules += siteAllows
        return Array(rules.prefix(maxRules))
    }

    struct Network {
        var trigger: ContentRule.Trigger
        var wholeSite: Bool
    }

    static func network(_ rule: String) -> Network? {
        var pattern = rule
        var options: [String] = []
        if let dollar = rule.lastIndex(of: "$"), !rule.hasPrefix("/") || rule[..<dollar].hasSuffix("/") {
            pattern = String(rule[..<dollar])
            options = rule[rule.index(after: dollar)...].split(separator: ",").map { String($0).lowercased() }
        }
        if pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 1 { return nil }

        var trigger = ContentRule.Trigger(urlFilter: "")
        var types = Set<String>()
        var negated = Set<String>()
        var wholeSite = false

        for opt in options {
            if ignoredOptions.contains(opt) { continue }
            if opt.hasPrefix("domain=") {
                guard let t = domainTrigger(String(opt.dropFirst(7)), separator: "|") else { return nil }
                trigger.ifDomain = t.ifDomain
                trigger.unlessDomain = t.unlessDomain
                continue
            }
            switch opt {
            case "third-party", "3p": trigger.loadType = ["third-party"]
            case "~third-party", "first-party", "1p": trigger.loadType = ["first-party"]
            case "match-case": trigger.caseSensitive = true
            case "document", "doc", "elemhide", "ehide", "all": wholeSite = true
            case "generichide", "ghide", "specifichide", "shide": return nil
            default:
                let neg = opt.hasPrefix("~")
                let name = neg ? String(opt.dropFirst()) : opt
                guard let mapped = typeMap[name] else { return nil }
                if neg { negated.insert(mapped) } else { types.insert(mapped) }
            }
        }
        if options.contains("object") && types.isEmpty && negated.isEmpty { return nil }
        if !negated.isEmpty { types = Set(allTypes).subtracting(negated).union(types) }
        if !types.isEmpty { trigger.resourceType = types.sorted() }

        guard let regex = regex(from: pattern) else { return nil }
        if regex == ".*" && trigger.resourceType == nil && trigger.ifDomain == nil && !wholeSite { return nil }
        if regex.count < 4 && regex != ".*" { return nil }
        trigger.urlFilter = regex
        return Network(trigger: trigger, wholeSite: wholeSite)
    }

    /// Filter pattern → WebKit regex (no alternation, quantifier braces, or non-ASCII).
    static func regex(from pattern: String) -> String? {
        var p = Substring(pattern)
        var out = ""
        if p.hasPrefix("||") {
            out = "^[^:]+://+([^:/]+\\.)?"
            p = p.dropFirst(2)
        } else if p.hasPrefix("|") {
            out = "^"
            p = p.dropFirst()
        }
        var anchorEnd = false
        if p.hasSuffix("|") {
            anchorEnd = true
            p = p.dropLast()
        }
        for ch in p {
            switch ch {
            case "*": out += ".*"
            case "^": out += "[/:?=&]"
            case ".", "+", "?", "(", ")", "[", "]", "\\", "$": out += "\\\(ch)"
            case "{", "}", "|": return nil
            default:
                guard ch.isASCII, !ch.isWhitespace else { return nil }
                out.append(ch)
            }
        }
        if anchorEnd { out += "$" }
        if out.isEmpty || out == ".*" { return ".*" }
        while out.hasPrefix(".*") && out.count > 2 { out.removeFirst(2) }
        return out
    }

    /// "a.com,~b.a.com" → if-domain / unless-domain. WebKit cannot mix both in one trigger.
    static func domainTrigger(_ list: String, separator: Character) -> ContentRule.Trigger? {
        var include: [String] = []
        var exclude: [String] = []
        for part in list.split(separator: separator) {
            var d = part.trimmingCharacters(in: .whitespaces).lowercased()
            let neg = d.hasPrefix("~")
            if neg { d.removeFirst() }
            guard !d.isEmpty, d.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
                  !d.hasSuffix(".") else { continue }
            if neg { exclude.append("*" + d) } else { include.append("*" + d) }
        }
        if !include.isEmpty { return ContentRule.Trigger(urlFilter: ".*", ifDomain: include) }
        if !exclude.isEmpty { return ContentRule.Trigger(urlFilter: ".*", unlessDomain: exclude) }
        return nil
    }

    private static func hostOnly(_ rule: String) -> String? {
        guard rule.hasPrefix("||") else { return nil }
        let rest = rule.dropFirst(2)
        let host = rest.prefix { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return host.contains(".") ? host.lowercased() : nil
    }

    private static func isUsable(selector: String) -> Bool {
        guard !selector.isEmpty, selector.allSatisfy(\.isASCII) else { return false }
        let lower = selector.lowercased()
        return !unsupportedSelector.contains { lower.contains($0) }
    }

    static func json(_ rules: [ContentRule]) throws -> String {
        String(decoding: try JSONEncoder().encode(rules), as: UTF8.self)
    }
}
