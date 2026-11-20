import Foundation

/// One SourceBuffer's data, written to disk in the order the player appended it.
/// Messages may arrive out of order, so later pieces wait until the gap is filled.
final class RecordedTrack {
    let id: String
    let mime: String
    let file: URL
    private(set) var bytes: Int64 = 0
    private var handle: FileHandle?
    private var nextSeq = 0
    private var pending: [Int: Data] = [:]

    init(id: String, mime: String, directory: URL) throws {
        self.id = id
        self.mime = mime.lowercased()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        file = directory.appendingPathComponent("\(safe).\(Self.fileExtension(for: mime))")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        handle = try FileHandle(forWritingTo: file)
    }

    static func fileExtension(for mime: String) -> String {
        let m = mime.lowercased()
        if m.contains("webm") { return "webm" }
        if m.contains("mp2t") { return "ts" }
        if m.contains("aac") || m.contains("mpeg") && m.hasPrefix("audio") { return "aac" }
        return "mp4"
    }

    var isVideo: Bool { mime.hasPrefix("video") }

    func append(seq: Int, data: Data) throws {
        pending[seq] = data
        while let next = pending.removeValue(forKey: nextSeq) {
            if !next.isEmpty {
                try handle?.write(contentsOf: next)
                bytes += Int64(next.count)
            }
            nextSeq += 1
        }
    }

    func close() {
        try? handle?.close()
        handle = nil
    }
}

extension Muxer {
    /// Joins recorded tracks (usually one video + one audio) into one file.
    static func combine(tracks: [URL], title: String, folder: URL = Output.folder) async throws -> URL {
        let nonEmpty = tracks.filter { ((try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0 }
        guard !nonEmpty.isEmpty else { throw DownloadError.empty }
        let allWebM = nonEmpty.allSatisfy { $0.pathExtension == "webm" }
        guard let ffmpeg = ffmpegURL() else {
            guard nonEmpty.count == 1 else { throw DownloadError.ffmpegMissing }
            let out = Output.unique(title, ext: nonEmpty[0].pathExtension, in: folder)
            try FileManager.default.copyItem(at: nonEmpty[0], to: out)
            return out
        }
        let out = Output.unique(title, ext: allWebM ? "webm" : "mp4", in: folder)
        var args = ["-hide_banner", "-loglevel", "error", "-y", "-err_detect", "ignore_err"]
        for t in nonEmpty { args += ["-i", t.path] }
        for i in nonEmpty.indices { args += ["-map", "\(i)"] }
        args += ["-c", "copy"]
        if !allWebM { args += ["-movflags", "+faststart"] }
        args.append(out.path)
        do {
            try await run(ffmpeg, args)
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        return out
    }
}
