import Foundation

/// How a DASH representation is fetched: as numbered segments, or as one whole file.
enum DASHPlan: Sendable, Equatable {
    case segments(HLSMediaPlaylist)
    case single(URL)
}

struct DASHRepresentation: Sendable, Equatable {
    enum Kind: Sendable { case video, audio, text }

    var id: String
    var kind: Kind
    var bandwidth: Int
    var width: Int?
    var height: Int?
    var codecs: String?
    var mimeType: String
    var language: String?
    var label: String?
    var encrypted: Bool
    var plan: DASHPlan

    var qualityLabel: String {
        let mbps = String(format: "%.1f Mb/sn", Double(bandwidth) / 1_000_000)
        if let height { return "\(height)p · \(mbps)" }
        return mbps
    }
}

struct DASHManifest: Sendable {
    var duration: Double
    var isLive: Bool
    var representations: [DASHRepresentation]

    var videos: [DASHRepresentation] {
        representations.filter { $0.kind == .video }
            .sorted { ($0.height ?? 0, $0.bandwidth) > ($1.height ?? 0, $1.bandwidth) }
    }

    var bestAudio: DASHRepresentation? {
        representations.filter { $0.kind == .audio && !$0.encrypted }.max { $0.bandwidth < $1.bandwidth }
    }

    /// Text tracks that are plain files (WebVTT / TTML), the kind a player can save directly.
    var subtitleFiles: [DASHRepresentation] {
        representations.filter {
            guard $0.kind == .text, case .single = $0.plan else { return false }
            return true
        }
    }

    var hasDRM: Bool {
        let main = videos.isEmpty ? representations.filter { $0.kind == .audio } : videos
        return !main.isEmpty && main.allSatisfy(\.encrypted)
    }
}

enum DASHParser {
    static func parse(_ data: Data, url: URL) throws -> DASHManifest {
        let doc = try XMLDocument(data: data)
        guard let mpd = doc.rootElement(), mpd.localName == "MPD" else { throw DownloadError.notPlaylist }
        let isLive = attr(mpd, "type") == "dynamic"
        let mpdDuration = duration(attr(mpd, "mediaPresentationDuration"))
        let mpdBase = base(mpd, url)

        let periods = kids(mpd, "Period")
        guard !periods.isEmpty else { throw DownloadError.empty }
        // Ad breaks come as short extra periods; the programme is the longest one.
        let period = periods.max {
            (duration(attr($0, "duration")) ?? mpdDuration ?? 0) < (duration(attr($1, "duration")) ?? mpdDuration ?? 0)
        }!
        let periodDuration = duration(attr(period, "duration")) ?? mpdDuration ?? 0
        let periodBase = base(period, mpdBase)

        var reps: [DASHRepresentation] = []
        for set in kids(period, "AdaptationSet") {
            let setBase = base(set, periodBase)
            let setProtected = !kids(set, "ContentProtection").isEmpty
            for rep in kids(set, "Representation") {
                let mime = attr(rep, "mimeType") ?? attr(set, "mimeType") ?? ""
                let codecs = attr(rep, "codecs") ?? attr(set, "codecs")
                let contentType = attr(set, "contentType") ?? String(mime.split(separator: "/").first ?? "")
                let kind: DASHRepresentation.Kind
                if contentType == "text" || mime.contains("vtt") || mime.contains("ttml")
                    || ["wvtt", "stpp"].contains(where: { codecs?.hasPrefix($0) == true }) {
                    kind = .text
                } else if contentType == "audio" {
                    kind = .audio
                } else if contentType == "video" || attr(rep, "height") != nil {
                    kind = .video
                } else {
                    continue
                }
                let id = attr(rep, "id") ?? UUID().uuidString
                let bandwidth = Int(attr(rep, "bandwidth") ?? "") ?? 0
                let repBase = base(rep, setBase)
                let plan: DASHPlan
                if let tpl = template(set: set, rep: rep) {
                    plan = .segments(segments(tpl, id: id, bandwidth: bandwidth, base: repBase, periodDuration: periodDuration))
                } else if let list = kids(rep, "SegmentList").first ?? kids(set, "SegmentList").first {
                    plan = .segments(segments(list: list, base: repBase))
                } else {
                    plan = .single(repBase)
                }
                reps.append(DASHRepresentation(
                    id: id, kind: kind, bandwidth: bandwidth,
                    width: Int(attr(rep, "width") ?? attr(set, "width") ?? ""),
                    height: Int(attr(rep, "height") ?? attr(set, "height") ?? ""),
                    codecs: codecs, mimeType: mime,
                    language: attr(set, "lang") ?? attr(rep, "lang"),
                    label: kids(set, "Label").first?.stringValue ?? attr(set, "label"),
                    encrypted: setProtected || !kids(rep, "ContentProtection").isEmpty,
                    plan: plan
                ))
            }
        }
        return DASHManifest(duration: periodDuration, isLive: isLive, representations: reps)
    }

    // MARK: Segment templates

    struct Template {
        var media: String?
        var initialization: String?
        var startNumber = 1
        var timescale = 1.0
        var duration: Double?
        var timeline: [XMLElement] = []
    }

    /// AdaptationSet-level SegmentTemplate with Representation-level overrides.
    static func template(set: XMLElement, rep: XMLElement) -> Template? {
        let layers = [kids(set, "SegmentTemplate").first, kids(rep, "SegmentTemplate").first].compactMap { $0 }
        guard !layers.isEmpty else { return nil }
        var t = Template()
        for l in layers {
            if let v = attr(l, "media") { t.media = v }
            if let v = attr(l, "initialization") { t.initialization = v }
            if let v = attr(l, "startNumber").flatMap(Int.init) { t.startNumber = v }
            if let v = attr(l, "timescale").flatMap(Double.init) { t.timescale = v }
            if let v = attr(l, "duration").flatMap(Double.init) { t.duration = v }
            if let tl = kids(l, "SegmentTimeline").first { t.timeline = kids(tl, "S") }
            if t.initialization == nil, let i = kids(l, "Initialization").first { t.initialization = attr(i, "sourceURL") }
        }
        return t.media == nil ? nil : t
    }

    static func segments(_ t: Template, id: String, bandwidth: Int, base: URL, periodDuration: Double) -> HLSMediaPlaylist {
        var segs: [HLSSegment] = []
        func add(number: Int, time: Int, d: Double) {
            let path = expand(t.media ?? "", id: id, bandwidth: bandwidth, number: number, time: time)
            if let url = URL(string: path, relativeTo: base)?.absoluteURL {
                segs.append(HLSSegment(url: url, duration: d / t.timescale, sequence: segs.count))
            }
        }
        if !t.timeline.isEmpty {
            var time = 0
            var number = t.startNumber
            let end = Int(periodDuration * t.timescale)
            for (i, s) in t.timeline.enumerated() {
                if let st = attr(s, "t").flatMap(Int.init) { time = st }
                guard let d = attr(s, "d").flatMap(Int.init), d > 0 else { continue }
                var r = attr(s, "r").flatMap(Int.init) ?? 0
                if r < 0 {
                    // Repeat until the next S element starts, or until the period ends.
                    let next = i + 1 < t.timeline.count ? attr(t.timeline[i + 1], "t").flatMap(Int.init) : nil
                    r = max(0, Int((Double((next ?? end) - time) / Double(d)).rounded(.up)) - 1)
                }
                for _ in 0...r {
                    add(number: number, time: time, d: Double(d))
                    time += d
                    number += 1
                }
            }
        } else if let d = t.duration, d > 0 {
            let count = max(1, Int((periodDuration * t.timescale / d).rounded(.up)))
            for i in 0..<count {
                add(number: t.startNumber + i, time: Int(Double(i) * d), d: d)
            }
        }
        let initSection = t.initialization.flatMap {
            URL(string: expand($0, id: id, bandwidth: bandwidth, number: nil, time: nil), relativeTo: base)?.absoluteURL
        }.map { HLSInitSection(url: $0) }
        return HLSMediaPlaylist(targetDuration: segs.map(\.duration).max() ?? 0, mediaSequence: 0,
                                segments: segs, endList: true, initSection: initSection)
    }

    static func segments(list: XMLElement, base: URL) -> HLSMediaPlaylist {
        let timescale = attr(list, "timescale").flatMap(Double.init) ?? 1
        let d = (attr(list, "duration").flatMap(Double.init) ?? 0) / timescale
        var segs: [HLSSegment] = []
        for s in kids(list, "SegmentURL") {
            let url = attr(s, "media").flatMap { URL(string: $0, relativeTo: base)?.absoluteURL } ?? base
            segs.append(HLSSegment(url: url, duration: d, sequence: segs.count, byteRange: range(attr(s, "mediaRange"))))
        }
        var initSection: HLSInitSection?
        if let i = kids(list, "Initialization").first {
            let url = attr(i, "sourceURL").flatMap { URL(string: $0, relativeTo: base)?.absoluteURL } ?? base
            initSection = HLSInitSection(url: url, byteRange: range(attr(i, "range")))
        }
        return HLSMediaPlaylist(targetDuration: d, mediaSequence: 0, segments: segs, endList: true, initSection: initSection)
    }

    /// $RepresentationID$, $Bandwidth$, $Number$, $Time$ with optional %0Nd width; $$ is a literal $.
    static func expand(_ template: String, id: String, bandwidth: Int, number: Int?, time: Int?) -> String {
        var out = ""
        var rest = Substring(template)
        while let start = rest.firstIndex(of: "$") {
            out += rest[..<start]
            let after = rest.index(after: start)
            guard let end = rest[after...].firstIndex(of: "$") else { out += rest[start...]; return out }
            let token = rest[after..<end]
            rest = rest[rest.index(after: end)...]
            if token.isEmpty { out += "$"; continue }
            let parts = token.split(separator: "%", maxSplits: 1)
            let name = String(parts[0])
            var width = 0
            if parts.count > 1, parts[1].hasSuffix("d") {
                width = Int(parts[1].dropFirst().dropLast()) ?? 0
            }
            let value: String?
            switch name {
            case "RepresentationID": value = id
            case "Bandwidth": value = String(bandwidth)
            case "Number": value = number.map(String.init)
            case "Time": value = time.map(String.init)
            default: value = nil
            }
            guard var v = value else { out += "$\(token)$"; continue }
            if v.count < width { v = String(repeating: "0", count: width - v.count) + v }
            out += v
        }
        return out + rest
    }

    // MARK: XML helpers

    static func kids(_ e: XMLElement, _ name: String) -> [XMLElement] {
        (e.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == name }
    }

    static func attr(_ e: XMLElement, _ name: String) -> String? {
        e.attribute(forName: name)?.stringValue
    }

    static func base(_ e: XMLElement, _ parent: URL) -> URL {
        guard let text = kids(e, "BaseURL").first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, let url = URL(string: text, relativeTo: parent)?.absoluteURL else { return parent }
        return url
    }

    static func range(_ s: String?) -> HLSByteRange? {
        guard let parts = s?.split(separator: "-"), parts.count == 2,
              let a = Int(parts[0]), let b = Int(parts[1]), b >= a else { return nil }
        return HLSByteRange(length: b - a + 1, offset: a)
    }

    /// ISO 8601 duration such as "PT1H2M3.5S" or "P1DT2H".
    static func duration(_ s: String?) -> Double? {
        guard let s, s.hasPrefix("P") else { return nil }
        var total = 0.0
        var number = ""
        var inTime = false
        for ch in s.dropFirst() {
            switch ch {
            case "T": inTime = true
            case "0"..."9", ".": number.append(ch)
            default:
                let v = Double(number) ?? 0
                number = ""
                switch (ch, inTime) {
                case ("D", _): total += v * 86400
                case ("H", true): total += v * 3600
                case ("M", true): total += v * 60
                case ("S", true): total += v
                default: break
                }
            }
        }
        return total
    }
}
