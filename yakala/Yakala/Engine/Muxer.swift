import Foundation

enum Output {
    static var folder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    static func sanitize(_ title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = title.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-")))
        return cleaned.isEmpty ? "video" : String(cleaned.prefix(120))
    }

    static func unique(_ title: String, ext: String, in folder: URL = Output.folder) -> URL {
        let base = sanitize(title)
        var url = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}

enum Muxer {
    static func ffmpegURL() -> URL? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) { candidates.append(bundled) }
        candidates += ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].map(URL.init(fileURLWithPath:))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Turns downloaded HLS tracks into one MP4 in `folder`. Subtitles are embedded as
    /// soft tracks and also written next to the video as .srt. Without ffmpeg a lone
    /// track is kept as-is (fragmented MP4 plays everywhere; MPEG-TS stays .ts).
    static func finish(video: URL, audio: URL?, subtitles: [SubtitleFile] = [], title: String,
                       folder: URL = Output.folder) async throws -> URL {
        let out: URL
        if let ffmpeg = ffmpegURL() {
            out = Output.unique(title, ext: "mp4", in: folder)
            do {
                try await run(ffmpeg, arguments(video: video, audio: audio, subtitles: subtitles, out: out))
            } catch where !subtitles.isEmpty && !(error is CancellationError) {
                // A subtitle ffmpeg cannot read must not cost the video.
                try await run(ffmpeg, arguments(video: video, audio: audio, subtitles: [], out: out))
            } catch {
                try? FileManager.default.removeItem(at: out)
                throw error
            }
        } else {
            guard audio == nil else { throw DownloadError.ffmpegMissing }
            out = Output.unique(title, ext: video.pathExtension, in: folder)
            try FileManager.default.moveItem(at: video, to: out)
        }
        try writeSidecars(subtitles, next: out)
        return out
    }

    static func arguments(video: URL, audio: URL?, subtitles: [SubtitleFile], out: URL) -> [String] {
        var args = ["-hide_banner", "-loglevel", "error", "-y", "-i", video.path]
        if let audio { args += ["-i", audio.path] }
        let subBase = audio == nil ? 1 : 2
        for sub in subtitles { args += ["-i", sub.file.path] }
        args += ["-map", "0:v?", "-map", audio == nil ? "0:a?" : "1:a?"]
        for i in subtitles.indices { args += ["-map", "\(subBase + i):s?"] }
        args += ["-c", "copy"]
        if !subtitles.isEmpty { args += ["-c:s", "mov_text"] }
        for (i, sub) in subtitles.enumerated() {
            if let lang = Subtitles.iso639_2(sub.language) { args += ["-metadata:s:s:\(i)", "language=\(lang)"] }
            args += ["-metadata:s:s:\(i)", "title=\(sub.name)"]
        }
        args += ["-movflags", "+faststart", out.path]
        return args
    }

    /// "Film.mp4" + Turkish subtitle → "Film.tr.srt"
    static func writeSidecars(_ subtitles: [SubtitleFile], next video: URL) throws {
        let base = video.deletingPathExtension()
        var used = Set<String>()
        for (i, sub) in subtitles.enumerated() {
            var tag = sub.language?.lowercased() ?? (subtitles.count > 1 ? "\(i + 1)" : "")
            if !tag.isEmpty, !used.insert(tag).inserted { tag += "-\(i + 1)" }
            let ext = sub.file.pathExtension.lowercased()
            let name = base.lastPathComponent + (tag.isEmpty ? "" : ".\(tag)")
            let dest = base.deletingLastPathComponent().appendingPathComponent(name)
            if ext == "vtt" {
                let srt = Subtitles.vttToSRT(Subtitles.decode(try Data(contentsOf: sub.file)))
                try srt.write(to: dest.appendingPathExtension("srt"), atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: dest.appendingPathExtension(ext))
                try FileManager.default.copyItem(at: sub.file, to: dest.appendingPathExtension(ext))
            }
        }
    }

    static func run(_ exe: URL, _ args: [String]) async throws {
        let process = Process()
        process.executableURL = exe
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { p in
                    let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    if p.terminationStatus == 0 {
                        c.resume()
                    } else {
                        let line = err.split(separator: "\n").last.map(String.init) ?? "çıkış kodu \(p.terminationStatus)"
                        c.resume(throwing: DownloadError.ffmpeg(line))
                    }
                }
                do { try process.run() } catch { c.resume(throwing: error) }
            }
        } onCancel: {
            process.terminate()
        }
    }
}
