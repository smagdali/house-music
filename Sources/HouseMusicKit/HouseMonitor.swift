import Foundation

/// Live snapshot of one room's state, for the now-playing strip and honest UI.
public struct RoomState: Sendable, Equatable {
    public var deviceID: DeviceID
    public var power: Bool
    public var input: String
    public var volume: Int
    public var mute: Bool
    /// netusb playback state ("play"/"stop"/"pause") for network inputs.
    /// nil for analog and HDMI inputs, which report no playback state at all.
    public var playback: String?

    public init(deviceID: DeviceID, power: Bool, input: String, volume: Int,
                mute: Bool, playback: String? = nil) {
        self.deviceID = deviceID
        self.power = power
        self.input = input
        self.volume = volume
        self.mute = mute
        self.playback = playback
    }

    /// Best available answer to "is this room actually making sound", used to
    /// avoid interrupting someone else's music. Network inputs report playback
    /// honestly; analog and HDMI cannot, so a powered-on unmuted room counts.
    public var isPlaying: Bool {
        guard power, !mute else { return false }
        if let playback { return playback == "play" }
        return true
    }
}

/// Polls all configured devices for status. YXC also pushes UDP events, but a
/// short poll is the simple, robust baseline (5 devices, one GET each).
public actor HouseMonitor {
    let client: YXCClient
    public private(set) var states: [DeviceID: RoomState] = [:]

    /// Inputs whose playback state netusb reports. mc_link is deliberately
    /// excluded: a client mirrors its server, and reports stop regardless.
    static let playbackReportingInputs: Set<String> = [
        "spotify", "airplay", "net_radio", "bluetooth", "usb", "server",
        "napster", "qobuz", "tidal", "deezer", "amazon_music", "juke",
    ]

    public init(client: YXCClient = YXCClient()) {
        self.client = client
    }

    @discardableResult
    public func refresh(config: HouseConfig) async -> [DeviceID: RoomState] {
        await withTaskGroup(of: RoomState?.self) { group in
            for device in config.devices {
                group.addTask { [client] in
                    guard let status = try? await client.status(host: device.ipAddress) else { return nil }
                    // Only network inputs report playback; skip the extra call
                    // for analog and HDMI, where it means nothing.
                    var playback: String?
                    if Self.playbackReportingInputs.contains(status.input) {
                        playback = try? await client.playInfo(host: device.ipAddress).playback
                    }
                    return RoomState(deviceID: device.id, power: status.isOn,
                                     input: status.input, volume: status.volume,
                                     mute: status.mute, playback: playback)
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
        let audible = Set(preset.rooms)
        // The source host serves the group even when it is not a chosen room
        // (silent server, e.g. "Stream here"): it is on and on the source input,
        // while the audible rooms receive the stream over mc_link.
        let silentServer = !audible.contains(source.deviceID)
        for device in config.devices {
            guard let state = states[device.id] else { return false }
            let isServer = device.id == source.deviceID
            let shouldBeOn = audible.contains(device.id) || (isServer && silentServer)
            if state.power != shouldBeOn { return false }
            guard shouldBeOn else { continue }
            let expected = isServer ? source.inputID : "mc_link"
            if state.input != expected { return false }
        }
        return true
    }
}
