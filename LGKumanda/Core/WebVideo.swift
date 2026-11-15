import Foundation
import Observation

/// A transient media address observed in the page, never a saved browsing history.
struct WebVideo: Identifiable, Equatable {
    let url: URL
    let title: String
    let mimeType: String
    var id: String { url.absoluteString }
    var format: String { mimeType.contains("mpegurl") ? "HLS" : mimeType.replacingOccurrences(of: "video/", with: "").uppercased() }
    var sourceLabel: String { url.host ?? "Video kaynağı" }

    static func parse(_ value: [String: Any]) -> WebVideo? {
        guard let address = value["url"] as? String, address.utf8.count <= 8192,
              address.rangeOfCharacter(from: .controlCharacters) == nil,
              let parts = URLComponents(string: address),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, parts.user == nil, parts.password == nil,
              let url = parts.url else { return nil }
        let supplied = (value["mime"] as? String ?? "").lowercased().components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
        let inferred = ["mp4": "video/mp4", "m4v": "video/mp4", "m3u8": "application/vnd.apple.mpegurl", "webm": "video/webm", "mov": "video/quicktime"][url.pathExtension.lowercased()]
        let allowed = ["video/mp4", "video/webm", "video/quicktime", "application/vnd.apple.mpegurl", "application/x-mpegurl"]
        guard let mime = allowed.contains(supplied) ? supplied : inferred else { return nil }
        let text = (value["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return WebVideo(url: url, title: text.isEmpty ? "Web videosu" : String(text.prefix(160)), mimeType: mime)
    }

    var openPayload: [String: Any] {
        ["target": url.absoluteString, "title": title, "mimeType": mimeType, "loop": false]
    }
}

@MainActor @Observable final class WebVideoCatalog {
    private(set) var videos: [WebVideo] = []
    func receive(_ body: Any) {
        guard let value = body as? [String: Any], let item = WebVideo.parse(value) else { return }
        if let index = videos.firstIndex(where: { $0.id == item.id }) { videos[index] = item }
        else if videos.count < 32 { videos.append(item) }
    }
    func reset() { videos = [] }
}

struct WebVideoSession {
    let video: WebVideo
    let viewerID: String?
    let sessionID: String?
}

enum WebVideoDiscovery {
    /// Passive DOM/resource observation, including iframe documents. No fetch/XHR monkey-patching.
    static let script = """
    (function () {
      var sent = new Set(), timer = null;
      function report(raw, mime, title) {
        try {
          var u = new URL(raw, document.baseURI);
          if (u.protocol !== 'https:' && u.protocol !== 'http:') return;
          if (u.username || u.password || sent.has(u.href) || sent.size >= 64) return;
          if (!mime && !/\\.(mp4|m4v|m3u8|webm|mov)$/i.test(u.pathname)) return;
          sent.add(u.href);
          window.webkit.messageHandlers.videoSource.postMessage({url:u.href, mime:mime || '', title:title || document.title || 'Web videosu'});
        } catch (_) {}
      }
      function scan() {
        timer = null;
        document.querySelectorAll('video').forEach(function(v) {
          var name = v.getAttribute('aria-label') || v.title || document.title;
          if (v.currentSrc) report(v.currentSrc, v.getAttribute('type'), name);
          if (v.src) report(v.src, v.getAttribute('type'), name);
          v.querySelectorAll('source').forEach(function(s) { report(s.src, s.type, name); });
        });
      }
      function schedule() { if (!timer) timer = setTimeout(scan, 150); }
      document.addEventListener('DOMContentLoaded', scan);
      document.addEventListener('loadedmetadata', schedule, true);
      document.addEventListener('loadstart', schedule, true);
      new MutationObserver(schedule).observe(document, {subtree:true, childList:true, attributes:true, attributeFilter:['src','type']});
      try {
        new PerformanceObserver(function(list) {
          list.getEntries().forEach(function(e) { if (/\\.m3u8(?:[?]|$)/i.test(e.name)) report(e.name, '', document.title); });
        }).observe({type:'resource', buffered:true});
      } catch (_) {}
      document.addEventListener('play', function(e) {
        var v = e.target;
        if (!v || !v.pause) return;
        scan();
        v.pause(); v.muted = true;
        try { window.webkit.messageHandlers.mediaPlay.postMessage(1); } catch (_) {}
      }, true);
      scan();
    })();
    """
}
