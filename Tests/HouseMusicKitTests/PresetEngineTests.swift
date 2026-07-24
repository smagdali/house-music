import XCTest
@testable import HouseMusicKit

final class PresetEngineTests: XCTestCase {

    // The real house, as discovered on the LAN.
    static let living = Device(id: "BC30D93644DA", modelName: "RX-V685", roomName: "Living Room", ipAddress: "192.168.6.21")
    static let bedroom = Device(id: "4C1B86A6835D", modelName: "RX-S602", roomName: "Master Bedroom", ipAddress: "192.168.6.34")
    static let dining = Device(id: "AC44F24F7404", modelName: "WXA-50", roomName: "Dining Room", ipAddress: "192.168.6.56")
    static let bathroom = Device(id: "00A0DE9868A8", modelName: "WXA-50", roomName: "Bathroom", ipAddress: "192.168.6.74")
    static let office = Device(id: "AC44F24FC12F", modelName: "WXA-50", roomName: "Office", ipAddress: "192.168.6.43")

    static let decks = SourceRef(deviceID: living.id, inputID: "audio4", label: "Decks", colorHex: "F6A83C")

    var config: HouseConfig {
        HouseConfig(devices: [Self.living, Self.bedroom, Self.dining, Self.bathroom, Self.office])
    }

    func testDecksUpstairsPlan() {
        let preset = Preset(name: "Decks Upstairs", source: Self.decks,
                            rooms: [Self.living.id, Self.dining.id],
                            baselines: [Self.living.id: 89, Self.dining.id: 40])
        let plan = PresetEngine.plan(for: preset, config: config)

        XCTAssertEqual(Set(plan.powerOff), [Self.bedroom.id, Self.bathroom.id, Self.office.id])
        XCTAssertEqual(plan.serverDevice, Self.living.id)
        XCTAssertEqual(plan.serverInput, "audio4")
        XCTAssertEqual(plan.clientDevices, [Self.dining.id])
        XCTAssertFalse(plan.pureDirect)
        XCTAssertFalse(plan.dissolveGroup)
    }

    func testDJTimePureDirectOnlyWhenSolo() {
        let solo = Preset(name: "DJ time", source: Self.decks, rooms: [Self.living.id], pureDirect: true)
        XCTAssertTrue(PresetEngine.plan(for: solo, config: config).pureDirect)

        // The constraint: Pure Direct must never combine with multi-room.
        let multi = Preset(name: "bad", source: Self.decks, rooms: [Self.living.id, Self.dining.id], pureDirect: true)
        XCTAssertFalse(PresetEngine.plan(for: multi, config: config).pureDirect)
    }

    func testAllOffPlan() {
        let preset = Preset(name: "All off", source: nil, rooms: [])
        let plan = PresetEngine.plan(for: preset, config: config)
        XCTAssertEqual(Set(plan.powerOff), Set(config.devices.map(\.id)))
        XCTAssertTrue(plan.powerOn.isEmpty)
        XCTAssertTrue(plan.dissolveGroup)
        XCTAssertNil(plan.serverDevice)
    }

    func testSoloPresetDissolvesGroup() {
        let preset = Preset(name: "Telly time",
                            source: SourceRef(deviceID: Self.living.id, inputID: "hdmi1", label: "Apple TV", colorHex: "B9A7FF"),
                            rooms: [Self.living.id])
        let plan = PresetEngine.plan(for: preset, config: config)
        XCTAssertTrue(plan.dissolveGroup)
        XCTAssertTrue(plan.clientDevices.isEmpty)
    }

    func testClampedVolume() {
        XCTAssertEqual(200.clamped(to: 0...161), 161)
        XCTAssertEqual((-5).clamped(to: 0...161), 0)
        XCTAssertEqual(80.clamped(to: 0...161), 80)
    }
}

final class ConfigStoreTests: XCTestCase {
    func testPersonalOrderAppendsUnknownPresets() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = ConfigStore(defaults: defaults)
        let a = Preset(name: "A", source: nil, rooms: [])
        let b = Preset(name: "B", source: nil, rooms: [])
        let c = Preset(name: "C", source: nil, rooms: [])
        let config = HouseConfig(presets: [a, b, c])

        store.saveOrder([c.id, a.id])
        let ordered = store.orderedPresets(config).map(\.name)
        XCTAssertEqual(ordered, ["C", "A", "B"])
    }

    func testConfigRoundTrip() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = ConfigStore(defaults: defaults)
        var config = HouseConfig(devices: [PresetEngineTests.living])
        config.presets = [Preset(name: "DJ time", source: PresetEngineTests.decks,
                                 rooms: [PresetEngineTests.living.id], pureDirect: true)]
        store.saveConfig(config)
        XCTAssertEqual(store.loadConfig(), config)
    }
}

final class SpotifyPKCETests: XCTestCase {
    func testAuthRequestShape() {
        let request = SpotifyClient.makeAuthRequest()
        let comps = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: comps.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["client_id"], SpotifyClient.clientID)
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["redirect_uri"], "housemusic://spotify-callback")
        XCTAssertEqual(request.codeVerifier.count, 64)
        XCTAssertFalse(items["code_challenge"]!.isEmpty)
    }
}

final class YXCClientTests: XCTestCase {
    func testURLBuilding() {
        let client = YXCClient()
        let url = client.url("192.168.6.21", "main/setVolume", ["volume": "89"])
        XCTAssertEqual(url.absoluteString, "http://192.168.6.21/YamahaExtendedControl/v1/main/setVolume?volume=89")
    }

    func testGroupIDGeneration() {
        let id = YXCClient.newGroupID()
        XCTAssertEqual(id.count, 32)
        XCTAssertTrue(id.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
