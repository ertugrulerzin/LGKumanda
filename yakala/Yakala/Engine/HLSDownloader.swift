import Foundation

/// Set by the user to end a live recording; the downloader then finishes what it has.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isStopped: Bool { lock.withLock { stopped } }
    func stop() { lock.withLock { stopped = true } }
}

actor KeyStore {
    private var cache: [URL: Data] = [:]
    private let ctx: HTTPContext

    init(ctx: HTTPContext) { self.ctx = ctx }

    func key(_ url: URL) async throws -> Data {
        if let k = cache[url] { return k }
        let d = try await HTTP.data(ctx.request(url))
        guard d.count == 16 else { throw DownloadError.badKey }
        cache[url] = d
        return d
    }
}

struct HLSProgress: Sendable {
    var done: Int
    var total: Int
    var bytes: Int64
    var seconds: Double
    var live: Bool
}

/// Downloads one HLS media playlist (video or audio) into a single .ts or fragmented .mp4 file.
/// Finished segments stay on disk in `workDir`, so a cancelled run resumes where it stopped.
struct HLSTrackDownloader {
    let playlistURL: URL
    let ctx: HTTPContext
    let workDir: URL
    let name: String
    let stop: StopFlag
    var concurrency = 6
    /// A ready-made segment list (DASH); when set, nothing is fetched from `playlistURL`.
    var fixedPlaylist: HLSMediaPlaylist?
    let onProgress: @Sendable (HLSProgress) -> Void

    func run() async throws -> URL {
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let keys = KeyStore(ctx: ctx)
        var playlist = try await fetchMedia()
        let live = playlist.isLive
        var order: [HLSSegment] = []
        var seen = Set<Int>()
        var earlier: [Int] = []
        if live {
            // Segments recorded before a pause or restart may have left the live window.
            let first = playlist.segments.first?.sequence ?? .max
            earlier = savedSequences().filter { $0 < first }
            earlier.forEach { seen.insert($0) }
        }
        var bytes: Int64 = 0
        var seconds = 0.0

        while true {
            let fresh = playlist.segments.filter { !seen.contains($0.sequence) }
            fresh.forEach { seen.insert($0.sequence) }
            order += fresh
            let total = order.count
            var done = order.count - fresh.count

            if !fresh.isEmpty {
                try await withThrowingTaskGroup(of: (Int64, Double).self) { group in
                    var queue = fresh.makeIterator()
                    for _ in 0..<concurrency {
                        guard let s = queue.next() else { break }
                        group.addTask { (try await fetch(s, keys: keys), s.duration) }
                    }
                    while let (n, d) = try await group.next() {
                        done += 1
                        bytes += n
                        seconds += d
                        onProgress(HLSProgress(done: done, total: total, bytes: bytes, seconds: seconds, live: live))
                        if let s = queue.next() {
                            group.addTask { (try await fetch(s, keys: keys), s.duration) }
                        }
                    }
                }
            }

            if !live || playlist.endList || stop.isStopped { break }
            try await Task.sleep(nanoseconds: UInt64(max(1, playlist.targetDuration / 2) * 1_000_000_000))
            if stop.isStopped { break }
            playlist = try await fetchMedia()
        }

        guard !order.isEmpty || !earlier.isEmpty else { throw DownloadError.empty }
        return try await assemble(earlier + order.map(\.sequence), initSection: playlist.initSection)
    }

    private func fetchMedia() async throws -> HLSMediaPlaylist {
        if let fixedPlaylist { return fixedPlaylist }
        var url = playlistURL
        for _ in 0..<2 {
            let text = try await HTTP.text(ctx.request(url))
            switch try HLSParser.parse(text, baseURL: url) {
            case .media(let m):
                if m.hasDRM { throw DownloadError.drm }
                return m
            case .master(let master):
                guard let best = master.variants.first else { throw DownloadError.empty }
                url = best.url
            }
        }
        throw DownloadError.notPlaylist
    }

    private func segmentFile(_ s: HLSSegment) -> URL { segmentFile(s.sequence) }

    private func segmentFile(_ sequence: Int) -> URL {
        workDir.appendingPathComponent("\(name)-\(sequence).seg")
    }

    private func savedSequences() -> [Int] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: workDir.path)) ?? []
        return files.compactMap { f -> Int? in
            guard f.hasPrefix("\(name)-"), f.hasSuffix(".seg") else { return nil }
            return Int(f.dropFirst(name.count + 1).dropLast(4))
        }.sorted()
    }

    private func fetch(_ s: HLSSegment, keys: KeyStore) async throws -> Int64 {
        let file = segmentFile(s)
        if let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int64, size > 0 {
            return size
        }
        var data = try await HTTP.data(ctx.request(s.url, range: s.byteRange))
        if let key = s.key, key.method == "AES-128", let uri = key.uri {
            let k = try await keys.key(uri)
            data = try AES128.decrypt(data, key: k, iv: key.iv ?? AES128.iv(sequence: s.sequence))
        }
        let part = file.appendingPathExtension("part")
        try data.write(to: part)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: part, to: file)
        return Int64(data.count)
    }

    private func assemble(_ sequences: [Int], initSection: HLSInitSection?) async throws -> URL {
        let out = workDir.appendingPathComponent("\(name).\(initSection == nil ? "ts" : "mp4")")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        let handle = try FileHandle(forWritingTo: out)
        defer { try? handle.close() }
        if let i = initSection {
            try handle.write(contentsOf: try await HTTP.data(ctx.request(i.url, range: i.byteRange)))
        }
        for s in sequences {
            try handle.write(contentsOf: try Data(contentsOf: segmentFile(s)))
        }
        return out
    }
}
