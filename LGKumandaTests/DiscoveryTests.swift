import XCTest
@testable import LGKumanda

final class LocalSubnetTests: XCTestCase {
    func testWiFiSubnetNeverIncludesSelfNetworkOrBroadcast() {
        let subnet = LocalSubnet(address: "192.168.1.111", mask: "255.255.255.0")
        let hosts = subnet.scanHosts
        XCTAssertEqual(hosts.count, 253)
        XCTAssertTrue(hosts.contains("192.168.1.3"))
        for excluded in ["192.168.1.0", "192.168.1.111", "192.168.1.255", "192.168.2.3"] { XCTAssertFalse(hosts.contains(excluded)) }
    }
    func testSmallSubnetUsesItsRealMask() {
        let subnet = LocalSubnet(address: "192.168.1.130", mask: "255.255.255.192")
        XCTAssertEqual(subnet.scanHosts.count, 61)
        XCTAssertTrue(subnet.scanHosts.contains("192.168.1.129"))
        XCTAssertFalse(subnet.scanHosts.contains("192.168.1.127"))
        XCTAssertFalse(subnet.scanHosts.contains("192.168.1.191"))
        XCTAssertFalse(subnet.contains("192.168.1.3"))
    }
    func testLargeNetworkIsBoundedButKnownHostCanBeInSameSubnet() {
        let subnet = LocalSubnet(address: "10.20.30.100", mask: "255.255.0.0")
        XCTAssertLessThanOrEqual(subnet.scanHosts.count, 255)
        XCTAssertTrue(subnet.scanHosts.allSatisfy { $0.hasPrefix("10.20.30.") })
        XCTAssertTrue(subnet.contains("10.20.40.3"))
        XCTAssertFalse(subnet.contains("10.21.30.3"))
    }
    func testInvalidAndPublicNetworksCannotBeScanned() {
        for subnet in [LocalSubnet(address: "8.8.8.8", mask: "255.255.255.0"),
                       LocalSubnet(address: "192.168.1.2", mask: "0.0.0.0"),
                       LocalSubnet(address: "192.168.1.2", mask: "255.0.255.0"),
                       LocalSubnet(address: "192.168.1.2", mask: "255.255.255.255")] {
            XCTAssertTrue(subnet.scanHosts.isEmpty)
        }
    }
}

final class DeviceIdentificationTests: XCTestCase {
    private func xml(manufacturer: String = "LG Electronics", service: String = "urn:lge-com:service:webos-second-screen:1") -> Data {
        Data("<root><device><friendlyName>Salon &amp; TV</friendlyName><manufacturer>\(manufacturer)</manufacturer><serviceList><service><serviceType>\(service)</serviceType></service></serviceList></device></root>".utf8)
    }
    func testRequiresLGManufacturerAndWebOSService() {
        XCTAssertEqual(TVDiscovery.deviceName(from: xml()), "Salon & TV")
        XCTAssertNil(TVDiscovery.deviceName(from: xml(manufacturer: "Other TV")))
        XCTAssertNil(TVDiscovery.deviceName(from: xml(service: "urn:schemas-upnp-org:service:ContentDirectory:1")))
        XCTAssertNil(TVDiscovery.deviceName(from: Data("<html>Router</html>".utf8)))
        XCTAssertNil(TVDiscovery.deviceName(from: Data("<root><device>".utf8)))
    }
    func testPermissionFailureDiffersFromOfflineDevice() {
        let denied = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: ["_NSURLErrorNWPathKey": "unsatisfied (Local network prohibited)"])
        XCTAssertTrue(TVDiscovery.isLocalNetworkDenied(denied))
        XCTAssertFalse(TVDiscovery.isLocalNetworkDenied(URLError(.timedOut)))
        XCTAssertFalse(TVDiscovery.isLocalNetworkDenied(URLError(.cannotConnectToHost)))
    }
    func testDeviceIdentityAllowsOneTVOnTwoNetworkInterfaces() {
        let data = Data("<root><device><friendlyName>LG TV</friendlyName><manufacturer>LG Electronics</manufacturer><UDN>uuid:ONE-TV</UDN><serviceList><service><serviceType>urn:lge-com:service:webos-second-screen:1</serviceType></service></serviceList></device></root>".utf8)
        XCTAssertEqual(TVDiscovery.deviceDescription(from: data)?.identity, "uuid:one-tv")
    }
}
