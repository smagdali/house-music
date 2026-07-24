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
                        if !rooms.contains(choice.deviceID) { rooms.insert(choice.deviceID) }
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

    private var sources: [SourceRef] {
        var result: [SourceRef] = []
        var index = 0
        for device in model.config.devices {
            for input in model.config.curatedInputs[device.id] ?? [] {
                result.append(SourceRef(deviceID: device.id, inputID: input.id, label: input.label,
                                        colorHex: Palette.colorHex(for: input.id, index: index)))
                index += 1
            }
        }
        return result
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
        guard let source, rooms == [source.deviceID] else { return false }
        return model.config.device(source.deviceID)?.modelName.hasPrefix("RX") ?? false
    }

    private func draft(named: String) -> Preset {
        var preset = Preset(id: basePreset?.id ?? UUID(), name: named, source: source,
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
