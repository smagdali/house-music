import Foundation

/// Subset of Yamaha Extended Control responses the app uses.
/// Every YXC response carries response_code; 0 is success.

public struct YXCResponseCode: Decodable {
    public let responseCode: Int
    enum CodingKeys: String, CodingKey { case responseCode = "response_code" }
}

public struct YXCDeviceInfo: Decodable, Sendable {
    public let responseCode: Int
    public let modelName: String
    public let deviceID: String
    public let systemVersion: Double
    public let apiVersion: Double

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case modelName = "model_name"
        case deviceID = "device_id"
        case systemVersion = "system_version"
        case apiVersion = "api_version"
    }
}

public struct YXCNameText: Decodable, Sendable {
    public struct Entry: Decodable, Sendable {
        public let id: String
        public let text: String
    }
    public let responseCode: Int
    public let zoneList: [Entry]
    public let inputList: [Entry]

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case zoneList = "zone_list"
        case inputList = "input_list"
    }
}

public struct YXCStatus: Decodable, Sendable {
    public struct ActualVolume: Decodable, Sendable {
        public let mode: String
        public let value: Double
    }
    public let responseCode: Int
    public let power: String
    public let volume: Int
    public let maxVolume: Int?
    public let mute: Bool
    public let input: String
    public let pureDirect: Bool?
    public let actualVolume: ActualVolume?

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case power, volume, mute, input
        case maxVolume = "max_volume"
        case pureDirect = "pure_direct"
        case actualVolume = "actual_volume"
    }

    public var isOn: Bool { power == "on" }
}

public struct YXCFeatures: Decodable, Sendable {
    public struct Zone: Decodable, Sendable {
        public struct RangeStep: Decodable, Sendable {
            public let id: String
            public let min: Double
            public let max: Double
            public let step: Double
        }
        public let id: String
        public let funcList: [String]
        public let inputList: [String]
        public let rangeStep: [RangeStep]?

        enum CodingKeys: String, CodingKey {
            case id
            case funcList = "func_list"
            case inputList = "input_list"
            case rangeStep = "range_step"
        }

        public var volumeRange: RangeStep? { rangeStep?.first { $0.id == "volume" } }
        public var volumeMax: Int? { volumeRange.map { Int($0.max) } }
        public var supportsPureDirect: Bool { funcList.contains("pure_direct") }
    }
    public let responseCode: Int
    public let zone: [Zone]

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case zone
    }
}

public struct YXCDistributionInfo: Decodable, Sendable {
    public struct Client: Decodable, Sendable {
        public let ipAddress: String
        enum CodingKeys: String, CodingKey { case ipAddress = "ip_address" }
    }
    public let responseCode: Int
    public let groupID: String
    public let groupName: String?
    public let role: String
    public let status: String?
    public let serverZone: String?
    public let clientList: [Client]?

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case groupID = "group_id"
        case groupName = "group_name"
        case role, status
        case serverZone = "server_zone"
        case clientList = "client_list"
    }

    /// All-zero group id means "not grouped".
    public var isGrouped: Bool {
        !groupID.isEmpty && groupID.contains(where: { $0 != "0" })
    }
}

public struct YXCPlayInfo: Decodable, Sendable {
    public let responseCode: Int
    public let input: String
    public let playback: String
    public let artist: String?
    public let track: String?

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case input, playback, artist, track
    }
}
