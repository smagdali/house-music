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
        /// The source device serves the group but is not a chosen (audible)
        /// room, so it plays silently, e.g. "Stream here": the Living Room
        /// ingests the AirPlay stream and distributes it while muted locally.
        public var silentServer: Bool = false
    }

    /// Compute the plan for a preset against the full device list.
    public static func plan(for preset: Preset, config: HouseConfig) -> Plan {
        var plan = Plan()
        let members = Set(preset.rooms)
        plan.baselines = preset.baselines
        plan.pureDirect = preset.pureDirect && preset.rooms.count == 1

        if let source = preset.source {
            plan.serverDevice = source.deviceID
            plan.serverInput = source.inputID
            plan.silentServer = !members.contains(source.deviceID)
            plan.clientDevices = preset.rooms.filter { $0 != source.deviceID }
            // No group only when the source room plays alone.
            plan.dissolveGroup = plan.clientDevices.isEmpty && !plan.silentServer
        } else {
            plan.dissolveGroup = true
        }

        // The audible rooms plus, if it isn't one of them, the source's host
        // device (needed on to serve distribution). Everything else powers off.
        var onSet = members
        if let server = plan.serverDevice { onSet.insert(server) }
        plan.powerOn = config.devices.map(\.id).filter { onSet.contains($0) }
        plan.powerOff = config.devices.map(\.id).filter { !onSet.contains($0) }
        return plan
    }

    /// Execute a preset. Throws on the first hard failure of a member room;
    /// power-offs of non-members are best-effort.
    public func apply(_ preset: Preset, config: HouseConfig) async throws {
        let plan = Self.plan(for: preset, config: config)

        func host(_ id: DeviceID) throws -> String {
            guard let device = config.device(id) else {
                throw KaysonicError.notConfigured("Device \(id)")
            }
            return device.ipAddress
        }

        // Tear down any existing group first so devices are in a known state.
        // Scan every device, not just the incoming server: switching between
        // presets served by different devices would otherwise leave the old
        // group's server as a zombie (powered off but still "serving"), which
        // strands a Spotify Connect session pointed at the dead group.
        for device in config.devices {
            guard let info = try? await client.distributionInfo(host: device.ipAddress),
                  info.isGrouped, info.role == "server" else { continue }
            let clients = info.clientList?.map(\.ipAddress) ?? []
            try? await client.dissolveGroup(serverHost: device.ipAddress, clientIPs: clients)
        }

        // Non-members off (best effort).
        for id in plan.powerOff {
            if let h = try? host(id) { try? await client.setPower(host: h, on: false) }
        }

        // Members on, at baseline, unmuted. A device just woken from standby
        // rejects writes with response_code 5 for up to about half a second, so
        // volume and mute are retried and treated as best-effort: a cold room
        // must not throw here and abort the grouping that follows. The silent
        // server is the exception: it comes on muted, with no baseline.
        for id in plan.powerOn {
            let h = try host(id)
            try await client.setPower(host: h, on: true)
            if plan.silentServer && id == plan.serverDevice {
                await retryWhileWaking { try await client.setMute(host: h, muted: true) }
                continue
            }
            if let units = plan.baselines[id] {
                await retryWhileWaking { try await client.setVolume(host: h, units: units) }
            }
            await retryWhileWaking { try await client.setMute(host: h, muted: false) }
        }

        guard let serverID = plan.serverDevice, let input = plan.serverInput else { return }
        let serverHost = try host(serverID)
        try await client.setInput(host: serverHost, input: input)
        // Changing input can clear mute, so re-assert the silent server's mute.
        if plan.silentServer {
            await retryWhileWaking { try await client.setMute(host: serverHost, muted: true) }
        }

        if !plan.clientDevices.isEmpty {
            let clientIPs = try plan.clientDevices.map { try host($0) }
            try await client.makeGroup(serverHost: serverHost, clientIPs: clientIPs,
                                       groupID: YXCClient.newGroupID(), name: preset.name)
            // Distribution auto-switches clients to mc_link; assert it too, but
            // best-effort so a slow client cannot abort an already-formed group.
            for ip in clientIPs {
                await retryWhileWaking { try await client.setInput(host: ip, input: "mc_link") }
            }
        }

        if plan.pureDirect {
            try await client.setPureDirect(host: serverHost, enabled: true)
        } else {
            try? await client.setPureDirect(host: serverHost, enabled: false)
        }
    }

    /// Retry a write that a freshly-woken device rejects with response_code 5
    /// (not-ready). Best-effort: after the budget, or on any other error, it
    /// returns quietly so one uncooperative room cannot abort the whole preset.
    private func retryWhileWaking(_ write: () async throws -> Void) async {
        for _ in 0..<6 {
            do { try await write(); return }
            catch KaysonicError.yxcError(let code, _) where code == 5 {
                try? await Task.sleep(for: .milliseconds(500))
            } catch { return }
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
