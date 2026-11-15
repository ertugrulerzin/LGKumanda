import Foundation
import Darwin

struct LocalSubnet: Equatable {
    let address: String
    let mask: String

    static func number(_ value: String) -> UInt32? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(byte)
        }
        return result
    }
    static func string(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> $0) & 255) }.joined(separator: ".")
    }
    func contains(_ host: String) -> Bool {
        guard let own = Self.number(address), let candidate = Self.number(host), let bits = Self.number(mask) else { return false }
        return TVProtocol.validHost(host) && own & bits == candidate & bits
    }
    var scanHosts: [String] {
        guard TVProtocol.validHost(address), let own = Self.number(address), let bits = Self.number(mask), bits != 0 else { return [] }
        let inverse = ~bits
        guard inverse & (inverse &+ 1) == 0 else { return [] }
        let network = own & bits
        let broadcast = network | inverse
        // Bound large networks to the phone's current /24 window, never the internet.
        let lower = max(network, own & 0xffffff00)
        let upper = min(broadcast, lower | 255)
        guard lower < upper else { return [] }
        return (lower...upper).filter { $0 != own && $0 != network && $0 != broadcast }.map(Self.string)
    }
    static func wifi() -> [LocalSubnet] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        var found: [LocalSubnet] = []
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            let item = entry.pointee
            let name = String(cString: item.ifa_name)
            guard name == "en0" || name == "en1", item.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = item.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = item.ifa_netmask else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let subnet = LocalSubnet(address: Self.string(ip), mask: Self.string(netmask))
            if TVProtocol.validHost(subnet.address) { found.append(subnet) }
        }
        return found
    }
}
