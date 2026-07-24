import XCTest
@testable import HouseMusicKit

/// Integration tests against the real house. Gated behind HM_LIVE=1 so CI and
/// normal test runs never touch the network. The only writes are a muted
/// volume round-trip on the Office WXA-50, restored to the exact prior state.
final class LiveIntegrationTests: XCTestCase {
    let hosts = [
        "192.168.6.21": "RX-V685",
        "192.168.6.34": "RX-S602",
        "192.168.6.56": "WXA-50",
        "192.168.6.74": "WXA-50",
        "192.168.6.43": "WXA-50",
    ]
    let officeHost = "192.168.6.43"
    let client = YXCClient()

    override func setUp() {
        continueAfterFailure = false
        try? XCTSkipUnless(ProcessInfo.processInfo.environment["HM_LIVE"] == "1", "live tests disabled")
    }

    func testAllDevicesAnswerAndMatchModels() async throws {
        for (host, model) in hosts {
            let info = try await client.deviceInfo(host: host)
            XCTAssertEqual(info.modelName, model, host)
        }
    }

    func testStatusAndFeaturesParseOnAllDevices() async throws {
        for host in hosts.keys {
            let status = try await client.status(host: host)
            XCTAssertTrue(["on", "standby"].contains(status.power), host)
            let features = try await client.features(host: host)
            let main = features.zone.first { $0.id == "main" }
            XCTAssertNotNil(main?.volumeRange, host)
        }
    }

    func testPureDirectOnlyOnAVRs() async throws {
        let living = try await client.features(host: "192.168.6.21")
        XCTAssertTrue(living.zone.first { $0.id == "main" }!.supportsPureDirect)
        let office = try await client.features(host: officeHost)
        XCTAssertFalse(office.zone.first { $0.id == "main" }!.supportsPureDirect)
    }

    func testDistributionInfoParses() async throws {
        for host in hosts.keys {
            _ = try await client.distributionInfo(host: host)
        }
    }

    /// Write path: mute the Office, nudge volume one unit and back, restore.
    /// Writes are guarded (code 5) while a device is in standby, so wake the
    /// Office muted for the duration and put it back exactly as found.
    func testOfficeMutedVolumeRoundTrip() async throws {
        let client = self.client
        let host = self.officeHost
        let initial = try await client.status(host: host)

        // Restore the exact initial state even if assertions fail.
        addTeardownBlock {
            try? await client.setVolume(host: host, units: initial.volume)
            try? await client.setMute(host: host, muted: initial.mute)
            if !initial.isOn {
                try? await client.setPower(host: host, on: false)
            }
        }

        if !initial.isOn {
            try await client.setPower(host: host, on: true)
            try await Task.sleep(for: .seconds(2))
        }
        let before = try await client.status(host: host)
        try XCTSkipUnless(before.volume > 0, "office volume at zero; nothing safe to nudge")

        // Nudge downward: upward can be clamped by the device's configured
        // max_volume. Mute is asserted after the volume writes because a
        // volume change clears mute on the WXA-50.
        try await client.setVolume(host: host, units: before.volume - 1)
        try await Task.sleep(for: .milliseconds(500))
        let during = try await client.status(host: host)
        XCTAssertEqual(during.volume, before.volume - 1)

        try await client.setVolume(host: host, units: before.volume)
        try await client.setMute(host: host, muted: true)
        try await Task.sleep(for: .milliseconds(500))
        let after = try await client.status(host: host)
        XCTAssertEqual(after.volume, before.volume)
        XCTAssertTrue(after.mute)
    }
}
