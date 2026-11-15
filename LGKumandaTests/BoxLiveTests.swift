import XCTest
@testable import LGKumanda

/// Opt-in: pairs with a real Android TV box and sends DOWN then UP.
/// The pairing code shown on the box is read from LG_BOX_CODE_FILE (written by the person watching the TV).
final class BoxLiveTests: XCTestCase {
    @MainActor func testPairAndSendKeys() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["LG_BOX_HOST"], let codeFile = env["LG_BOX_CODE_FILE"] else { throw XCTSkip("Opt-in") }
        let box = BoxClient()
        if box.box?.host != host || box.box?.paired != true {
            await box.startPairing(host: host, name: "Tivibu AndroidTV", inputID: "HDMI_3")
            let started = Date().addingTimeInterval(15)
            while box.pairing != .waitingForCode && Date() < started {
                if case .failed(let reason) = box.pairing { XCTFail(reason); return }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTAssertEqual(box.pairing, .waitingForCode)
            print("BOX_LIVE waiting for code")
            var code = ""
            let deadline = Date().addingTimeInterval(300)
            while Date() < deadline {
                if let text = try? String(contentsOfFile: codeFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), text.count == 6 { code = text; break }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            box.finishPairing(code: code)
            XCTAssertNil(box.pairingCodeError)
            let paired = Date().addingTimeInterval(15)
            while box.pairing != .done && Date() < paired {
                if case .failed(let reason) = box.pairing { XCTFail(reason); return }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTAssertEqual(box.pairing, .done)
        }
        let t0 = Date()
        let connected = await box.connect()
        XCTAssertTrue(connected, box.statusText)
        print("BOX_LIVE connected in", Date().timeIntervalSince(t0), "model", box.deviceModel, "app", box.currentApp)
        XCTAssertTrue(box.send(.down)); try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertTrue(box.send(.up)); try await Task.sleep(nanoseconds: 1_500_000_000)
        box.disconnect()
    }
}
