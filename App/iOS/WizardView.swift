import SwiftUI
import HouseMusicKit

/// First-run setup: discover devices, confirm rooms, curate inputs, seed presets.
struct WizardView: View {
    @Environment(AppModel.self) private var model
    @State private var phase = Phase.welcome
    @State private var found: [Device] = []
    @State private var kept: Set<DeviceID> = []
    @State private var curated: [DeviceID: [InputChoice]] = [:]
    @State private var scanning = false
    @State private var scanTask: Task<Void, Never>?

    enum Phase { case welcome, scanning, done }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            switch phase {
            case .welcome:
                Text("House Music")
                    .font(.system(size: 34, weight: .heavy))
                Text("One tap to put music, telly, or the decks in any combination of rooms.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(hex: "BEB5A8"))
                Button("Find my devices") { startScan() }
                    .buttonStyle(WizardButton())
            case .scanning:
                HStack(spacing: 10) {
                    ProgressView().tint(Color(hex: "E9A23B"))
                    Text(found.isEmpty ? "Scanning\u{2026}" : "Found \(found.count) device\(found.count == 1 ? "" : "s")")
                        .font(.system(size: 24, weight: .heavy))
                }
                if found.isEmpty {
                    Text("Looking for your devices. Make sure House Music has Local Network access in Settings and every device is on the same Wi-Fi.")
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(hex: "BEB5A8"))
                        .padding(.horizontal, 8)
                } else {
                    List {
                        ForEach(found) { device in
                            Toggle(isOn: binding(device.id)) {
                                VStack(alignment: .leading) {
                                    Text(device.roomName).font(.system(size: 17, weight: .bold))
                                    Text(device.modelName).font(.system(size: 13)).foregroundStyle(.secondary)
                                }
                            }
                            .tint(Color(hex: "E9A23B"))
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .animation(.default, value: found)
                }
                Text("Keep going until every room appears, then tap Done.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "7D746A"))
                Button(kept.isEmpty ? "Done" : "Done (\(kept.count))") { finish() }
                    .buttonStyle(WizardButton())
                    .disabled(kept.isEmpty)
            case .done:
                Image(systemName: "hifispeaker.2.fill").font(.system(size: 48))
                Text("Ready").font(.system(size: 26, weight: .heavy))
            }
            Spacer()
        }
        .padding(24)
        .background(Color(hex: "0D0B09").ignoresSafeArea())
        .foregroundStyle(.white)
    }

    private func binding(_ id: DeviceID) -> Binding<Bool> {
        Binding(get: { kept.contains(id) },
                set: { on in if on { kept.insert(id) } else { kept.remove(id) } })
    }

    /// Scan continuously until the user taps Done. Each cycle sweeps the network
    /// and accumulates any new rooms into the list (deduped by device id), so a
    /// device that misses one cycle, or is powered on mid-setup, gets picked up
    /// on a later one without the user doing anything.
    private func startScan() {
        scanTask?.cancel()
        phase = .scanning
        scanning = true
        scanTask = Task {
            while !Task.isCancelled {
                for await device in model.discovery.discoveryStream(passes: 3) {
                    if !found.contains(where: { $0.id == device.id }) {
                        found.append(device)
                        found.sort { $0.roomName < $1.roomName }
                        kept.insert(device.id)
                    }
                }
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(1))
            }
            scanning = false
        }
    }

    private func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        scanning = false
    }

    /// Keep inputs the owner has renamed (label differs from the stock name)
    /// plus spotify; hide the other twenty-odd. AirPlay is excluded: it is
    /// always the phone pushing to a room, never a preset source.
    static func defaultCuration(_ inputs: [YXCNameText.Entry]) -> [InputChoice] {
        inputs.compactMap { entry in
            let stock = entry.id.uppercased() == entry.text.uppercased()
                || entry.text.isEmpty
                || entry.text.lowercased() == entry.id.lowercased()
            let wanted = entry.id == "spotify" || !stock
            let noise = ["main_sync", "mc_link", "server", "net_radio", "bluetooth", "usb", "tuner",
                         "airplay", "napster", "qobuz", "tidal", "deezer", "amazon_music", "juke"].contains(entry.id)
            guard wanted && !noise else { return nil }
            return InputChoice(id: entry.id, label: entry.text)
        }
    }

    private func finish() {
        stopScan()
        phase = .done
        Task {
            // Enrich the kept devices with volume range and curated inputs; the
            // discovery stream only yields id/model/room/ip.
            var devices = found.filter { kept.contains($0.id) }
            for index in devices.indices {
                if let features = try? await model.client.features(host: devices[index].ipAddress) {
                    devices[index].volumeMax = features.zone.first { $0.id == "main" }?.volumeMax
                }
                if let names = try? await model.client.nameText(host: devices[index].ipAddress) {
                    curated[devices[index].id] = Self.defaultCuration(names.inputList)
                }
            }
            var config = HouseConfig(devices: devices,
                                     curatedInputs: curated.filter { kept.contains($0.key) })
            config.presets = Self.starterPresets(config)
            model.adoptConfig(config)
            model.persist()
        }
    }

    /// Seed the starter preset set. Local (Debug) builds seed our actual house
    /// spec when this house is recognized; the App Store (Release) build always
    /// seeds the generic set.
    static func starterPresets(_ config: HouseConfig) -> [Preset] {
        #if HOUSE_SEED
        if let house = houseStarterPresets(config) { return house }
        #endif
        return genericStarterPresets(config)
    }

    /// Generic starter set for any MusicCast home: one "Spotify <Room>" per room
    /// plus "All off". The user builds everything else with the Custom editor.
    static func genericStarterPresets(_ config: HouseConfig) -> [Preset] {
        var presets: [Preset] = []
        for device in config.devices {
            guard (config.curatedInputs[device.id] ?? []).contains(where: { $0.id == "spotify" }) else { continue }
            let source = SourceRef(deviceID: device.id, inputID: "spotify", label: "Spotify",
                                   colorHex: Palette.colorHex(for: "spotify", index: 0))
            presets.append(Preset(name: "Spotify \(device.roomName)", source: source, rooms: [device.id],
                                  baselines: [device.id: Int(0.3 * Double(device.volumeRange.upperBound))]))
        }
        presets.append(Preset(name: "All off", source: nil, rooms: []))
        return presets
    }

    /// Our house's spec presets, mapped onto whatever was discovered. Returns nil
    /// if the expected rooms/inputs are not present (e.g. a Debug build on some
    /// other network), so it falls back to the generic set.
    static func houseStarterPresets(_ config: HouseConfig) -> [Preset]? {
        func device(_ room: String) -> Device? { config.devices.first { $0.roomName == room } }
        func hasInput(_ d: Device, _ id: String) -> Bool {
            (config.curatedInputs[d.id] ?? []).contains { $0.id == id }
        }
        func base(_ d: Device) -> Int { Int(0.3 * Double(d.volumeRange.upperBound)) }

        guard let living = device("Living Room"),
              let dining = device("Dining Room"),
              let bedroom = device("Master Bedroom"),
              hasInput(living, "audio4"), hasInput(living, "hdmi1"), hasInput(bedroom, "hdmi1")
        else { return nil }

        let decks = SourceRef(deviceID: living.id, inputID: "audio4", label: "Decks", colorHex: "F6A83C")
        let atvLR = SourceRef(deviceID: living.id, inputID: "hdmi1", label: "Apple TV", colorHex: "B9A7FF")
        let atvBR = SourceRef(deviceID: bedroom.id, inputID: "hdmi1", label: "Apple TV", colorHex: "B9A7FF")
        let spotify = SourceRef(deviceID: dining.id, inputID: "spotify", label: "Spotify", colorHex: "3DDC6A")

        return [
            Preset(name: "Decks", source: decks, rooms: [living.id, dining.id],
                   baselines: [living.id: base(living), dining.id: base(dining)]),
            Preset(name: "DJ time", source: decks, rooms: [living.id],
                   baselines: [living.id: base(living)], pureDirect: true),
            Preset(name: "Spotify", source: spotify, rooms: [dining.id], baselines: [dining.id: base(dining)]),
            Preset(name: "Telly time", source: atvLR, rooms: [living.id], baselines: [living.id: base(living)]),
            Preset(name: "TV in bed", source: atvBR, rooms: [bedroom.id], baselines: [bedroom.id: base(bedroom)]),
            Preset(name: "All off", source: nil, rooms: []),
        ]
    }
}

struct WizardButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy))
            .padding(.vertical, 14).padding(.horizontal, 28)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "E9A23B")))
            .foregroundStyle(Color(hex: "1A1408"))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
