import Foundation
import Darwin

enum WakeOnLAN {
    enum Failure: LocalizedError {
        case invalidMAC, invalidAddress, socket, send
        var errorDescription: String? {
            switch self {
            case .invalidMAC: return "Geçerli bir MAC adresi gir: AA:BB:CC:DD:EE:FF."
            case .invalidAddress: return "Geçerli bir IPv4 yayın adresi gir."
            case .socket: return "Ağ bağlantısı açılamadı. Yerel ağ iznini kontrol et."
            case .send: return "Uyandırma paketi gönderilemedi. Wi-Fi bağlantını kontrol et."
            }
        }
    }
    static func packet(mac: String) throws -> Data {
        let parts = mac.replacingOccurrences(of: "-", with: ":").split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 }),
              parts.compactMap({ UInt8($0, radix: 16) }).count == 6 else { throw Failure.invalidMAC }
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        return Data(Array(repeating: UInt8(255), count: 6) + Array(repeating: bytes, count: 16).flatMap { $0 })
    }
    // getinfo lists both NICs even when only one is in use. Match getStatus to
    // the paired IP rather than saving the first MAC (often the inactive NIC).
    static func networkIdentity(info: [String: Any], status: [String: Any], host: String) -> (mac: String, broadcast: String?)? {
        var candidates: [(mac: String, broadcast: String?)] = []
        for adapter in ["wired", "wifi"] {
            guard let entry = info[adapter + "Info"] as? [String: Any],
                  let mac = entry["macAddress"] as? String, (try? packet(mac: mac)) != nil,
                  !["00:00:00:00:00:00", "FF:FF:FF:FF:FF:FF"].contains(mac.uppercased().replacingOccurrences(of: "-", with: ":")) else { continue }
            let network = status[adapter] as? [String: Any] ?? [:]
            let broadcast = (network["netmask"] as? String).flatMap { LocalSubnet(address: host, mask: $0).broadcast }
            if network["ipAddress"] as? String == host, network["state"] as? String == "connected" {
                return (mac.uppercased().replacingOccurrences(of: "-", with: ":"), broadcast)
            }
            candidates.append((mac.uppercased().replacingOccurrences(of: "-", with: ":"), nil))
        }
        // Older firmware may expose only a single network interface.
        return candidates.count == 1 && status.isEmpty ? candidates[0] : nil
    }
    static func targets(host: String, broadcast: String, subnets: [LocalSubnet]) throws -> [String] {
        guard TVProtocol.validHost(host), LocalSubnet.number(broadcast) != nil,
              broadcast == "255.255.255.255" || TVProtocol.validHost(broadcast) else { throw Failure.invalidAddress }
        let addresses = [host] + subnets.filter { $0.contains(host) }.compactMap(\.broadcast) + [broadcast]
        return addresses.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
    static func send(mac: String, host: String, broadcast: String) async throws {
        let data = try packet(mac: mac)
        let destinations = try targets(host: host, broadcast: broadcast, subnets: LocalSubnet.wifi())
        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw Failure.socket }
        defer { Darwin.close(descriptor) }
        var enabled: Int32 = 1
        // An iPhone without the multicast entitlement can still send unicast.
        _ = setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled)))
        var delivered = false
        for attempt in 0..<3 {
            try Task.checkCancellation()
            for target in destinations {
                for port: UInt16 in [9, 7] {
                    var address = sockaddr_in()
                    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                    address.sin_family = sa_family_t(AF_INET)
                    address.sin_port = port.bigEndian
                    guard inet_pton(AF_INET, target, &address.sin_addr) == 1 else { continue }
                    let sent = data.withUnsafeBytes { bytes in
                        withUnsafePointer(to: &address) { pointer in
                            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                                Darwin.sendto(descriptor, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                    delivered = delivered || sent == data.count
                }
            }
            if attempt < 2 { try await Task.sleep(for: .milliseconds(300)) }
        }
        guard delivered else { throw Failure.send }
    }
}
