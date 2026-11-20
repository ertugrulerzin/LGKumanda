import WebKit
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

        server = try startServer(port: port)
    }

    var extraServers: [Process] = []

    func startServer(port: Int, throttle: Int = 0) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("range_server.py")
        p.arguments = ["python3", script.path, root.appendingPathComponent("site").path, String(port), String(throttle)]
        try p.run()
        for _ in 0..<50 {
            if (try? Data(contentsOf: URL(string: "http://127.0.0.1:\(port)/index.m3u8")!)) != nil { return p }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("test sunucusu açılmadı")
        return p
    }

    override func tearDown() {
        server?.terminate()
        extraServers.forEach { $0.terminate() }
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

    func testRateLimitedServerStillCompletes() async throws {
        let throttledPort = port + 1
        extraServers.append(try startServer(port: throttledPort, throttle: 8))
        let started = Date()
        let ts = try await HLSTrackDownloader(
            playlistURL: URL(string: "http://127.0.0.1:\(throttledPort)/index.m3u8")!,
            ctx: HTTPContext(), workDir: root.appendingPathComponent("throttled"), name: "video",
            stop: StopFlag(), onProgress: { _ in }
        ).run()
        XCTAssertGreaterThan(try Data(contentsOf: ts).count, 10_000)
        XCTAssertGreaterThanOrEqual(-started.timeIntervalSinceNow, 1, "Retry-After honoured")
        let limit = await HTTP.gate.limit(for: "127.0.0.1")
        XCTAssertLessThan(limit, HostGate.maxPerHost, "parallelism reduced after 429")
    }

    func testSubtitleEmbeddedAndSidecar() async throws {
        let ts = try await HLSTrackDownloader(
            playlistURL: URL(string: "http://127.0.0.1:\(port)/index.m3u8")!,
            ctx: HTTPContext(), workDir: root.appendingPathComponent("subwork"), name: "video",
            stop: StopFlag(), onProgress: { _ in }
        ).run()
        let vtt = root.appendingPathComponent("tr.vtt")
        try "WEBVTT\n\n00:00.500 --> 00:02.000\nMerhaba <b>dünya</b>\n\n00:03.000 --> 00:05.000\nİkinci satır\n"
            .write(to: vtt, atomically: true, encoding: .utf8)
        let out = try await Muxer.finish(
            video: ts, audio: nil,
            subtitles: [SubtitleFile(file: vtt, name: "Türkçe", language: "tr")],
            title: "altyazi", folder: root
        )
        let streams = try probe(out)
        XCTAssertTrue(streams.contains("codec_type=subtitle"), streams)
        let srt = try String(contentsOf: root.appendingPathComponent("altyazi.tr.srt"), encoding: .utf8)
        XCTAssertTrue(srt.hasPrefix("1\n00:00:00,500 --> 00:00:02,000\nMerhaba <b>dünya</b>"), srt)
    }

    func testCancelledHLSResumesFromSavedSegments() async throws {
        let url = URL(string: "http://127.0.0.1:\(port)/index.m3u8")!
        let work = root.appendingPathComponent("resume")
        let task = Task {
            try await HLSTrackDownloader(playlistURL: url, ctx: HTTPContext(), workDir: work, name: "video",
                                         stop: StopFlag(), concurrency: 1, onProgress: { p in
                if p.done == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            }).run()
        }
        let first = await task.result
        XCTAssertThrowsError(try first.get(), "first run was cancelled")
        let saved = try FileManager.default.contentsOfDirectory(atPath: work.path).filter { $0.hasSuffix(".seg") }
        XCTAssertGreaterThanOrEqual(saved.count, 2)

        let resumed = try await HLSTrackDownloader(playlistURL: url, ctx: HTTPContext(), workDir: work, name: "video",
                                                   stop: StopFlag(), onProgress: { _ in }).run()
        let fresh = try await HLSTrackDownloader(playlistURL: url, ctx: HTTPContext(),
                                                 workDir: root.appendingPathComponent("fresh"), name: "video",
                                                 stop: StopFlag(), onProgress: { _ in }).run()
        XCTAssertEqual(try Data(contentsOf: resumed), try Data(contentsOf: fresh))
    }

    /// Recording mode end to end: hls.js plays the local stream through MediaSource in a real
    /// WKWebView, the sniffer copies the appended buffers, and the result is a playable MP4.
    @MainActor
    func testRecordingModeCapturesMediaSource() async throws {
        let html = """
        <!doctype html><video id="v" muted autoplay playsinline></video>
        <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.13/dist/hls.min.js"></script>
        <script>
          if (window.Hls && Hls.isSupported()) {
            const h = new Hls(); h.loadSource('index.m3u8'); h.attachMedia(document.getElementById('v'));
          } else { window.webkit.messageHandlers.yakala.postMessage({ type: 'nohls' }); }
        </script>
        """
        try html.write(to: root.appendingPathComponent("site/player.html"), atomically: true, encoding: .utf8)

        let collector = RecordingCollector(directory: root.appendingPathComponent("rec"))
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(source: Sniffer.recordingFlag, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.addUserScript(WKUserScript(source: Sniffer.source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.add(collector, name: Sniffer.handlerName)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        window.contentView!.addSubview(webView)
        window.orderBack(nil)
        webView.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/player.html")!))

        var lastBytes: Int64 = -1
        var stable = 0
        for _ in 0..<150 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if collector.noHLS { throw XCTSkip("hls.js yüklenemedi") }
            let b = collector.bytes
            stable = (b > 0 && b == lastBytes) ? stable + 1 : 0
            lastBytes = b
            if stable >= 15 { break }
        }
        window.close()
        XCTAssertGreaterThan(collector.bytes, 0, "no MediaSource data captured")
        XCTAssertGreaterThanOrEqual(collector.tracks.count, 1)

        let files = collector.tracks.sorted { $0.isVideo && !$1.isVideo }.map { t -> URL in t.close(); return t.file }
        let out = try await Muxer.combine(tracks: files, title: "kayit", folder: root)
        let streams = try probe(out)
        XCTAssertTrue(streams.contains("codec_type=video"), streams)
        XCTAssertEqual(try durationOf(out), 8, accuracy: 1.0)
    }

    func testDASHSegmentedAndSingleFile() async throws {
        let site = root.appendingPathComponent("site")
        for (dirName, extra) in [("dash", [String]()), ("dash1", ["-single_file", "1"])] {
            let dir = site.appendingPathComponent(dirName)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try sh(ffmpeg, [
                "-hide_banner", "-loglevel", "error",
                "-f", "lavfi", "-i", "testsrc=duration=8:size=320x240:rate=25",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=8",
                "-c:v", "libx264", "-g", "50", "-c:a", "aac", "-shortest",
                "-map", "0:v", "-map", "1:a", "-seg_duration", "2",
            ] + extra + ["-f", "dash", dir.appendingPathComponent("manifest.mpd").path])

            let url = URL(string: "http://127.0.0.1:\(port)/\(dirName)/manifest.mpd")!
            let manifest = try DASHParser.parse(try await HTTP.data(URLRequest(url: url)), url: url)
            let video = try XCTUnwrap(manifest.videos.first, dirName)
            let audio = try XCTUnwrap(manifest.bestAudio, dirName)
            func fetch(_ rep: DASHRepresentation, _ name: String) async throws -> URL {
                let work = root.appendingPathComponent("w-\(dirName)")
                switch rep.plan {
                case .segments(let p):
                    return try await HLSTrackDownloader(playlistURL: url, ctx: HTTPContext(), workDir: work, name: name,
                                                        stop: StopFlag(), fixedPlaylist: p, onProgress: { _ in }).run()
                case .single(let u):
                    return try await FileDownloader(url: u, ctx: HTTPContext(), workDir: work.appendingPathComponent(name),
                                                    onProgress: { _, _ in }).run()
                }
            }
            let out = try await Muxer.finish(video: try await fetch(video, "video"), audio: try await fetch(audio, "audio"),
                                             title: dirName, folder: root)
            let streams = try probe(out)
            XCTAssertTrue(streams.contains("codec_type=video") && streams.contains("codec_type=audio"), "\(dirName): \(streams)")
            XCTAssertEqual(try durationOf(out), 8, accuracy: 0.6, dirName)
        }
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

final class RecordingCollector: NSObject, WKScriptMessageHandler {
    let directory: URL
    var tracks: [RecordedTrack] = []
    var noHLS = false
    var bytes: Int64 { tracks.reduce(0) { $0 + $1.bytes } }

    init(directory: URL) { self.directory = directory }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "nohls": noHLS = true
        case "mse-track":
            if let id = body["track"] as? String, let t = try? RecordedTrack(id: id, mime: body["mime"] as? String ?? "", directory: directory) {
                tracks.append(t)
            }
        case "mse-data":
            guard let id = body["track"] as? String, let seq = body["seq"] as? Int,
                  let t = tracks.first(where: { $0.id == id }) else { return }
            try? t.append(seq: seq, data: Data(base64Encoded: body["data"] as? String ?? "") ?? Data())
        default: break
        }
    }
}
