import Foundation

/// Applies presets declaratively and runs universal volume/mute across the
/// active preset's rooms. Stateless: reads config, drives devices via YXC.
public struct PresetEngine: Sendable {
    let client: YXCClient

    public init(client: YXCClient = YXCClient()) {
        self.client = client
    }

    /// The plan of YXC work a preset implies. Separated from execution so the
    /// diffing logic is unit-testable without a network.
    public struct Plan: Equatable, Sendable {
        public var powerOff: [DeviceID] = []
        public var powerOn: [DeviceID] = []
        public var serverDevice: DeviceID?
        public var serverInput: String?
        public var clientDevices: [DeviceID] = []
        public var baselines: [DeviceID: Int] = [:]
        public var pureDirect: Bool = false
        public var dissolveGroup: Bool = false
    }

    /// Compute the plan for a preset against the full device list.
    public static func plan(for preset: Preset, config: HouseConfig) -> Plan {
        var plan = Plan()
        let members = Set(preset.rooms)
        plan.powerOff = config.devices.map(\.id).filter { !members.contains($0) }
        plan.powerOn = preset.rooms
        plan.baselines = preset.baselines
        plan.pureDirect = preset.pureDirect && preset.rooms.count == 1

        if let source = preset.source {
            plan.serverDevice = source.deviceID
            plan.serverInput = source.inputID
            plan.clientDevices = preset.rooms.filter { $0 != source.deviceID }
            plan.dissolveGroup = plan.clientDevices.isEmpty
        } else {
            plan.dissolveGroup = true
        }
        return plan
    }

    /// Execute a preset. Throws on the first hard failure of a member room;
    /// power-offs of non-members are best-effort.
    public func apply(_ preset: Preset, config: HouseConfig) async throws {
        let plan = Self.plan(for: preset, config: config)

        func host(_ id: DeviceID) throws -> String {
            guard let device = config.device(id) else {
                throw HouseMusicError.notConfigured("Device \(id)")
            }
            return device.ipAddress
        }

        // Tear down any existing group first so devices are in a known state.
        if let serverID = plan.serverDevice ?? config.devices.first?.id,
           let serverHost = try? host(serverID),
           let info = try? await client.distributionInfo(host: serverHost),
           info.isGrouped, info.role == "server" {
            let clients = info.clientList?.map(\.ipAddress) ?? []
            try? await client.dissolveGroup(serverHost: serverHost, clientIPs: clients)
        }

        // Non-members off (best effort).
        for id in plan.powerOff {
            if let h = try? host(id) { try? await client.setPower(host: h, on: false) }
        }

        // Members on, at baseline, unmuted.
        for id in plan.powerOn {
            let h = try host(id)
            try await client.setPower(host: h, on: true)
            if let units = plan.baselines[id] {
                try await client.setVolume(host: h, units: units)
            }
            try await client.setMute(host: h, muted: false)
        }

        guard let serverID = plan.serverDevice, let input = plan.serverInput else { return }
        let serverHost = try host(serverID)
        try await client.setInput(host: serverHost, input: input)

        if !plan.clientDevices.isEmpty {
            let clientIPs = try plan.clientDevices.map { try host($0) }
            try await client.makeGroup(serverHost: serverHost, clientIPs: clientIPs,
                                       groupID: YXCClient.newGroupID(), name: preset.name)
            for ip in clientIPs {
                try await client.setInput(host: ip, input: "mc_link")
            }
        }

        if plan.pureDirect {
            try await client.setPureDirect(host: serverHost, enabled: true)
        } else {
            try? await client.setPureDirect(host: serverHost, enabled: false)
        }
    }

    // MARK: - Universal volume

    /// Move every room of `preset` by the same fraction of its own volume range,
    /// per Yamaha's group-volume guidance. `delta` is a fraction of full range
    /// (e.g. +0.05 = five percent louder everywhere).
    public func nudgeVolume(preset: Preset, config: HouseConfig, delta: Double) async throws {
        for id in preset.rooms {
            guard let device = config.device(id) else { continue }
            let range = device.volumeRange
            let status = try await client.status(host: device.ipAddress)
            let span = Double(range.upperBound - range.lowerBound)
            let target = Double(status.volume) + delta * span
            let clamped = Int(target.rounded()).clamped(to: range)
            try await client.setVolume(host: device.ipAddress, units: clamped)
        }
    }

    public func setMuteAll(preset: Preset, config: HouseConfig, muted: Bool) async throws {
        for id in preset.rooms {
            guard let device = config.device(id) else { continue }
            try await client.setMute(host: device.ipAddress, muted: muted)
        }
    }

    /// Read every member room's current volume, for "save this volume to preset".
    public func currentVolumes(preset: Preset, config: HouseConfig) async throws -> [DeviceID: Int] {
        var result: [DeviceID: Int] = [:]
        for id in preset.rooms {
            guard let device = config.device(id) else { continue }
            result[id] = try await client.status(host: device.ipAddress).volume
        }
        return result
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
