import Foundation
import Observation

enum MediaKind: Equatable {
    case hls
    case dash
    case file(String)
    case subtitle(String)

    static let subtitleExtensions = ["vtt", "srt", "ass", "ssa", "ttml", "dfxp"]

    static func classify(_ url: URL, hint: String) -> MediaKind? {
        let h = hint.lowercased()
        let ext = url.pathExtension.lowercased()
        let s = url.absoluteString.lowercased()
        if h.contains("mpegurl") || ext == "m3u8" || s.contains(".m3u8") { return .hls }
        if h.contains("dash+xml") || ext == "mpd" { return .dash }
        if subtitleExtensions.contains(ext) { return .subtitle(ext) }
        if h == "subtitle" || h.hasPrefix("text/vtt") { return .subtitle("vtt") }
        if ["mp4", "m4v", "webm", "flv", "mov"].contains(ext) { return .file(ext) }
        if h.hasPrefix("video/") { return .file(h.contains("webm") ? "webm" : "mp4") }
        if h == "media" { return .file("mp4") }
        return nil
    }

    var badge: String {
        switch self {
        case .hls: return "HLS"
        case .dash: return "DASH"
        case .file(let ext), .subtitle(let ext): return ext.uppercased()
        }
    }

    var isSubtitle: Bool {
        if case .subtitle = self { return true }
        return false
    }
}

@MainActor
@Observable
final class DetectedMedia: Identifiable {
    enum Status: Equatable {
        case probing, ready
        case failed(String)
    }

    let id = UUID()
    let url: URL
    var kind: MediaKind
    let ctx: HTTPContext
    var title: String
    var status: Status = .probing
    var variants: [HLSVariant] = []
    var master: HLSMasterPlaylist?
    var selected: HLSVariant?
    var subtitleTracks: [HLSRendition] = []
    /// "all", "none", or one track's URL.
    var subtitleSelection = "all"
    var duration: Double?
    var isLive = false
    var size: Int64?
    var hidden = false

    init(url: URL, kind: MediaKind, ctx: HTTPContext, title: String) {
        self.url = url
        self.kind = kind
        self.ctx = ctx
        self.title = title
    }

    var summary: String {
        var parts: [String] = []
        if isLive { parts.append("Canlı yayın") }
        if variants.count > 1 { parts.append("\(variants.count) kalite") }
        if !subtitleTracks.isEmpty { parts.append("\(subtitleTracks.count) altyazı") }
        if let duration, duration > 0, !isLive { parts.append(Format.duration(duration)) }
        if let size { parts.append(Format.bytes(size)) }
        return parts.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class DownloadItem: Identifiable {
    enum Source: Codable {
        case hls(video: URL, audio: URL?, subtitles: [SubtitleSource])
        case file(URL, ext: String)
        case subtitle(SubtitleSource)
    }

    enum State: Equatable, Codable {
        case running, paused, muxing
        case done(URL)
        case failed(String)
    }

    /// What survives an app restart.
    struct Record: Codable {
        var id: UUID
        var title: String
        var source: Source
        var ctx: HTTPContext
        var isLive: Bool
        var state: State
        var detail: String
    }

    let id: UUID
    let title: String
    let source: Source
    let ctx: HTTPContext
    let isLive: Bool
    let workDir: URL
    var state: State = .running
    var progress: Double?
    var detail = ""
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var stop = StopFlag()

    init(id: UUID = UUID(), title: String, source: Source, ctx: HTTPContext, isLive: Bool) {
        self.id = id
        self.title = title
        self.source = source
        self.ctx = ctx
        self.isLive = isLive
        workDir = Storage.jobs.appendingPathComponent(id.uuidString)
    }

    var record: Record {
        Record(id: id, title: title, source: source, ctx: ctx, isLive: isLive, state: state, detail: detail)
    }

    func apply(_ p: HLSProgress) {
        guard state == .running else { return }
        if p.live {
            progress = nil
            detail = "Kaydediliyor · \(Format.duration(p.seconds)) · \(Format.bytes(p.bytes))"
        } else {
            progress = p.total > 0 ? Double(p.done) / Double(p.total) : nil
            detail = "\(p.done)/\(p.total) parça · \(Format.bytes(p.bytes))"
        }
    }

    func apply(bytes: Int64, total: Int64?) {
        guard state == .running else { return }
        if let total, total > 0 {
            progress = Double(bytes) / Double(total)
            detail = "\(Format.bytes(bytes)) / \(Format.bytes(total))"
        } else {
            progress = nil
            detail = Format.bytes(bytes)
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var detected: [DetectedMedia] = []
    var downloads: [DownloadItem] = []
    let browser = BrowserModel()

    @ObservationIgnored private var childURLs = Set<String>()
    @ObservationIgnored private var hlsFolders = Set<String>()

    init() {
        browser.app = self
        restoreDownloads()
    }

    // MARK: Persistence

    private func restoreDownloads() {
        guard let data = try? Data(contentsOf: Storage.downloadsFile),
              let records = try? JSONDecoder().decode([DownloadItem.Record].self, from: data) else { return }
        for r in records {
            let item = DownloadItem(id: r.id, title: r.title, source: r.source, ctx: r.ctx, isLive: r.isLive)
            item.state = r.state
            item.detail = r.detail
            if case .done = r.state { item.progress = 1 }
            downloads.append(item)
        }
        // Whatever was downloading when the app quit picks up where it stopped.
        for item in downloads where item.state == .running || item.state == .muxing {
            start(item)
        }
    }

    func saveDownloads() {
        let records = downloads.map(\.record)
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(at: Storage.root, withIntermediateDirectories: true)
        try? data.write(to: Storage.downloadsFile, options: .atomic)
    }

    var visibleDetected: [DetectedMedia] { detected.filter { !$0.hidden } }

    // MARK: Detection

    func pageChanged() {
        detected.removeAll()
        childURLs.removeAll()
        hlsFolders.removeAll()
    }

    func report(url: URL, hint: String, page: URL?, title: String, label: String = "") {
        guard let kind = MediaKind.classify(url, hint: hint) else { return }
        let key = url.absoluteString
        guard !detected.contains(where: { $0.url.absoluteString == key }) else { return }
        let ctx = HTTPContext(referer: page, userAgent: browser.userAgent)
        var name = title.isEmpty ? url.lastPathComponent : title
        if kind.isSubtitle, !label.isEmpty { name += " – \(label)" }
        let item = DetectedMedia(url: url, kind: kind, ctx: ctx, title: name)
        item.hidden = childURLs.contains(key)
        detected.append(item)
        Task { await probe(item) }
    }

    private func folder(_ url: URL) -> String { url.deletingLastPathComponent().absoluteString }

    private func probe(_ item: DetectedMedia) async {
        do {
            switch item.kind {
            case .dash:
                item.status = .failed("DASH henüz desteklenmiyor.")
            case .hls:
                try await probeHLS(item)
            case .subtitle:
                if hlsFolders.contains(folder(item.url)) { item.hidden = true; return }
                item.status = .ready
            case .file:
                if hlsFolders.contains(folder(item.url)) { item.hidden = true; return }
                let p = try await FileDownloader.probe(item.url, ctx: item.ctx)
                if let type = p.contentType?.lowercased(), type.contains("mpegurl") {
                    item.kind = .hls
                    try await probeHLS(item)
                    return
                }
                item.size = p.size
                if let s = p.size, s < 512 * 1024 { item.hidden = true }
                item.status = .ready
            }
        } catch {
            item.status = .failed(error.localizedDescription)
        }
    }

    private func probeHLS(_ item: DetectedMedia) async throws {
        hlsFolders.insert(folder(item.url))
        let text = try await HTTP.text(item.ctx.request(item.url))
        var media: HLSMediaPlaylist?
        switch try HLSParser.parse(text, baseURL: item.url) {
        case .master(let m):
            item.master = m
            item.variants = m.variants
            item.selected = m.variants.first
            item.subtitleTracks = m.subtitles
            let children = m.variants.map(\.url) + m.renditions.compactMap(\.url)
            for c in children {
                childURLs.insert(c.absoluteString)
                hlsFolders.insert(folder(c))
            }
            for d in detected where childURLs.contains(d.url.absoluteString) || (d.kind != .hls && hlsFolders.contains(folder(d.url))) {
                d.hidden = true
            }
            if let first = m.variants.first,
               case .media(let mm) = try HLSParser.parse(try await HTTP.text(item.ctx.request(first.url)), baseURL: first.url) {
                media = mm
            }
        case .media(let m):
            media = m
        }
        if let media {
            if media.hasDRM { item.status = .failed(DownloadError.drm.localizedDescription); return }
            item.isLive = media.isLive
            item.duration = media.totalDuration
        }
        item.status = .ready
    }

    // MARK: Downloads

    func download(_ media: DetectedMedia) {
        let source: DownloadItem.Source
        switch media.kind {
        case .hls:
            let variant = media.selected
            let audio = variant.flatMap { media.master?.audio(for: $0)?.url }
            let tracks = media.subtitleTracks.filter {
                media.subtitleSelection == "all" || $0.url?.absoluteString == media.subtitleSelection
            }
            let subtitles = tracks.compactMap { r in
                r.url.map { SubtitleSource(url: $0, name: r.name ?? r.language ?? "Altyazı", language: r.language, isPlaylist: true) }
            }
            source = .hls(video: variant?.url ?? media.url, audio: audio, subtitles: subtitles)
        case .file(let ext):
            source = .file(media.url, ext: ext)
        case .subtitle:
            source = .subtitle(SubtitleSource(url: media.url, name: media.title, language: nil, isPlaylist: false))
        case .dash:
            return
        }
        var ctx = media.ctx
        if ctx.userAgent == nil { ctx.userAgent = browser.userAgent }
        var title = media.title
        if let h = media.selected?.height, media.variants.count > 1 { title += " \(h)p" }
        let item = DownloadItem(title: title, source: source, ctx: ctx, isLive: media.isLive)
        downloads.insert(item, at: 0)
        start(item)
    }

    func start(_ item: DownloadItem) {
        item.state = .running
        item.stop = StopFlag()
        item.detail = "Başlıyor…"
        saveDownloads()
        let browser = browser
        item.task = Task {
            var retries = 0
            while true {
                await browser.syncCookies()
                do {
                    let output = try await run(item)
                    item.state = .done(output)
                    item.progress = 1
                    item.detail = Format.bytes(Int64((try? output.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0))
                    try? FileManager.default.removeItem(at: item.workDir)
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        item.state = .paused
                        item.detail = "Duraklatıldı"
                    } else if Self.isTransient(error), retries < Self.maxAutoRetries {
                        // Dropped connection or rate limit: wait, then continue from the saved parts.
                        retries += 1
                        let delay = min(60, 5 * (1 << (retries - 1)))
                        item.state = .running
                        item.progress = nil
                        item.detail = "Bağlantı sorunu (\(error.localizedDescription)) · \(delay) sn sonra devam edecek"
                        do {
                            try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                            continue
                        } catch {
                            item.state = .paused
                            item.detail = "Duraklatıldı"
                        }
                    } else {
                        item.state = .failed(error.localizedDescription)
                    }
                }
                break
            }
            saveDownloads()
        }
    }

    static let maxAutoRetries = 6

    nonisolated static func isTransient(_ error: Error) -> Bool {
        if case DownloadError.http(let code) = error { return code == 408 || code == 429 || code >= 500 }
        guard let u = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                .cannotFindHost, .dnsLookupFailed, .secureConnectionFailed, .cannotLoadFromNetwork,
                .dataNotAllowed, .internationalRoamingOff, .callIsActive].contains(u.code)
    }

    private func run(_ item: DownloadItem) async throws -> URL {
        let ctx = item.ctx
        let dir = item.workDir
        let stop = item.stop
        switch item.source {
        case .hls(let videoURL, let audioURL, let subtitleSources):
            let report: @Sendable (HLSProgress) -> Void = { [weak item] p in
                Task { @MainActor in item?.apply(p) }
            }
            async let video = HLSTrackDownloader(
                playlistURL: videoURL, ctx: ctx, workDir: dir, name: "video", stop: stop, onProgress: report
            ).run()
            async let audio = Self.audioTrack(audioURL, ctx: ctx, dir: dir, stop: stop)
            let (v, a) = try await (video, audio)
            var subtitles: [SubtitleFile] = []
            for (i, s) in subtitleSources.enumerated() {
                item.detail = "Altyazı alınıyor: \(s.name)"
                do {
                    subtitles.append(try await Subtitles.fetch(s, ctx: ctx, into: dir.appendingPathComponent("subs"), index: i))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    continue // a missing subtitle should not fail the video
                }
            }
            item.state = .muxing
            item.detail = "MP4 hazırlanıyor…"
            return try await Muxer.finish(video: v, audio: a, subtitles: subtitles, title: item.title)
        case .subtitle(let source):
            let f = try await Subtitles.fetch(source, ctx: ctx, into: dir, index: 0)
            let ext = f.file.pathExtension.lowercased()
            if ext == "vtt" {
                let out = Output.unique(item.title, ext: "srt")
                try Subtitles.vttToSRT(Subtitles.decode(try Data(contentsOf: f.file))).write(to: out, atomically: true, encoding: .utf8)
                return out
            }
            let out = Output.unique(item.title, ext: ext)
            try FileManager.default.moveItem(at: f.file, to: out)
            return out
        case .file(let url, let ext):
            let file = try await FileDownloader(url: url, ctx: ctx, workDir: dir) { [weak item] done, total in
                Task { @MainActor in item?.apply(bytes: done, total: total) }
            }.run()
            let out = Output.unique(item.title, ext: ext)
            try FileManager.default.moveItem(at: file, to: out)
            return out
        }
    }

    private nonisolated static func audioTrack(_ url: URL?, ctx: HTTPContext, dir: URL, stop: StopFlag) async throws -> URL? {
        guard let url else { return nil }
        return try await HLSTrackDownloader(
            playlistURL: url, ctx: ctx, workDir: dir, name: "audio", stop: stop, onProgress: { _ in }
        ).run()
    }

    func pause(_ item: DownloadItem) { item.task?.cancel() }

    func resumeAll() {
        for item in downloads where item.state == .paused || { if case .failed = item.state { return true }; return false }() {
            start(item)
        }
    }

    func finishLive(_ item: DownloadItem) {
        item.stop.stop()
        item.detail = "Kayıt bitiriliyor…"
    }

    func remove(_ item: DownloadItem) {
        item.task?.cancel()
        downloads.removeAll { $0.id == item.id }
        saveDownloads()
        let dir = item.workDir
        Task.detached { try? FileManager.default.removeItem(at: dir) }
    }
}

enum Storage {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Yakala")
    }
    static var jobs: URL { root.appendingPathComponent("Jobs") }
    static var downloadsFile: URL { root.appendingPathComponent("downloads.json") }
}

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
