import Foundation
import Observation

/// One MediaSource the page created while recording mode was on.
@MainActor
@Observable
final class Recording: Identifiable {
    enum State: Equatable {
        case recording, saving
        case saved(URL)
        case failed(String)
    }

    let id: String
    var title: String
    let page: URL?
    var state: State = .recording
    var bytes: Int64 = 0
    var drm = false
    var hasVideo = false
    var hasAudio = false

    @ObservationIgnored private var tracks: [String: RecordedTrack] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored let directory: URL

    init(id: String, title: String, page: URL?) {
        self.id = id
        self.title = title
        self.page = page
        directory = Storage.root.appendingPathComponent("Recordings/\(id)")
    }

    func owns(_ track: String) -> Bool { tracks[track] != nil }

    func addTrack(_ id: String, mime: String) {
        guard tracks[id] == nil, let t = try? RecordedTrack(id: id, mime: mime, directory: directory) else { return }
        tracks[id] = t
        order.append(id)
        if t.isVideo { hasVideo = true } else { hasAudio = true }
    }

    func append(_ track: String, seq: Int, data: Data) {
        guard state == .recording, let t = tracks[track] else { return }
        do {
            try t.append(seq: seq, data: data)
            bytes = tracks.values.reduce(0) { $0 + $1.bytes }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var summary: String {
        var parts: [String] = []
        if hasVideo { parts.append("görüntü") }
        if hasAudio { parts.append("ses") }
        return parts.joined(separator: " + ") + " · " + Format.bytes(bytes)
    }

    func save() {
        guard state == .recording else { return }
        state = .saving
        let files = order.compactMap { tracks[$0] }
            .sorted { $0.isVideo && !$1.isVideo }
            .map { t -> URL in t.close(); return t.file }
        let title = title
        let dir = directory
        Task {
            do {
                let out = try await Muxer.combine(tracks: files, title: title)
                state = .saved(out)
                try? FileManager.default.removeItem(at: dir)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func discard() {
        tracks.values.forEach { $0.close() }
        try? FileManager.default.removeItem(at: directory)
    }
}
