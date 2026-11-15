import XCTest
import Security
@testable import LGKumanda

final class BoxProtocolTests: XCTestCase {
    func testProtobufRoundTripAndFraming() throws {
        var w = ProtoWriter()
        w.varint(1, 2); w.varint(2, 200)
        w.message(10) { $0.string(1, "atvremote"); $0.string(2, "LG Kumanda") }
        w.message(40) { $0.bytes(1, Data([1, 2, 3])) }
        let message = try XCTUnwrap(ProtoMessage(w.data))
        XCTAssertEqual(message.int(1), 2)
        XCTAssertEqual(message.int(2), 200)
        XCTAssertEqual(message.message(10)?.string(2), "LG Kumanda")
        XCTAssertEqual(message.message(40)?.data(1), Data([1, 2, 3]))

        let frame = ProtoWriter.frame(w.data) + ProtoWriter.frame(Data([8, 1]))
        var framer = ProtoFramer()
        XCTAssertTrue(framer.append(frame.prefix(3)).isEmpty, "Partial frames are kept until complete")
        let frames = framer.append(frame.dropFirst(3))
        XCTAssertEqual(frames, [w.data, Data([8, 1])])
        XCTAssertNil(ProtoMessage(Data([0x08])), "Truncated varint is rejected")
    }

    func testPairingSecretMatchesReferenceAndChecksTheCode() throws {
        let client = (modulus: Data(hex: String(repeating: "c0ffee", count: 10))!, exponent: Data([1, 0, 1]))
        let server = (modulus: Data(hex: String(repeating: "beef", count: 12))!, exponent: Data([1, 0, 1]))
        let secret = try XCTUnwrap(BoxCertificate.pairingSecret(code: "710fec", client: client, server: server))
        XCTAssertEqual(secret, Data(hex: "712e735166d8964e455ccf16f43fc9f05658911c3722952588f09b646f3fa98d"))
        XCTAssertNil(BoxCertificate.pairingSecret(code: "720FEC", client: client, server: server), "Checksum mismatch means a typo")
        XCTAssertNil(BoxCertificate.pairingSecret(code: "71FE", client: client, server: server))
        XCTAssertNil(BoxCertificate.pairingSecret(code: "71ZZZZ", client: client, server: server))
    }

    func testGeneratedCertificateIsValidAndKeyNumbersAreMinimal() throws {
        // Uses (or creates) the app's identity without deleting it: a paired box keeps trusting it.
        let certificate = try BoxCertificate.certificate()
        XCTAssertEqual(SecCertificateCopySubjectSummary(certificate) as String?, "atvremote")
        let numbers = try XCTUnwrap(BoxCertificate.rsaNumbers(certificate))
        XCTAssertEqual(numbers.modulus.count, 256, "2048-bit modulus without a sign byte")
        XCTAssertEqual(numbers.exponent, Data([1, 0, 1]))
        XCTAssertNotNil(try? BoxCertificate.identity(), "Identity is found again after creation")
    }

    func testRemoteKeysMapToAndroidKeyCodes() {
        XCTAssertEqual(BoxClient.keyCode(for: .up), 19)
        XCTAssertEqual(BoxClient.keyCode(for: .enter), 23)
        XCTAssertEqual(BoxClient.keyCode(for: .back), 4)
        XCTAssertEqual(BoxClient.keyCode(for: .channelUp), 166)
        XCTAssertEqual(BoxClient.keyCode(for: .five), 12)
        XCTAssertNil(BoxClient.keyCode(for: .dash))
    }

    @MainActor func testBoxOnlyTakesKeysOnItsLinkedInputWhenEnabled() {
        let box = BoxClient()
        let wasEnabled = box.enabled
        defer { box.enabled = wasEnabled }
        let linked = box.box?.inputID.flatMap(ControlRouting.appID(forInput:))
        XCTAssertFalse(box.handles(foregroundAppID: "com.webos.app.hdmi9"), "Other inputs keep TV/CEC control")
        XCTAssertFalse(box.handles(foregroundAppID: "netflix"))
        box.enabled = false
        XCTAssertFalse(box.handles(foregroundAppID: linked), "Turning Wi-Fi control off returns keys to the TV")
        box.enabled = true
        XCTAssertEqual(box.handles(foregroundAppID: linked), box.box?.paired == true && linked != nil)
    }
}
