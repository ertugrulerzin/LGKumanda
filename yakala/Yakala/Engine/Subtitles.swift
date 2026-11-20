import Foundation

/// A subtitle track to fetch: an HLS subtitle playlist or a single file (.vtt, .srt…).
struct SubtitleSource: Sendable, Hashable, Codable {
    var url: URL
    var name: String
    var language: String?
    var isPlaylist: Bool
}

/// A downloaded subtitle as WebVTT or SRT text.
struct SubtitleFile: Sendable {
    var file: URL
    var name: String
    var language: String?
}

enum Subtitles {
    static func fetch(_ source: SubtitleSource, ctx: HTTPContext, into dir: URL, index: Int) async throws -> SubtitleFile {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text: String
        var ext = source.url.pathExtension.lowercased()
        if source.isPlaylist {
            let listText = try await HTTP.text(ctx.request(source.url))
            guard case .media(let playlist) = try HLSParser.parse(listText, baseURL: source.url) else {
                throw DownloadError.notPlaylist
            }
            var parts: [String] = []
            for seg in playlist.segments {
                parts.append(decode(try await HTTP.data(ctx.request(seg.url, range: seg.byteRange))))
            }
            text = mergeVTT(parts)
            ext = "vtt"
        } else {
            text = decode(try await HTTP.data(ctx.request(source.url)))
            if !["vtt", "srt", "ass", "ssa", "ttml", "dfxp"].contains(ext) {
                ext = text.hasPrefix("WEBVTT") ? "vtt" : "srt"
            }
        }
        let file = dir.appendingPathComponent("sub-\(index).\(ext)")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return SubtitleFile(file: file, name: source.name, language: source.language)
    }

    static func decode(_ data: Data) -> String {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d.removeFirst(3) }
        if let s = String(data: d, encoding: .utf8) { return s }
        return String(data: d, encoding: .windowsCP1254) ?? String(decoding: d, as: UTF8.self)
    }

    /// Joins segmented WebVTT into one file: one header, no repeated cues.
    static func mergeVTT(_ parts: [String]) -> String {
        var cues: [String] = []
        var seen = Set<String>()
        for part in parts {
            for block in blocks(part) {
                let first = block.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
                if first.hasPrefix("WEBVTT") || first.hasPrefix("NOTE") || first.hasPrefix("STYLE")
                    || first.hasPrefix("REGION") || first.hasPrefix("X-TIMESTAMP-MAP") { continue }
                guard block.contains("-->") else { continue }
                if seen.insert(stripIdentifier(block)).inserted { cues.append(block) }
            }
        }
        return "WEBVTT\n\n" + cues.joined(separator: "\n\n") + "\n"
    }

    static func vttToSRT(_ vtt: String) -> String {
        var out: [String] = []
        var n = 0
        for block in blocks(vtt) {
            var lines = block.components(separatedBy: "\n")
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            lines.removeFirst(timing)
            let parts = lines[0].components(separatedBy: "-->")
            guard parts.count == 2 else { continue }
            let start = srtTime(parts[0])
            let end = srtTime(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0])
            let text = lines.dropFirst().map(stripTags).joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            n += 1
            out.append("\(n)\n\(start) --> \(end)\n\(text)")
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    private static func blocks(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
    }

    private static func stripIdentifier(_ block: String) -> String {
        guard let r = block.range(of: "-->") else { return block }
        let lineStart = block[..<r.lowerBound].lastIndex(of: "\n").map { block.index(after: $0) } ?? block.startIndex
        return String(block[lineStart...])
    }

    /// "1:02.5" / "00:01:02.500" → "00:01:02,500"
    static func srtTime(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        let main = t.split(separator: ".", maxSplits: 1)
        var fields = main[0].split(separator: ":").map { Int($0) ?? 0 }
        while fields.count < 3 { fields.insert(0, at: 0) }
        var ms = main.count > 1 ? String(main[1].prefix(3)) : "0"
        while ms.count < 3 { ms += "0" }
        return String(format: "%02d:%02d:%02d,%@", fields[0], fields[1], fields[2], ms)
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<(?!/?[ibu]>)[^>]+>", with: "", options: .regularExpression)
    }

    /// ISO 639-1 → ISO 639-2 for MP4 track language tags.
    static func iso639_2(_ code: String?) -> String? {
        guard let c = code?.lowercased().split(separator: "-").first.map(String.init) else { return nil }
        if c.count == 3 { return c }
        let map = ["tr": "tur", "en": "eng", "de": "ger", "fr": "fre", "es": "spa", "it": "ita", "ru": "rus",
                   "ar": "ara", "ja": "jpn", "ko": "kor", "zh": "chi", "pt": "por", "nl": "dut", "pl": "pol",
                   "el": "gre", "he": "heb", "fa": "per", "hi": "hin", "sv": "swe", "da": "dan", "no": "nor",
                   "fi": "fin", "cs": "cze", "hu": "hun", "ro": "rum", "uk": "ukr", "az": "aze", "bg": "bul"]
        return map[c]
    }
}
