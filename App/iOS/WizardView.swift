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
                    if scanning { ProgressView().tint(Color(hex: "E9A23B")) }
                    Text(found.isEmpty ? "Scanning\u{2026}" : "Found \(found.count) device\(found.count == 1 ? "" : "s")")
                        .font(.system(size: 24, weight: .heavy))
                }
                if found.isEmpty && !scanning {
                    Text("Nothing found. Make sure House Music has Local Network access in Settings and every device is on the same Wi-Fi.")
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
                Button(scanning ? "Done (\(kept.count))" : "Set up \(kept.count) rooms") { finish() }
                    .buttonStyle(WizardButton())
                    .disabled(kept.isEmpty)
                if !scanning {
                    Button("Scan again") { startScan() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "BEB5A8"))
                }
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

    /// Start (or restart) a progressive scan. Devices appear in the list as they
    /// answer, across several passes, so slow responders are not missed. The
    /// user taps Done whenever the expected rooms are all present.
    private func startScan() {
        scanTask?.cancel()
        found = []; kept = []
        phase = .scanning
        scanning = true
        scanTask = Task {
            for await device in model.discovery.discoveryStream() {
                if !found.contains(where: { $0.id == device.id }) {
                    found.append(device)
                    found.sort { $0.roomName < $1.roomName }
                    kept.insert(device.id)
                }
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
