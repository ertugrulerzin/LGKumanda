import Foundation

/// A stable device UUID and the saved TLS pin survive DHCP address changes.
/// Names, shared certificates and IP addresses alone never select another device.
enum TVAddressRecovery {
    enum Result: Equatable {
        case found(Television), notFound, ambiguous, permissionDenied, cancelled
    }

    static func resolve(_ saved: Television, fingerprint: String, candidates: [Television], fingerprints: [String: String]) -> Result {
        guard saved.secure, let deviceUUID = saved.deviceUUID, UUID(uuidString: deviceUUID) != nil, fingerprint.count == 64,
              fingerprint.allSatisfy({ $0.isHexDigit }) else { return .notFound }
        let matches = Set(candidates.filter {
            TVProtocol.validHost($0.host) && $0.deviceUUID == deviceUUID && fingerprints[$0.host] == fingerprint
        }.map(\.host))
        guard matches.count <= 1 else { return .ambiguous }
        guard let host = matches.first else { return .notFound }
        var updated = saved
        updated.host = host
        return .found(updated)
    }

    @MainActor static func find(_ saved: Television, fingerprint: String) async -> Result {
        guard !Task.isCancelled else { return .cancelled }
        guard saved.secure, let uuid = saved.deviceUUID, UUID(uuidString: uuid) != nil,
              fingerprint.count == 64, fingerprint.allSatisfy({ $0.isHexDigit }) else { return .notFound }
        let discovery = TVDiscovery()
        await discovery.search(knownHosts: [saved.host], useMulticast: false)
        guard !Task.isCancelled else { return .cancelled }
        if discovery.permissionDenied { return .permissionDenied }
        return resolve(saved, fingerprint: fingerprint, candidates: discovery.found, fingerprints: discovery.fingerprints)
    }
}
