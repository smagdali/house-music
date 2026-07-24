import SwiftUI
import HouseMusicKit

/// First-run setup: discover devices, confirm rooms, curate inputs, seed presets.
struct WizardView: View {
    @Environment(AppModel.self) private var model
    @State private var phase = Phase.welcome
    @State private var found: [Device] = []
    @State private var kept: Set<DeviceID> = []
    @State private var curated: [DeviceID: [InputChoice]] = [:]

    enum Phase { case welcome, scanning, rooms, done }

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
                Button("Find my devices") { Task { await scan() } }
                    .buttonStyle(WizardButton())
            case .scanning:
                ProgressView().controlSize(.large).tint(Color(hex: "E9A23B"))
                Text("Scanning your network\u{2026}")
                    .foregroundStyle(Color(hex: "BEB5A8"))
            case .rooms:
                Text("Found \(found.count) devices")
                    .font(.system(size: 26, weight: .heavy))
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
                Button("Set up \(kept.count) rooms") { finish() }
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

    private func scan() async {
        phase = .scanning
        var devices = await model.discovery.discover()
        if devices.isEmpty {
            // SSDP can be blocked by AP isolation; fall back to probing common addresses.
            devices = []
        }
        // Enrich with volume range and curated inputs.
        for index in devices.indices {
            if let features = try? await model.client.features(host: devices[index].ipAddress) {
                devices[index].volumeMax = features.zone.first { $0.id == "main" }?.volumeMax
            }
            if let names = try? await model.client.nameText(host: devices[index].ipAddress) {
                curated[devices[index].id] = Self.defaultCuration(names.inputList)
            }
        }
        found = devices
        kept = Set(devices.map(\.id))
        phase = .rooms
    }

    /// Keep inputs the owner has renamed (label differs from the stock name)
    /// plus spotify and airplay; hide the other twenty-odd.
    static func defaultCuration(_ inputs: [YXCNameText.Entry]) -> [InputChoice] {
        inputs.compactMap { entry in
            let stock = entry.id.uppercased() == entry.text.uppercased()
                || entry.text.isEmpty
                || entry.text.lowercased() == entry.id.lowercased()
            let wanted = ["spotify", "airplay"].contains(entry.id) || !stock
            let noise = ["main_sync", "mc_link", "server", "net_radio", "bluetooth", "usb", "tuner",
                         "napster", "qobuz", "tidal", "deezer", "amazon_music", "juke"].contains(entry.id)
            guard wanted && !noise else { return nil }
            return InputChoice(id: entry.id, label: entry.text)
        }
    }

    private func finish() {
        let devices = found.filter { kept.contains($0.id) }
        var config = HouseConfig(devices: devices,
                                 curatedInputs: curated.filter { kept.contains($0.key) })
        config.presets = Self.starterPresets(config)
        model.adoptConfig(config)
        model.persist()
        phase = .done
    }

    /// Seed presets: All off, Spotify per room, and a solo preset per renamed
    /// input. The user sculpts from there; baselines start at 30 percent.
    static func starterPresets(_ config: HouseConfig) -> [Preset] {
        var presets: [Preset] = []
        var colorIndex = 0
        for device in config.devices {
            for input in config.curatedInputs[device.id] ?? [] where input.id != "airplay" {
                let source = SourceRef(deviceID: device.id, inputID: input.id, label: input.label,
                                       colorHex: Palette.colorHex(for: input.id, index: colorIndex))
                colorIndex += 1
                let name = input.id == "spotify" ? "Spotify \(device.roomName)" : input.label
                presets.append(Preset(name: name, source: source, rooms: [device.id],
                                      baselines: [device.id: Int(0.3 * Double(device.volumeRange.upperBound))]))
            }
        }
        presets.append(Preset(name: "All off", source: nil, rooms: []))
        return presets
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
