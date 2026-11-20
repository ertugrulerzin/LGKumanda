import CommonCrypto
import Foundation

enum DownloadError: LocalizedError, Equatable {
    case http(Int)
    case drm
    case notPlaylist
    case empty
    case badKey
    case decrypt
    case ffmpegMissing
    case ffmpeg(String)
    case sizeMismatch

    var errorDescription: String? {
        switch self {
        case .http(let code): return "Sunucu \(code) yanıtı verdi."
        case .drm: return "Bu video DRM ile korunuyor; indirilemez."
        case .notPlaylist: return "Adres geçerli bir HLS listesi döndürmedi."
        case .empty: return "İndirilecek parça bulunamadı."
        case .badKey: return "Şifre anahtarı alınamadı."
        case .decrypt: return "Parça çözülemedi."
        case .ffmpegMissing: return "Ayrı ses ve görüntüyü birleştirmek için ffmpeg gerekli (brew install ffmpeg)."
        case .ffmpeg(let msg): return "ffmpeg hatası: \(msg)"
        case .sizeMismatch: return "Sunucu beklenen boyutta veri göndermedi."
        }
    }
}

/// Headers a page's own media requests would carry.
struct HTTPContext: Sendable, Codable {
    var referer: URL?
    var userAgent: String?

    func request(_ url: URL, range: HLSByteRange? = nil) -> URLRequest {
        var r = URLRequest(url: url)
        if let userAgent { r.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let referer {
            r.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
            if let scheme = referer.scheme, let host = referer.host {
                var origin = "\(scheme)://\(host)"
                if let port = referer.port { origin += ":\(port)" }
                r.setValue(origin, forHTTPHeaderField: "Origin")
            }
        }
        if let range {
            r.setValue("bytes=\(range.offset)-\(range.offset + range.length - 1)", forHTTPHeaderField: "Range")
        }
        return r
    }
}

enum HTTP {
    static func configuration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpShouldSetCookies = true
        c.httpMaximumConnectionsPerHost = 8
        c.timeoutIntervalForRequest = 30
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        return c
    }

    static let session = URLSession(configuration: configuration())

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    static let gate = HostGate()

    static func data(_ request: URLRequest, retries: Int = 3) async throws -> Data {
        let host = request.url?.host ?? ""
        var attempt = 0
        var throttled = 0
        while true {
            try Task.checkCancellation()
            try await gate.acquire(host)
            do {
                let (data, response) = try await session.data(for: request)
                if let h = response as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
                    if h.statusCode == 429 || h.statusCode == 503 {
                        let wait = retryAfter(h) ?? min(60, 2 * pow(2, Double(throttled)))
                        await gate.release(host, throttledFor: wait)
                        throttled += 1
                        // Rate limits clear with time; keep waiting rather than failing the download.
                        if throttled > 8 { throw DownloadError.http(h.statusCode) }
                        continue
                    }
                    await gate.release(host)
                    throw DownloadError.http(h.statusCode)
                }
                await gate.release(host, succeeded: true)
                return data
            } catch {
                if case DownloadError.http = error {} else { await gate.release(host) }
                if isCancellation(error) { throw CancellationError() }
                if case DownloadError.http(let code) = error, code != 408 { throw error }
                attempt += 1
                if attempt > retries { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
            }
        }
    }

    /// Retry-After as seconds or an HTTP date.
    static func retryAfter(_ h: HTTPURLResponse) -> Double? {
        guard let v = h.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) else { return nil }
        if let s = Double(v) { return min(max(s, 1), 120) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: v).map { min(max($0.timeIntervalSinceNow, 1), 120) }
    }

    static func text(_ request: URLRequest) async throws -> String {
        String(decoding: try await data(request), as: UTF8.self)
    }
}

/// Per-host connection limit that halves on 429/503, honours the cool-down,
/// and creeps back up after a run of successful requests.
actor HostGate {
    static let maxPerHost = 6

    private struct State {
        var limit = HostGate.maxPerHost
        var inFlight = 0
        var until = Date.distantPast
        var streak = 0
    }

    private var hosts: [String: State] = [:]

    func acquire(_ host: String) async throws {
        while true {
            try Task.checkCancellation()
            let s = hosts[host, default: State()]
            let wait = s.until.timeIntervalSinceNow
            if wait > 0 {
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                continue
            }
            if s.inFlight < s.limit {
                hosts[host, default: State()].inFlight += 1
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func release(_ host: String, succeeded: Bool = false, throttledFor: Double? = nil) {
        var s = hosts[host, default: State()]
        s.inFlight = max(0, s.inFlight - 1)
        if let t = throttledFor {
            s.limit = max(1, s.limit / 2)
            s.until = max(s.until, Date().addingTimeInterval(t))
            s.streak = 0
        } else if succeeded {
            s.streak += 1
            if s.streak >= 20, s.limit < Self.maxPerHost {
                s.limit += 1
                s.streak = 0
            }
        }
        hosts[host] = s
    }

    func limit(for host: String) -> Int { hosts[host]?.limit ?? Self.maxPerHost }
}

enum AES128 {
    static func decrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128 else { throw DownloadError.decrypt }
        var out = Data(count: data.count + kCCBlockSizeAES128)
        let capacity = out.count
        var moved = 0
        let status = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { d in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { v in
                        CCCrypt(
                            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            k.baseAddress, key.count, v.baseAddress,
                            d.baseAddress, data.count, o.baseAddress, capacity, &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw DownloadError.decrypt }
        out.removeSubrange(moved..<out.count)
        return out
    }

    /// HLS default IV: the media sequence number as a 128-bit big-endian integer.
    static func iv(sequence: Int) -> Data {
        var d = Data(count: 16)
        withUnsafeBytes(of: UInt64(sequence).bigEndian) { d.replaceSubrange(8..<16, with: $0) }
        return d
    }
}
