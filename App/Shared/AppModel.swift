import Foundation
import SwiftUI
import HouseMusicKit

/// One observable model shared by the iOS and watchOS apps.
@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    let client = YXCClient()
    let store = ConfigStore()
    let engine: PresetEngine
    let monitor: HouseMonitor
    let discovery: DeviceDiscovery
    let spotify = SpotifyClient()

    var config: HouseConfig
    var presets: [Preset] = []
    var roomStates: [DeviceID: RoomState] = [:]
    var activePreset: Preset?
    /// Universal volume slider position, 0...1 of the reference room's range.
    var sliderPosition: Double = 0.3
    var muted = false
    var busy = false
    var lastError: String?
    var toast: String?
    var spotifyConnected = false

    var needsOnboarding: Bool { config.devices.isEmpty }

    private init() {
        engine = PresetEngine(client: client)
        monitor = HouseMonitor(client: client)
        discovery = DeviceDiscovery(client: client)
        config = store.loadConfig()
        // Debug: preload a config from a JSON file path (for screenshots/UI runs
        // where the simulator's Local Network privacy blocks discovery).
        if let path = ProcessInfo.processInfo.environment["HM_SEED_CONFIG"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let seeded = try? JSONDecoder().decode(HouseConfig.self, from: data) {
            config = seeded
            store.saveConfig(seeded)
        }
        presets = store.orderedPresets(config)
    }

    // MARK: - Live state

    func refresh() async {
        roomStates = await monitor.refresh(config: config)
        activePreset = await monitor.activePreset(config: config)
        if let active = activePreset, let reference = referenceRoom(active) {
            if let state = roomStates[reference.id] {
                let span = Double(reference.volumeRange.upperBound)
                if span > 0 { sliderPosition = Double(state.volume) / span }
                muted = state.mute
            }
        }
    }

    func refreshSpotifyState() async {
        spotifyConnected = await spotify.isLoggedIn
    }

    func startPolling() -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func referenceRoom(_ preset: Preset) -> Device? {
        if let source = preset.source, preset.rooms.contains(source.deviceID) {
            return config.device(source.deviceID)
        }
        return preset.rooms.first.flatMap { config.device($0) }
    }

    // MARK: - Actions

    func fire(_ preset: Preset) async {
        busy = true
        defer { busy = false }
        do {
            try await engine.apply(preset, config: config)
            if let source = preset.source, source.isSpotify {
                await handoffSpotify(preset)
            }
            muted = false
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Spotify preset: transfer the caller's session to the target room/group,
    /// then bounce into the Spotify app if nothing was playing.
    private func handoffSpotify(_ preset: Preset) async {
        guard await spotify.isLoggedIn else { return }
        let targetName = preset.rooms.count > 1
            ? preset.name
            : (referenceRoom(preset)?.roomName ?? preset.name)
        // Groups advertise under their group name; allow a settle delay.
        try? await Task.sleep(for: .seconds(2))
        try? await spotify.transferPlayback(toDeviceNamed: targetName, play: true)
        #if os(iOS)
        if let url = URL(string: "spotify:"), UIApplication.shared.canOpenURL(url) {
            await UIApplication.shared.open(url)
        }
        #endif
    }

    func setSlider(_ position: Double) async {
        guard let active = activePreset else { return }
        let delta = position - sliderPosition
        sliderPosition = position
        try? await engine.nudgeVolume(preset: active, config: config, delta: delta)
    }

    func toggleMute() async {
        guard let active = activePreset else { return }
        muted.toggle()
        try? await engine.setMuteAll(preset: active, config: config, muted: muted)
    }

    /// Long-press on the slider: current room volumes become this preset's baselines.
    func saveBaselines() async {
        guard var active = activePreset else { return }
        guard let volumes = try? await engine.currentVolumes(preset: active, config: config) else { return }
        active.baselines = volumes
        updatePreset(active)
        toast = "Baseline saved"
    }

    // MARK: - Config mutation

    func updatePreset(_ preset: Preset) {
        if let index = config.presets.firstIndex(where: { $0.id == preset.id }) {
            config.presets[index] = preset
        } else {
            config.presets.append(preset)
        }
        persist()
        if activePreset?.id == preset.id { activePreset = preset }
    }

    func deletePreset(_ preset: Preset) {
        config.presets.removeAll { $0.id == preset.id }
        persist()
    }

    func reorder(_ ids: [UUID]) {
        store.saveOrder(ids)
        presets = store.orderedPresets(config)
    }

    func persist() {
        store.saveConfig(config)
        presets = store.orderedPresets(config)
        SyncBridge.shared.pushConfig(config)
        #if os(iOS)
        Task { await cloudPush() }
        #endif
    }

    func adoptConfig(_ fresh: HouseConfig) {
        config = fresh
        store.saveConfig(fresh)
        presets = store.orderedPresets(fresh)
    }

    /// Baseline tick position for the active preset, 0...1, or nil without one.
    var baselineTick: Double? {
        guard let active = activePreset, let reference = referenceRoom(active),
              let baseline = active.baselines[reference.id] else { return nil }
        let span = Double(reference.volumeRange.upperBound)
        guard span > 0 else { return nil }
        return Double(baseline) / span
    }

    func color(for preset: Preset) -> Color {
        guard let hex = preset.source?.colorHex else { return Color(white: 0.16) }
        return Color(hex: hex)
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

enum Palette {
    /// Preset tile colours by input flavour; deterministic assignment order.
    static let sourceColors = [
        "F6A83C", // amber (analog / decks)
        "3DDC6A", // green (spotify)
        "B9A7FF", // violet (hdmi / tv)
        "5FB2FF", // blue
        "FF6B62", // red
        "6BE0D5", // teal
    ]

    static func colorHex(for inputID: String, index: Int) -> String {
        if inputID == "spotify" { return "3DDC6A" }
        if inputID.hasPrefix("hdmi") { return "B9A7FF" }
        if inputID.hasPrefix("audio") || inputID == "phono" || inputID == "aux" { return "F6A83C" }
        if inputID == "airplay" { return "5FB2FF" }
        return sourceColors[index % sourceColors.count]
    }
}
