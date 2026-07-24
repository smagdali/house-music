import Foundation

/// Stable identifier for a MusicCast device: its YXC device_id (MAC-derived),
/// never its IP address, which is DHCP-assigned.
public typealias DeviceID = String

public struct Device: Codable, Identifiable, Hashable, Sendable {
    public var id: DeviceID
    public var modelName: String
    public var roomName: String
    public var ipAddress: String
    public var zone: String
    /// Max volume in device units (from getFeatures range_step); min is 0.
    public var volumeMax: Int?

    public init(id: DeviceID, modelName: String, roomName: String, ipAddress: String,
                zone: String = "main", volumeMax: Int? = nil) {
        self.id = id
        self.modelName = modelName
        self.roomName = roomName
        self.ipAddress = ipAddress
        self.zone = zone
        self.volumeMax = volumeMax
    }

    public var volumeRange: ClosedRange<Int> { 0...(volumeMax ?? 100) }
}

public struct InputChoice: Codable, Hashable, Sendable {
    public var id: String      // YXC input id, e.g. "audio4"
    public var label: String   // user-visible name from the device, e.g. "Decks"

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// A source the user can play: a specific input on a specific device.
/// For multi-room presets the source device becomes the MusicCast Link server.
public struct SourceRef: Codable, Hashable, Sendable {
    public var deviceID: DeviceID
    public var inputID: String
    public var label: String
    public var colorHex: String

    public init(deviceID: DeviceID, inputID: String, label: String, colorHex: String) {
        self.deviceID = deviceID
        self.inputID = inputID
        self.label = label
        self.colorHex = colorHex
    }

    public var isSpotify: Bool { inputID == "spotify" }
}

public struct Preset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// nil source = "All off"
    public var source: SourceRef?
    /// Device IDs that play this preset. Empty for "All off".
    public var rooms: [DeviceID]
    /// Per-room volume baseline in device volume units.
    public var baselines: [DeviceID: Int]
    public var pureDirect: Bool

    public init(id: UUID = UUID(), name: String, source: SourceRef?, rooms: [DeviceID],
                baselines: [DeviceID: Int] = [:], pureDirect: Bool = false) {
        self.id = id
        self.name = name
        self.source = source
        self.rooms = rooms
        self.baselines = baselines
        self.pureDirect = pureDirect
    }

    public var isAllOff: Bool { source == nil && rooms.isEmpty }
}

/// Household configuration: shared between family members via CloudKit.
/// Personal preset ordering deliberately lives outside this struct.
public struct HouseConfig: Codable, Sendable, Equatable {
    public var devices: [Device]
    /// Curated inputs per device (everything else stays hidden).
    public var curatedInputs: [DeviceID: [InputChoice]]
    public var presets: [Preset]

    public init(devices: [Device] = [], curatedInputs: [DeviceID: [InputChoice]] = [:], presets: [Preset] = []) {
        self.devices = devices
        self.curatedInputs = curatedInputs
        self.presets = presets
    }

    public func device(_ id: DeviceID) -> Device? {
        devices.first { $0.id == id }
    }
}

public enum HouseMusicError: Error, LocalizedError {
    case deviceUnreachable(String)
    case yxcError(code: Int, endpoint: String)
    case notConfigured(String)

    public var errorDescription: String? {
        switch self {
        case .deviceUnreachable(let host): return "Device \(host) is unreachable."
        case .yxcError(let code, let endpoint): return "\(endpoint) failed with response_code \(code)."
        case .notConfigured(let what): return "\(what) is not configured."
        }
    }
}
