import XCTest

/// End-to-end: ffmpeg makes an AES-128 encrypted HLS stream and a large MP4, a local
/// Range-capable server serves them, and the real downloaders fetch them back.
final class DownloadIntegrationTests: XCTestCase {
    var root: URL!
    var server: Process!
    var port = 0
    var ffmpeg: URL!

    override func setUpWithError() throws {
        guard let ff = Muxer.ffmpegURL() else { throw XCTSkip("ffmpeg yok") }
        ffmpeg = ff
        root = FileManager.default.temporaryDirectory.appendingPathComponent("yakala-it-\(UUID().uuidString)")
        let site = root.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        port = Int.random(in: 20000...40000)

        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        try key.write(to: site.appendingPathComponent("enc.key"))
        let keyInfo = "http://127.0.0.1:\(port)/enc.key\n\(site.appendingPathComponent("enc.key").path)\n"
        try keyInfo.write(to: root.appendingPathComponent("keyinfo"), atomically: true, encoding: .utf8)

        try sh(ffmpeg, [
            "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=duration=8:size=320x240:rate=25",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=8",
            "-c:v", "libx264", "-g", "50", "-c:a", "aac", "-shortest",
            "-hls_time", "2", "-hls_playlist_type", "vod",
            "-hls_key_info_file", root.appendingPathComponent("keyinfo").path,
            "-hls_segment_filename", site.appendingPathComponent("seg%03d.ts").path,
            site.appendingPathComponent("index.m3u8").path,
        ])
        try sh(ffmpeg, [
            "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc2=duration=20:size=1280x720:rate=30",
            "-c:v", "libx264", "-preset", "ultrafast", "-b:v", "12M",
            site.appendingPathComponent("big.mp4").path,
        ])

        server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("range_server.py")
        server.arguments = ["python3", script.path, site.path, String(port)]
        try server.run()
        for _ in 0..<50 {
            if (try? Data(contentsOf: URL(string: "http://127.0.0.1:\(port)/index.m3u8")!)) != nil { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("test sunucusu açılmadı")
    }

    override func tearDown() {
        server?.terminate()
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testEncryptedHLSBecomesPlayableMP4() async throws {
        let ctx = HTTPContext(referer: URL(string: "http://127.0.0.1:\(port)/"), userAgent: "YakalaTest")
        let work = root.appendingPathComponent("work")
        let downloader = HLSTrackDownloader(
            playlistURL: URL(string: "http://127.0.0.1:\(port)/index.m3u8")!,
            ctx: ctx, workDir: work, name: "video", stop: StopFlag(), onProgress: { _ in }
        )
        let ts = try await downloader.run()
        let out = try await Muxer.finish(video: ts, audio: nil, title: "hls test", folder: root)
        XCTAssertEqual(out.pathExtension, "mp4")
        let streams = try probe(out)
        XCTAssertTrue(streams.contains("codec_type=video"), streams)
        XCTAssertTrue(streams.contains("codec_type=audio"), streams)
        let duration = try durationOf(out)
        XCTAssertEqual(duration, 8, accuracy: 0.6)

        // Resume path: segments are cached, a second run gives the same bytes.
        let again = try await downloader.run()
        XCTAssertEqual(try Data(contentsOf: again).count, try Data(contentsOf: ts).count)
    }

    func testChunkedFileDownloadMatchesSource() async throws {
        let source = root.appendingPathComponent("site/big.mp4")
        let size = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as! Int64
        let url = URL(string: "http://127.0.0.1:\(port)/big.mp4")!
        let probe = try await FileDownloader.probe(url, ctx: HTTPContext())
        XCTAssertEqual(probe.size, size)
        XCTAssertTrue(probe.acceptsRanges)

        var dl = FileDownloader(url: url, ctx: HTTPContext(), workDir: root.appendingPathComponent("fwork"), onProgress: { _, _ in })
        dl.chunkSize = 1 << 20
        XCTAssertGreaterThan(size, dl.chunkSize * 2, "test file must take the chunked path")
        let file = try await dl.run()
        XCTAssertEqual(try Data(contentsOf: file), try Data(contentsOf: source))
    }

    // MARK: helpers

    @discardableResult
    private func sh(_ exe: URL, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw NSError(domain: "sh", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: out]) }
        return out
    }

    private var ffprobe: URL { ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe") }

    private func probe(_ file: URL) throws -> String {
        try sh(ffprobe, ["-v", "error", "-show_entries", "stream=codec_type", "-of", "default=nw=1", file.path])
    }

    private func durationOf(_ file: URL) throws -> Double {
        Double(try sh(ffprobe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file.path])
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}
