import Foundation

/// Live snapshot of one room's state, for the now-playing strip and honest UI.
public struct RoomState: Sendable, Equatable {
    public var deviceID: DeviceID
    public var power: Bool
    public var input: String
    public var volume: Int
    public var mute: Bool
}

/// Polls all configured devices for status. YXC also pushes UDP events, but a
/// short poll is the simple, robust baseline (5 devices, one GET each).
public actor HouseMonitor {
    let client: YXCClient
    public private(set) var states: [DeviceID: RoomState] = [:]

    public init(client: YXCClient = YXCClient()) {
        self.client = client
    }

    @discardableResult
    public func refresh(config: HouseConfig) async -> [DeviceID: RoomState] {
        await withTaskGroup(of: RoomState?.self) { group in
            for device in config.devices {
                group.addTask { [client] in
                    guard let status = try? await client.status(host: device.ipAddress) else { return nil }
                    return RoomState(deviceID: device.id, power: status.isOn,
                                     input: status.input, volume: status.volume, mute: status.mute)
                }
            }
            var fresh: [DeviceID: RoomState] = [:]
            for await state in group {
                if let state { fresh[state.deviceID] = state }
            }
            states = fresh
            return fresh
        }
    }

    /// Best guess at which preset is active: every member room on with the
    /// right input, every non-member off.
    public func activePreset(config: HouseConfig) -> Preset? {
        for preset in config.presets {
            if matches(preset, config: config) { return preset }
        }
        return nil
    }

    func matches(_ preset: Preset, config: HouseConfig) -> Bool {
        if preset.isAllOff {
            return config.devices.allSatisfy { !(states[$0.id]?.power ?? false) }
        }
        guard let source = preset.source else { return false }
        for device in config.devices {
            guard let state = states[device.id] else { return false }
            let isMember = preset.rooms.contains(device.id)
            if state.power != isMember { return false }
            if isMember {
                let expected = device.id == source.deviceID ? source.inputID : "mc_link"
                if preset.rooms.count > 1 && state.input != expected { return false }
                if preset.rooms.count == 1 && device.id == source.deviceID && state.input != source.inputID { return false }
            }
        }
        return true
    }
}
