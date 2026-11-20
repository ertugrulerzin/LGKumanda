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
struct HTTPContext: Sendable {
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

    static func data(_ request: URLRequest, retries: Int = 3) async throws -> Data {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                if let h = response as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
                    throw DownloadError.http(h.statusCode)
                }
                return data
            } catch {
                if isCancellation(error) { throw CancellationError() }
                if case DownloadError.http(let code) = error, (400..<500).contains(code), code != 408, code != 429 {
                    throw error
                }
                attempt += 1
                if attempt > retries { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
            }
        }
    }

    static func text(_ request: URLRequest) async throws -> String {
        String(decoding: try await data(request), as: UTF8.self)
    }
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
