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

    /// Turns downloaded HLS tracks into one MP4 in `folder`. Without ffmpeg a lone
    /// track is kept as-is (fragmented MP4 plays everywhere; MPEG-TS stays .ts).
    static func finish(video: URL, audio: URL?, title: String, folder: URL = Output.folder) async throws -> URL {
        guard let ffmpeg = ffmpegURL() else {
            guard audio == nil else { throw DownloadError.ffmpegMissing }
            let out = Output.unique(title, ext: video.pathExtension, in: folder)
            try FileManager.default.moveItem(at: video, to: out)
            return out
        }
        let out = Output.unique(title, ext: "mp4", in: folder)
        var args = ["-hide_banner", "-loglevel", "error", "-y", "-i", video.path]
        if let audio {
            args += ["-i", audio.path, "-map", "0:v?", "-map", "1:a?"]
        } else {
            args += ["-map", "0:v?", "-map", "0:a?"]
        }
        args += ["-c", "copy", "-movflags", "+faststart", out.path]
        do {
            try await run(ffmpeg, args)
        } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
        return out
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
