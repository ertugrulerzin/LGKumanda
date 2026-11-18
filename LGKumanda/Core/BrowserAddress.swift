import Foundation

enum BrowserAddress {
    enum Invalid: LocalizedError {
        case address
        var errorDescription: String? { "Geçerli bir web adresi veya arama gir. Örnek: example.com ya da hava durumu" }
    }
    /// What the typed text will open: a web address, or a Google search for the text.
    enum Target: Equatable {
        case address(URL), search(URL)
        var url: URL { switch self { case .address(let url), .search(let url): return url } }
        var isSearch: Bool { if case .search = self { return true }; return false }
    }
    static func resolve(_ input: String) throws -> URL { try target(input).url }

    static func target(_ input: String) throws -> Target {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.rangeOfCharacter(from: .controlCharacters) == nil else { throw Invalid.address }
        if text.contains("://") { return .address(try webURL(text)) }
        if text.rangeOfCharacter(from: .whitespaces) == nil, hasNonWebScheme(text) { throw Invalid.address }
        if looksLikeHost(text), let url = try? webURL("https://" + text) { return .address(url) }
        return .search(googleSearch(text))
    }

    static func googleSearch(_ query: String) -> URL {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        // Same language, region and no personalisation everywhere, so the phone preview
        // and the TV browser show the same results page.
        return URL(string: "https://www.google.com/search?q=\(encoded)&hl=tr&gl=tr&pws=0")!
    }
    /// The TV's own browser identity; the phone preview asks for the same page the TV gets.
    static let webOSUserAgent = "Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36 WebAppManager"

    private static func webURL(_ candidate: String) throws -> URL {
        guard let parts = URLComponents(string: candidate),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              parts.user == nil, parts.password == nil,
              let url = parts.url else { throw Invalid.address }
        return url
    }
    /// "javascript:…", "mailto:…" and similar; "localhost:8080" is a host with a port, not a scheme.
    private static func hasNonWebScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon], rest = text[text.index(after: colon)...]
        guard let first = scheme.first, first.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+.-".contains($0) }) else { return false }
        let port = rest.prefix { $0.isNumber }
        return port.isEmpty || !(rest.dropFirst(port.count).first.map { "/?#".contains($0) } ?? true)
    }
    /// A host part without spaces that has a dot (example.com, 192.168.1.3) or is localhost.
    private static func looksLikeHost(_ text: String) -> Bool {
        let host = text.prefix { !"/?#".contains($0) }
        guard host.rangeOfCharacter(from: .whitespaces) == nil, !host.contains("@") else { return false }
        let name = host.split(separator: ":").first.map(String.init) ?? ""
        if name.lowercased() == "localhost" { return true }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { !$0.isEmpty } && labels.last!.contains(where: \.isLetter) || isIPv4(name)
    }
    private static func isIPv4(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }
}
