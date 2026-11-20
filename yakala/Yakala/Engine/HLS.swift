import Foundation

struct HLSByteRange: Equatable, Sendable {
    var length: Int
    var offset: Int
}

struct HLSKey: Equatable, Sendable {
    var method: String
    var uri: URL?
    var iv: Data?
    var keyFormat: String?

    /// Plain AES-128 is ordinary HLS transport encryption. SAMPLE-AES and
    /// vendor key formats (FairPlay, Widevine, PlayReady) are DRM.
    var isDRM: Bool {
        if method == "NONE" { return false }
        if method != "AES-128" { return true }
        if let f = keyFormat, f.lowercased() != "identity" { return true }
        return false
    }
}

struct HLSSegment: Equatable, Sendable {
    var url: URL
    var duration: Double
    var sequence: Int
    var key: HLSKey?
    var byteRange: HLSByteRange?
}

struct HLSInitSection: Equatable, Sendable {
    var url: URL
    var byteRange: HLSByteRange?
}

struct HLSMediaPlaylist: Equatable, Sendable {
    var targetDuration: Double
    var mediaSequence: Int
    var segments: [HLSSegment]
    var endList: Bool
    var initSection: HLSInitSection?

    var totalDuration: Double { segments.reduce(0) { $0 + $1.duration } }
    var isLive: Bool { !endList }
    var hasDRM: Bool { segments.contains { $0.key?.isDRM == true } }
}

struct HLSVariant: Equatable, Hashable, Sendable {
    var url: URL
    var bandwidth: Int
    var resolution: String?
    var codecs: String?
    var audioGroup: String?

    var height: Int? { resolution?.split(separator: "x").last.flatMap { Int($0) } }

    var label: String {
        let mbps = String(format: "%.1f Mb/sn", Double(bandwidth) / 1_000_000)
        if let h = height { return "\(h)p · \(mbps)" }
        return mbps
    }
}

struct HLSRendition: Equatable, Hashable, Sendable {
    var type: String
    var groupID: String
    var name: String?
    var language: String?
    var isDefault: Bool
    var url: URL?
}

struct HLSMasterPlaylist: Equatable, Sendable {
    var variants: [HLSVariant]
    var renditions: [HLSRendition]

    func audio(for variant: HLSVariant) -> HLSRendition? {
        guard let group = variant.audioGroup else { return nil }
        let options = renditions.filter { $0.type == "AUDIO" && $0.groupID == group && $0.url != nil }
        return options.first(where: \.isDefault) ?? options.first
    }
}

enum HLSPlaylist: Equatable, Sendable {
    case master(HLSMasterPlaylist)
    case media(HLSMediaPlaylist)
}

enum HLSParser {
    static func parse(_ text: String, baseURL: URL) throws -> HLSPlaylist {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first, first.hasPrefix("#EXTM3U") else {
            throw DownloadError.notPlaylist
        }
        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
            return .master(parseMaster(lines, baseURL: baseURL))
        }
        return .media(parseMedia(lines, baseURL: baseURL))
    }

    static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var i = text.startIndex
        while i < text.endIndex {
            guard let eq = text[i...].firstIndex(of: "=") else { break }
            let key = text[i..<eq].trimmingCharacters(in: .whitespaces)
            var j = text.index(after: eq)
            var value = ""
            if j < text.endIndex, text[j] == "\"" {
                j = text.index(after: j)
                let close = text[j...].firstIndex(of: "\"") ?? text.endIndex
                value = String(text[j..<close])
                j = close < text.endIndex ? text.index(after: close) : close
                if j < text.endIndex, text[j] == "," { j = text.index(after: j) }
            } else {
                let comma = text[j...].firstIndex(of: ",") ?? text.endIndex
                value = String(text[j..<comma])
                j = comma < text.endIndex ? text.index(after: comma) : comma
            }
            result[key] = value
            i = j
        }
        return result
    }

    private static func value(_ line: String, after tag: String) -> String {
        String(line.dropFirst(tag.count))
    }

    private static func resolve(_ s: String, _ base: URL) -> URL? {
        URL(string: s, relativeTo: base)?.absoluteURL
    }

    static func hexData(_ s: String) -> Data? {
        var hex = s.lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard !hex.isEmpty, hex.count <= 32 else { return nil }
        hex = String(repeating: "0", count: 32 - hex.count) + hex
        var data = Data(capacity: 16)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        return data
    }

    /// "length[@offset]"
    private static func byteRange(_ s: String) -> (Int, Int?)? {
        let parts = s.split(separator: "@")
        guard let len = parts.first.flatMap({ Int($0) }) else { return nil }
        return (len, parts.count > 1 ? Int(parts[1]) : nil)
    }

    private static func parseMaster(_ lines: [String], baseURL: URL) -> HLSMasterPlaylist {
        var variants: [HLSVariant] = []
        var renditions: [HLSRendition] = []
        var pending: [String: String]?
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pending = attributes(value(line, after: "#EXT-X-STREAM-INF:"))
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                let a = attributes(value(line, after: "#EXT-X-MEDIA:"))
                renditions.append(HLSRendition(
                    type: a["TYPE"] ?? "",
                    groupID: a["GROUP-ID"] ?? "",
                    name: a["NAME"],
                    language: a["LANGUAGE"],
                    isDefault: a["DEFAULT"] == "YES",
                    url: a["URI"].flatMap { resolve($0, baseURL) }
                ))
            } else if !line.hasPrefix("#"), let a = pending {
                if let url = resolve(line, baseURL) {
                    variants.append(HLSVariant(
                        url: url,
                        bandwidth: Int(a["AVERAGE-BANDWIDTH"] ?? a["BANDWIDTH"] ?? "") ?? 0,
                        resolution: a["RESOLUTION"],
                        codecs: a["CODECS"],
                        audioGroup: a["AUDIO"]
                    ))
                }
                pending = nil
            }
        }
        variants.sort { ($0.height ?? 0, $0.bandwidth) > ($1.height ?? 0, $1.bandwidth) }
        return HLSMasterPlaylist(variants: variants, renditions: renditions)
    }

    private static func parseMedia(_ lines: [String], baseURL: URL) -> HLSMediaPlaylist {
        var target = 0.0
        var mediaSequence = 0
        var segments: [HLSSegment] = []
        var endList = false
        var initSection: HLSInitSection?
        var key: HLSKey?
        var duration: Double?
        var range: (Int, Int?)?
        var lastRangeEnd: [URL: Int] = [:]

        for line in lines {
            if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                target = Double(value(line, after: "#EXT-X-TARGETDURATION:")) ?? 0
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                mediaSequence = Int(value(line, after: "#EXT-X-MEDIA-SEQUENCE:")) ?? 0
            } else if line.hasPrefix("#EXTINF:") {
                let v = value(line, after: "#EXTINF:")
                duration = Double(v.split(separator: ",", omittingEmptySubsequences: false).first ?? "") ?? 0
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                range = byteRange(value(line, after: "#EXT-X-BYTERANGE:"))
            } else if line.hasPrefix("#EXT-X-KEY:") {
                let a = attributes(value(line, after: "#EXT-X-KEY:"))
                let method = a["METHOD"] ?? "NONE"
                key = method == "NONE" ? nil : HLSKey(
                    method: method,
                    uri: a["URI"].flatMap { resolve($0, baseURL) },
                    iv: a["IV"].flatMap(hexData),
                    keyFormat: a["KEYFORMAT"]
                )
            } else if line.hasPrefix("#EXT-X-MAP:") {
                let a = attributes(value(line, after: "#EXT-X-MAP:"))
                if let url = a["URI"].flatMap({ resolve($0, baseURL) }) {
                    let r = a["BYTERANGE"].flatMap(byteRange)
                    initSection = HLSInitSection(
                        url: url,
                        byteRange: r.map { HLSByteRange(length: $0.0, offset: $0.1 ?? 0) }
                    )
                }
            } else if line.hasPrefix("#EXT-X-ENDLIST") {
                endList = true
            } else if line == "#EXT-X-PLAYLIST-TYPE:VOD" {
                endList = true
            } else if !line.hasPrefix("#") {
                guard let url = resolve(line, baseURL) else { continue }
                var br: HLSByteRange?
                if let (len, off) = range {
                    let offset = off ?? lastRangeEnd[url] ?? 0
                    br = HLSByteRange(length: len, offset: offset)
                    lastRangeEnd[url] = offset + len
                }
                segments.append(HLSSegment(
                    url: url,
                    duration: duration ?? 0,
                    sequence: mediaSequence + segments.count,
                    key: key,
                    byteRange: br
                ))
                duration = nil
                range = nil
            }
        }
        return HLSMediaPlaylist(
            targetDuration: target,
            mediaSequence: mediaSequence,
            segments: segments,
            endList: endList,
            initSection: initSection
        )
    }
}
