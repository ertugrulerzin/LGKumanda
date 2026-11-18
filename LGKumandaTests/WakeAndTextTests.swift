import XCTest
@testable import LGKumanda

final class WakeAndTextTests: XCTestCase {
    func testWakeMACFromDIALReply() {
        let reply = "HTTP/1.1 200 OK\r\nST: urn:dial-multiscreen-org:service:dial:1\r\nWAKEUP: MAC=d0:cd:bf:5d:fb:9a;Timeout=60\r\n\r\n"
        XCTAssertEqual(WakeOnLAN.wakeMAC(fromSSDP: reply), "D0:CD:BF:5D:FB:9A")
        XCTAssertNil(WakeOnLAN.wakeMAC(fromSSDP: "HTTP/1.1 200 OK\r\nWAKEUP: MAC=00:00:00:00:00:00;Timeout=60\r\n"))
        XCTAssertNil(WakeOnLAN.wakeMAC(fromSSDP: "HTTP/1.1 200 OK\r\nLOCATION: http://x\r\n"))
    }

    func testBoxRequestsTextAndEchoesIMECounters() throws {
        XCTAssertNotEqual(BoxRemoteSession.requestedFeatures & 4, 0)
        var session = BoxRemoteSession()
        var show = ProtoWriter(); show.message(22) { $0.message(2) { $0.varint(1, 7) } }
        _ = session.receive(show.data)
        var edit = ProtoWriter(); edit.message(21) { $0.varint(1, 3); $0.varint(2, 7) }
        _ = session.receive(edit.data)
        let frame = try XCTUnwrap(ProtoMessage(session.textEdit("ab")))
        let batch = try XCTUnwrap(frame.message(21))
        XCTAssertEqual(batch.int(1), 3)
        XCTAssertEqual(batch.int(2), 7)
        let field = try XCTUnwrap(batch.message(3)?.message(2))
        XCTAssertEqual(field.string(3), "ab")
        XCTAssertEqual(field.int(1), 1)
    }
}
