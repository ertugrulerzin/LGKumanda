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
    static func send(mac: String, broadcast: String) throws {
        let data = try packet(mac: mac)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(9).bigEndian
        guard inet_pton(AF_INET, broadcast, &address.sin_addr) == 1 else { throw Failure.invalidAddress }
        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw Failure.socket }
        defer { Darwin.close(descriptor) }
        var enabled: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))) == 0 else { throw Failure.socket }
        let sent = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.sendto(descriptor, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == data.count else { throw Failure.send }
    }
}
