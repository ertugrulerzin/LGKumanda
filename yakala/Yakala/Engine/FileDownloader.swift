import Foundation

/// Downloads a plain media file (MP4, WebM, FLV…). Large files on servers that honour
/// Range requests are fetched as parallel 8 MB chunks that survive a pause.
struct FileDownloader {
    let url: URL
    let ctx: HTTPContext
    let workDir: URL
    var chunkSize: Int64 = 8 << 20
    var concurrency = 4
    let onProgress: @Sendable (Int64, Int64?) -> Void

    struct Probe: Sendable {
        var size: Int64?
        var acceptsRanges: Bool
        var contentType: String?
    }

    static func probe(_ url: URL, ctx: HTTPContext) async throws -> Probe {
        let (bytes, response) = try await HTTP.session.bytes(for: ctx.request(url, range: HLSByteRange(length: 1, offset: 0)))
        bytes.task.cancel()
        guard let h = response as? HTTPURLResponse else { return Probe(size: nil, acceptsRanges: false) }
        guard (200..<300).contains(h.statusCode) else { throw DownloadError.http(h.statusCode) }
        let type = h.value(forHTTPHeaderField: "Content-Type")
        if h.statusCode == 206,
           let total = h.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap({ Int64($0) }) {
            return Probe(size: total, acceptsRanges: true, contentType: type)
        }
        let len = h.expectedContentLength
        return Probe(size: len > 0 ? len : nil, acceptsRanges: false, contentType: type)
    }

    func run() async throws -> URL {
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let out = workDir.appendingPathComponent("file.bin")
        let probe = try await Self.probe(url, ctx: ctx)
        if let size = probe.size, probe.acceptsRanges, size > chunkSize * 2 {
            try await chunked(size: size, to: out)
        } else {
            try await SingleDownload(dest: out, onProgress: onProgress).run(ctx.request(url))
        }
        return out
    }

    private func chunked(size: Int64, to out: URL) async throws {
        let count = Int((size + chunkSize - 1) / chunkSize)
        func file(_ i: Int) -> URL { workDir.appendingPathComponent("chunk-\(i)") }
        func length(_ i: Int) -> Int64 { min(chunkSize, size - Int64(i) * chunkSize) }
        func existing(_ i: Int) -> Int64? {
            (try? FileManager.default.attributesOfItem(atPath: file(i).path))?[.size] as? Int64
        }

        var done: Int64 = 0
        var pending: [Int] = []
        for i in 0..<count {
            if existing(i) == length(i) { done += length(i) } else { pending.append(i) }
        }
        onProgress(done, size)

        try await withThrowingTaskGroup(of: Int64.self) { group in
            var queue = pending.makeIterator()
            let fetch: @Sendable (Int) async throws -> Int64 = { i in
                let range = HLSByteRange(length: Int(length(i)), offset: Int(Int64(i) * chunkSize))
                let data = try await HTTP.data(ctx.request(url, range: range))
                guard Int64(data.count) == length(i) else { throw DownloadError.sizeMismatch }
                let part = file(i).appendingPathExtension("part")
                try data.write(to: part)
                try? FileManager.default.removeItem(at: file(i))
                try FileManager.default.moveItem(at: part, to: file(i))
                return Int64(data.count)
            }
            for _ in 0..<concurrency {
                if let i = queue.next() { group.addTask { try await fetch(i) } }
            }
            while let n = try await group.next() {
                done += n
                onProgress(done, size)
                if let i = queue.next() { group.addTask { try await fetch(i) } }
            }
        }

        FileManager.default.createFile(atPath: out.path, contents: nil)
        let handle = try FileHandle(forWritingTo: out)
        defer { try? handle.close() }
        for i in 0..<count { try handle.write(contentsOf: try Data(contentsOf: file(i))) }
    }
}

/// One URLSession download task with byte progress, wrapped for async/await.
final class SingleDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let dest: URL
    private let onProgress: @Sendable (Int64, Int64?) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var finishError: Error?

    init(dest: URL, onProgress: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.dest = dest
        self.onProgress = onProgress
    }

    func run(_ request: URLRequest) async throws {
        let session = URLSession(configuration: HTTP.configuration(), delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                continuation = c
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let h = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            finishError = DownloadError.http(h.statusCode)
            return
        }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            finishError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let c = continuation
        continuation = nil
        if let error {
            c?.resume(throwing: HTTP.isCancellation(error) ? CancellationError() : error)
        } else if let finishError {
            c?.resume(throwing: finishError)
        } else {
            c?.resume()
        }
    }
}
