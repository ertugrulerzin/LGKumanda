import Foundation
import Observation

enum MediaKind: Equatable {
    case hls
    case dash
    case file(String)

    static func classify(_ url: URL, hint: String) -> MediaKind? {
        let h = hint.lowercased()
        let ext = url.pathExtension.lowercased()
        let s = url.absoluteString.lowercased()
        if h.contains("mpegurl") || ext == "m3u8" || s.contains(".m3u8") { return .hls }
        if h.contains("dash+xml") || ext == "mpd" { return .dash }
        if ["mp4", "m4v", "webm", "flv", "mov"].contains(ext) { return .file(ext) }
        if h.hasPrefix("video/") { return .file(h.contains("webm") ? "webm" : "mp4") }
        if h == "media" { return .file("mp4") }
        return nil
    }

    var badge: String {
        switch self {
        case .hls: return "HLS"
        case .dash: return "DASH"
        case .file(let ext): return ext.uppercased()
        }
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
        if let duration, duration > 0, !isLive { parts.append(Format.duration(duration)) }
        if let size { parts.append(Format.bytes(size)) }
        return parts.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class DownloadItem: Identifiable {
    enum Source {
        case hls(video: URL, audio: URL?)
        case file(URL, ext: String)
    }

    enum State: Equatable {
        case running, paused, muxing
        case done(URL)
        case failed(String)
    }

    let id = UUID()
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

    init(title: String, source: Source, ctx: HTTPContext, isLive: Bool) {
        self.title = title
        self.source = source
        self.ctx = ctx
        self.isLive = isLive
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent("Yakala/\(id.uuidString)")
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
    }

    var visibleDetected: [DetectedMedia] { detected.filter { !$0.hidden } }

    // MARK: Detection

    func pageChanged() {
        detected.removeAll()
        childURLs.removeAll()
        hlsFolders.removeAll()
    }

    func report(url: URL, hint: String, page: URL?, title: String) {
        guard let kind = MediaKind.classify(url, hint: hint) else { return }
        let key = url.absoluteString
        guard !detected.contains(where: { $0.url.absoluteString == key }) else { return }
        let ctx = HTTPContext(referer: page, userAgent: browser.userAgent)
        let item = DetectedMedia(url: url, kind: kind, ctx: ctx, title: title.isEmpty ? url.lastPathComponent : title)
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
            source = .hls(video: variant?.url ?? media.url, audio: audio)
        case .file(let ext):
            source = .file(media.url, ext: ext)
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
        let browser = browser
        item.task = Task {
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
                } else {
                    item.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func run(_ item: DownloadItem) async throws -> URL {
        let ctx = item.ctx
        let dir = item.workDir
        let stop = item.stop
        switch item.source {
        case .hls(let videoURL, let audioURL):
            let report: @Sendable (HLSProgress) -> Void = { [weak item] p in
                Task { @MainActor in item?.apply(p) }
            }
            async let video = HLSTrackDownloader(
                playlistURL: videoURL, ctx: ctx, workDir: dir, name: "video", stop: stop, onProgress: report
            ).run()
            async let audio = Self.audioTrack(audioURL, ctx: ctx, dir: dir, stop: stop)
            let (v, a) = try await (video, audio)
            item.state = .muxing
            item.detail = "MP4 hazırlanıyor…"
            return try await Muxer.finish(video: v, audio: a, title: item.title)
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

    func finishLive(_ item: DownloadItem) {
        item.stop.stop()
        item.detail = "Kayıt bitiriliyor…"
    }

    func remove(_ item: DownloadItem) {
        item.task?.cancel()
        downloads.removeAll { $0.id == item.id }
        let dir = item.workDir
        Task.detached { try? FileManager.default.removeItem(at: dir) }
    }
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
