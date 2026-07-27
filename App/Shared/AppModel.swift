import Foundation
import SwiftUI
import AppIntents
import KaysonicKit
#if os(watchOS)
import WidgetKit
#endif

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
        #if os(watchOS)
        publishSelection()
        #endif
    }

    #if os(watchOS)
    /// Share the current selection with the watch complication and refresh it.
    private func publishSelection() {
        let hex = activePreset?.source.map { Palette.colorHex(for: $0.inputID) } ?? SharedSelection.offHex
        let rooms = activePreset.map { $0.isAllOff ? "" : roomList($0.rooms) } ?? ""
        SharedSelection.write(name: nowPlayingText, colorHex: hex, rooms: rooms)
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif

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

    /// Rooms that are audibly playing right now and that this preset would
    /// silence or switch to a different source. Used to confirm before cutting
    /// off someone else's music, since firing a preset powers off every room
    /// that is not part of it.
    func conflicts(with preset: Preset) -> [Device] {
        let plan = PresetEngine.plan(for: preset, config: config)
        let members = Set(preset.rooms)
        return config.devices.filter { device in
            guard let state = roomStates[device.id], state.isPlaying else { return false }
            if plan.powerOff.contains(device.id) { return true }
            guard members.contains(device.id) else { return false }
            let expected = device.id == preset.source?.deviceID
                ? (preset.source?.inputID ?? state.input)
                : "mc_link"
            return state.input != expected
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
        // Tell iOS the shortcut parameter's values changed, or the parameterised
        // App Shortcut never gets populated and does not appear in Shortcuts.
        KaysonicShortcuts.updateAppShortcutParameters()
        SyncBridge.shared.pushConfig(config)
        #if os(iOS)
        Task { await cloudPush() }
        #endif
    }

    func adoptConfig(_ fresh: HouseConfig) {
        config = fresh
        store.saveConfig(fresh)
        presets = store.orderedPresets(fresh)
        KaysonicShortcuts.updateAppShortcutParameters()
    }

    /// Baseline tick position for the active preset, 0...1, or nil without one.
    var baselineTick: Double? {
        guard let active = activePreset, let reference = referenceRoom(active),
              let baseline = active.baselines[reference.id] else { return nil }
        let span = Double(reference.volumeRange.upperBound)
        guard span > 0 else { return nil }
        return Double(baseline) / span
    }

    /// Tile colour is derived from the source input, not the preset's stored
    /// colorHex, so palette changes apply to every preset at once (including
    /// old presets rehydrated from CloudKit) with no regeneration.
    func color(for preset: Preset) -> Color {
        guard let source = preset.source else { return Color(white: 0.16) }
        return Color(hex: Palette.colorHex(for: source.inputID))
    }

    /// Now-playing strip text. A saved preset shows its name; an unmatched
    /// ("custom") state is described from what is actually playing rather than
    /// the opaque "Mixed state".
    var nowPlayingText: String {
        if let active = activePreset {
            return active.isAllOff ? "All quiet" : active.name
        }
        return liveStateSummary
    }

    /// "Whole House" when every configured room is included, otherwise the room
    /// names joined with " + " in device order. `short` drops a trailing " Room"
    /// ("Living Room" -> "Living") to keep the MusicCast group name compact in
    /// Spotify Connect; the in-app UI keeps full names.
    func roomList(_ rooms: some Sequence<DeviceID>, short: Bool = false) -> String {
        let ids = Set(rooms)
        let ordered = config.devices.filter { ids.contains($0.id) }.map { device -> String in
            short && device.roomName.hasSuffix(" Room")
                ? String(device.roomName.dropLast(5))
                : device.roomName
        }
        return ordered.count == config.devices.count && !ordered.isEmpty
            ? "Whole House"
            : ordered.joined(separator: " + ")
    }

    /// "<Source> \u{00B7} <rooms>", e.g. "Decks \u{00B7} Whole House". Used for the
    /// now-playing strip and the MusicCast group name, so an ad-hoc setup reads
    /// well in Spotify Connect instead of the bare "Custom".
    func describe(source label: String, rooms: some Sequence<DeviceID>, short: Bool = false) -> String {
        let rooms = roomList(rooms, short: short)
        return rooms.isEmpty ? label : "\(label) \u{00B7} \(rooms)"
    }

    /// Compact description of the live house when no saved preset matches,
    /// collapsing to "Whole House" and listing several independent sources as
    /// "<A> \u{00B7} Room, <B> \u{00B7} Room".
    private var liveStateSummary: String {
        let onRooms = config.devices.filter { roomStates[$0.id]?.power == true }
        guard !onRooms.isEmpty else { return "All quiet" }

        func inputLabel(_ device: Device) -> String {
            let input = roomStates[device.id]?.input ?? ""
            return (config.curatedInputs[device.id] ?? []).first { $0.id == input }?.label ?? input
        }

        // A room on mc_link is a client receiving another room's stream; a room
        // on any other input is its own source.
        let sources = onRooms.filter { (roomStates[$0.id]?.input ?? "") != "mc_link" }
        let clients = onRooms.filter { (roomStates[$0.id]?.input ?? "") == "mc_link" }

        if sources.count == 1, let server = sources.first {
            // A muted source room feeding mc_link clients is a silent server
            // (e.g. Stream here): name its input but list only the audible rooms.
            let serverSilent = (roomStates[server.id]?.mute ?? false) && !clients.isEmpty
            let rooms = (serverSilent ? clients : [server] + clients).map(\.id)
            return describe(source: inputLabel(server), rooms: rooms)
        }
        if !sources.isEmpty {
            return sources.map { "\(inputLabel($0)) \u{00B7} \($0.roomName)" }.joined(separator: ", ")
        }
        return describe(source: "Playing", rooms: onRooms.map(\.id))
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
    /// The app's accent / selection colour (chips, buttons, slider). Preset
    /// tiles must never use this or a look-alike, or an active tile is
    /// indistinguishable from a selected control.
    static let highlight = "E9A23B"

    /// Distinct colours for the common inputs, all kept clear of `highlight`.
    static func colorHex(for inputID: String) -> String {
        switch inputID {
        case "spotify": return "3DDC6A" // green
        case "audio4":  return "E8602B" // burnt orange - Decks
        case "audio5":  return "5FB2FF" // blue - AirKay
        case "hdmi1":   return "B9A7FF" // violet - Apple TV
        default:
            // Every other input gets its own colour, keyed by the input id so
            // it is distinct per source and stable across launches (String's
            // own hashValue is per-process randomised, so roll a fixed one).
            let pool = ["FF6B62", "6BE0D5", "E86BB0", "4FC3F7", "C77DFF"]
            let h = inputID.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
            return pool[abs(h) % pool.count]
        }
    }
}
