import XCTest
@testable import LGKumanda

final class HDMIDiagnosticTests: XCTestCase {
    @MainActor func testHDMIDiagnostics() async throws {
        guard ProcessInfo.processInfo.environment["LG_HDMI_DIAG"] == "1" else { throw XCTSkip("Opt-in diagnostics") }
        let out = ProcessInfo.processInfo.environment["LG_DIAG_OUT"] ?? NSTemporaryDirectory()
        let client = TVClient()
        let tv = try XCTUnwrap(client.selected)
        client.connect(to: tv)
        defer { client.disconnect() }
        let by = Date().addingTimeInterval(15)
        while (client.state != .connected || !client.pointerReady) && Date() < by { try await Task.sleep(nanoseconds: 100_000_000) }
        var report: [String: Any] = [:]
        func ask(_ name: String, _ uri: String, _ payload: [String: Any] = [:]) async {
            do { report[name] = try await client.request(uri, payload) } catch { report[name] = "ERR \(error.localizedDescription)" }
        }
        await ask("foreground", "com.webos.applicationManager/getForegroundAppInfo")
        await ask("inputs", "tv/getExternalInputList")
        await ask("settings_option", "settings/getSystemSettings", ["category": "option"])
        await ask("settings_general", "settings/getSystemSettings", ["category": "general"])
        await ask("settings_simplink", "settings/getSystemSettings", ["category": "option", "keys": ["simplink", "simplinkEnable", "hdmiCec", "cecEnable", "simplinkAutoPowerOn"]])
        await ask("sysinfo", "system/getSystemInfo")
        await ask("swinfo", "com.webos.service.update/getCurrentSWInformation")
        let fg = (report["foreground"] as? [String: Any])?["appId"] as? String ?? ""
        if fg.hasPrefix("com.webos.app.hdmi"), ProcessInfo.processInfo.environment["LG_DIAG_KEYS"] == "1" {
            func shot(_ tag: String) async {
                do {
                    let r = try await client.request("tv/executeOneShot")
                    report["shot_\(tag)"] = r
                    if let s = r["imageUri"] as? String, let u = URL(string: s) {
                        let (d, _) = try await URLSession.shared.data(from: u)
                        try d.write(to: URL(fileURLWithPath: out).appendingPathComponent("shot_\(tag).jpg"))
                    }
                } catch { report["shot_\(tag)"] = "ERR \(error.localizedDescription)" }
            }
            await shot("0_before")
            client.key(.down); try await Task.sleep(nanoseconds: 1_500_000_000)
            await shot("1_after_down")
            client.key(.enter); try await Task.sleep(nanoseconds: 1_500_000_000)
            await shot("2_after_ok")
            client.key(.back); try await Task.sleep(nanoseconds: 1_500_000_000)
            await shot("3_after_back")
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        try data.write(to: URL(fileURLWithPath: out).appendingPathComponent("hdmi-diag.json"))
    }
}
