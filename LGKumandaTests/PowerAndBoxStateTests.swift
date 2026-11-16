import XCTest
@testable import LGKumanda

final class PowerAndBoxStateTests: XCTestCase {
    func testConfirmedStandbyDiffersFromScreenOffAndUnknownNetworkState() {
        for state in ["Active Standby", "Suspend", "Power Off"] {
            XCTAssertEqual(TVPowerState.read(["state": state]), .standby)
        }
        XCTAssertEqual(TVPowerState.read(["state": "Active"]), .active)
        XCTAssertEqual(TVPowerState.read(["state": "Screen Off"]), .screenOff)
        XCTAssertEqual(TVPowerState.read(["state": "Screen Saver"]), .screenSaver)
        XCTAssertFalse(TVPowerState.read(["state": "Screen Off"]).isStandby)
        XCTAssertEqual(TVPowerState.read(["state": "Active Standby", "processing": "startup"]), .unknown)
        XCTAssertEqual(TVPowerState.read(["state": "Active Standby", "processing": ""]), .standby)
        XCTAssertEqual(TVPowerState.read(["errorText": "offline"]), .unknown)
        XCTAssertEqual(TVPowerState.read(["state": "new firmware state"]), .unknown)
    }
    @MainActor func testPowerEventClearsTransportAndExposesTheWakeActionStatus() throws {
        let suite = "LGPowerTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let client = TVClient(preferences: preferences)
        client.updatePowerState(["state": "Suspend"])
        XCTAssertEqual(client.powerState, .standby)
        XCTAssertEqual(client.state, .disconnected)
        XCTAssertEqual(client.connectionLabel, "TV kapalı")
        XCTAssertFalse(client.pointerReady)
        XCTAssertTrue(client.apps.isEmpty)
        XCTAssertNil(client.error)
        client.updatePowerState(["state": "unknown"])
        XCTAssertEqual(client.powerState, .standby, "An empty/unsupported power response cannot invent a power-on event")
        client.disconnect()
        XCTAssertEqual(client.powerState, .unknown, "A transport disconnect alone cannot assert the TV is off")
    }
    func testBoxWaitsForRemoteStartAndEchoesOnlyNegotiatedFeatures() throws {
        var session = BoxRemoteSession()
        var configure = ProtoWriter()
        configure.message(1) { c in
            c.varint(1, 3)
            c.message(2) { $0.string(1, "Tivibu test box") }
        }
        let configureReply = try XCTUnwrap(ProtoMessage(session.receive(configure.data)))
        XCTAssertEqual(configureReply.message(1)?.int(1), 3)
        XCTAssertEqual(session.model, "Tivibu test box")
        XCTAssertFalse(session.ready)
        var activate = ProtoWriter(); activate.message(2) { $0.varint(1, 3) }
        let activateReply = try XCTUnwrap(ProtoMessage(session.receive(activate.data)))
        XCTAssertEqual(activateReply.message(2)?.int(1), 3, "Do not re-advertise features the box rejected")
        XCTAssertFalse(session.ready, "SetActive is followed by RemoteStart; keys before it can be ignored")
        var start = ProtoWriter(); start.message(40) { $0.bool(1, true) }
        XCTAssertTrue(session.receive(start.data).isEmpty)
        XCTAssertTrue(session.ready)
        XCTAssertEqual(session.isOn, true)
    }
    func testBoxStandbyAndPingRemainSeparateFromSessionReadiness() throws {
        var session = BoxRemoteSession()
        var start = ProtoWriter(); start.message(40) { _ in }
        _ = session.receive(start.data)
        XCTAssertTrue(session.ready)
        XCTAssertEqual(session.isOn, false)
        var ping = ProtoWriter(); ping.message(8) { $0.varint(1, 42) }
        let pong = try XCTUnwrap(ProtoMessage(session.receive(ping.data)))
        XCTAssertEqual(pong.message(9)?.int(1), 42)
        var noKeys = ProtoWriter(); noKeys.message(1) { $0.varint(1, 1) }
        _ = session.receive(noKeys.data)
        XCTAssertFalse(session.supportsKeys)
        XCTAssertFalse(session.ready)
    }
}
