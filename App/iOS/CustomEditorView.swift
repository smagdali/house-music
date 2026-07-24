import SwiftUI
import HouseMusicKit

/// The two-axis editor: pick a source, pick rooms; fire it, or save as preset.
struct CustomEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let basePreset: Preset?
    @State private var source: SourceRef?
    @State private var rooms: Set<DeviceID> = []
    @State private var pureDirect = false
    @State private var name = ""
    @State private var showSave = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionLabel("Source")
                    chips(sources, id: \.self, label: { $0.label }, isOn: { $0 == source }) { choice in
                        source = choice
                        // Physical inputs live on one device, so pre-select that
                        // room; network sources (empty deviceID) leave rooms alone.
                        if !choice.deviceID.isEmpty, !rooms.contains(choice.deviceID) {
                            rooms.insert(choice.deviceID)
                        }
                    }

                    sectionLabel("Room combinations")
                    chips(comboNames, id: \.self, label: { $0 }, isOn: { comboMatches($0) }) { combo in
                        rooms = comboRooms(combo)
                    }

                    sectionLabel("Or pick rooms")
                    chips(model.config.devices, id: \.id, label: { $0.roomName }, isOn: { rooms.contains($0.id) }) { device in
                        if rooms.contains(device.id) { rooms.remove(device.id) } else { rooms.insert(device.id) }
                    }

                    if supportsPureDirect {
                        Toggle("Pure Direct", isOn: $pureDirect)
                            .font(.system(size: 16, weight: .bold))
                            .tint(Color(hex: "E9A23B"))
                            .padding(.top, 4)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await model.fire(draft(named: basePreset?.name ?? "Custom"))
                                dismiss()
                            }
                        } label: {
                            Text("Make it so")
                                .font(.system(size: 17, weight: .heavy))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "E9A23B")))
                                .foregroundStyle(Color(hex: "1A1408"))
                        }
                        .disabled(source == nil || rooms.isEmpty)

                        Button("Save\u{2026}") { showSave = true }
                            .font(.system(size: 15, weight: .bold))
                            .padding(.vertical, 14).padding(.horizontal, 16)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: "3E372E"), lineWidth: 2))
                            .disabled(source == nil || rooms.isEmpty)
                    }
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .background(Color(hex: "0D0B09").ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.bold) }
                }
            }
            .alert("Preset name", isPresented: $showSave) {
                TextField("Name", text: $name)
                Button("Save") {
                    let preset = draft(named: name.isEmpty ? "Preset" : name)
                    model.updatePreset(preset)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { seed() }
    }

    // MARK: - Data

    /// Networked sources (Spotify) can play on any room, so they appear once,
    /// not per device; the room selection decides which device hosts them.
    private static let networkInputs: Set<String> = ["spotify"]

    private var sources: [SourceRef] {
        var result: [SourceRef] = []

        // One chip per network source, if any device offers it. deviceID is
        // resolved from the chosen rooms at apply time (see draft()).
        for inputID in ["spotify"] {
            if let sample = model.config.devices.lazy
                .compactMap({ (model.config.curatedInputs[$0.id] ?? []).first { $0.id == inputID } })
                .first {
                result.append(SourceRef(deviceID: "", inputID: inputID, label: sample.label,
                                        colorHex: Palette.colorHex(for: inputID, index: 0)))
            }
        }

        // Physical inputs are tied to a device. Collect them, then room-qualify
        // any label that appears on more than one device (e.g. two Apple TVs).
        var physical: [(device: Device, input: InputChoice)] = []
        for device in model.config.devices {
            for input in model.config.curatedInputs[device.id] ?? []
            where !Self.networkInputs.contains(input.id) && input.id != "airplay" {
                physical.append((device, input))
            }
        }
        let labelCounts = Dictionary(physical.map { ($0.input.label, 1) }, uniquingKeysWith: +)
        var index = 1
        for (device, input) in physical {
            let repeated = (labelCounts[input.label] ?? 0) > 1
            let label = repeated ? "\(input.label) \u{00B7} \(device.roomName)" : input.label
            result.append(SourceRef(deviceID: device.id, inputID: input.id, label: label,
                                    colorHex: Palette.colorHex(for: input.id, index: index)))
            index += 1
        }
        return result
    }

    /// Resolve a network source (deviceID == "") to a concrete host device: the
    /// first selected room that offers the input, else the first selected room.
    private func resolvedSource() -> SourceRef? {
        guard var source else { return nil }
        guard source.deviceID.isEmpty else { return source }
        let host = rooms.first { (model.config.curatedInputs[$0] ?? []).contains { $0.id == source.inputID } }
            ?? rooms.first
        guard let host else { return nil }
        source.deviceID = host
        return source
    }

    private var comboNames: [String] { ["Upstairs", "Upstairs Downstairs", "Whole House"] }

    private func comboRooms(_ name: String) -> Set<DeviceID> {
        let devices = model.config.devices
        func ids(_ roomNames: [String]) -> Set<DeviceID> {
            Set(devices.filter { roomNames.contains($0.roomName) }.map(\.id))
        }
        switch name {
        case "Upstairs": return ids(["Living Room", "Dining Room"])
        case "Upstairs Downstairs": return Set(devices.filter { $0.roomName != "Office" }.map(\.id))
        default: return Set(devices.map(\.id))
        }
    }

    private func comboMatches(_ name: String) -> Bool { rooms == comboRooms(name) }

    private var supportsPureDirect: Bool {
        // Pure Direct only makes sense for a physical input feeding one AVR room.
        guard let source, !source.deviceID.isEmpty, rooms == [source.deviceID] else { return false }
        return model.config.device(source.deviceID)?.modelName.hasPrefix("RX") ?? false
    }

    private func draft(named: String) -> Preset {
        var preset = Preset(id: basePreset?.id ?? UUID(), name: named, source: resolvedSource(),
                            rooms: Array(rooms), baselines: basePreset?.baselines ?? [:],
                            pureDirect: pureDirect && rooms.count == 1)
        // New rooms get a conservative default baseline: 30 percent of range.
        for id in preset.rooms where preset.baselines[id] == nil {
            if let device = model.config.device(id) {
                preset.baselines[id] = Int(0.3 * Double(device.volumeRange.upperBound))
            }
        }
        return preset
    }

    private func seed() {
        guard let base = basePreset else { return }
        source = base.source
        rooms = Set(base.rooms)
        pureDirect = base.pureDirect
        name = base.name
    }

    // MARK: - UI bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Color(hex: "BEB5A8"))
    }

    private func chips<T, ID: Hashable>(_ items: [T], id: KeyPath<T, ID>,
                                        label: @escaping (T) -> String,
                                        isOn: @escaping (T) -> Bool,
                                        action: @escaping (T) -> Void) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: id) { item in
                Button { action(item) } label: {
                    Text(label(item))
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(isOn(item) ? Color(hex: "E9A23B") : Color(hex: "211D19")))
                        .overlay(Capsule().strokeBorder(isOn(item) ? Color.clear : Color(hex: "3E372E"), lineWidth: 2))
                        .foregroundStyle(isOn(item) ? Color(hex: "161006") : .white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal wrapping flow layout for chip rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = arrange(proposal: proposal, subviews: subviews)
        for (index, point) in placement.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
