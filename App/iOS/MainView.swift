import SwiftUI
import HouseMusicKit

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var showCustom = false
    @State private var showSettings = false
    @State private var showReorder = false
    @State private var editingPreset: Preset?
    @State private var pollTask: Task<Void, Never>?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            header
            nowPlaying
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.presets) { preset in
                        PresetTile(preset: preset, active: model.activePreset?.id == preset.id)
                            .onTapGesture { Task { await model.fire(preset) } }
                            .contextMenu {
                                Button("Edit") { editingPreset = preset }
                                Button("Reorder") { showReorder = true }
                                Button("Delete", role: .destructive) { model.deletePreset(preset) }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                Button {
                    showCustom = true
                } label: {
                    Text("+ Custom source & rooms")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                .foregroundStyle(.secondary)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
            VolumeBar()
        }
        .background(Color(hex: "0D0B09").ignoresSafeArea())
        .foregroundStyle(.white)
        .sheet(isPresented: $showCustom) { CustomEditorView(basePreset: nil) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showReorder) { ReorderView() }
        .sheet(item: $editingPreset) { CustomEditorView(basePreset: $0) }
        .overlay(alignment: .bottom) { toastView }
        .onAppear { pollTask = model.startPolling() }
        .onDisappear { pollTask?.cancel() }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.activePreset.map { model.color(for: $0) } ?? Color(hex: "BEB5A8"))
                .frame(width: 10, height: 10)
                .shadow(color: model.activePreset.map { model.color(for: $0) } ?? .clear, radius: 6)
            Text(nowPlayingText)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Button {
                Task { await model.toggleMute() }
            } label: {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(model.muted ? Color(hex: "0D0B09") : .white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(model.muted ? Color.white : Color.clear))
                    .overlay(Circle().strokeBorder(Color(hex: "BEB5A8"), lineWidth: model.muted ? 0 : 2))
            }
            .disabled(model.activePreset == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "211D19")))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var nowPlayingText: String {
        guard let active = model.activePreset else { return "Mixed state" }
        if active.isAllOff { return "All quiet" }
        return "\(active.name)"
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color(hex: "3DDC6A")))
                .foregroundStyle(Color(hex: "161006"))
                .padding(.bottom, 100)
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    model.toast = nil
                }
        }
    }
}

struct PresetTile: View {
    @Environment(AppModel.self) private var model
    let preset: Preset
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 14)
            Text(preset.name)
                .font(.system(size: 19, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(roomsLabel)
                .font(.system(size: 13, weight: .bold))
                .opacity(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(minHeight: 84)
        .background(RoundedRectangle(cornerRadius: 18).fill(tileColor))
        .foregroundStyle(preset.source == nil ? Color.white : Color(hex: "161006"))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(active ? Color.white : Color.clear, lineWidth: 3)
        )
        .shadow(color: active ? tileColor.opacity(0.6) : .clear, radius: active ? 10 : 0)
    }

    private var tileColor: Color {
        preset.source == nil ? Color(hex: "211D19") : model.color(for: preset)
    }

    private var roomsLabel: String {
        if preset.isAllOff { return "everything" }
        let names = preset.rooms.compactMap { model.config.device($0)?.roomName }
        if names.count == model.config.devices.count { return "Whole House" }
        return names.joined(separator: " + ")
    }
}

struct VolumeBar: View {
    @Environment(AppModel.self) private var model
    @State private var dragging = false
    @State private var localValue: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("VOLUME")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color(hex: "BEB5A8"))
                Spacer()
                Text(percentLabel)
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
            }
            GeometryReader { geo in
                let width = geo.size.width
                let position = (dragging ? localValue : model.sliderPosition).clamped01
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: "3E372E")).frame(height: 4)
                    Capsule().fill(Color(hex: "E9A23B")).frame(width: max(0, position * width), height: 4)
                    if let tick = model.baselineTick {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 3, height: 16)
                            .position(x: tick.clamped01 * width, y: 11)
                    }
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .position(x: position * width, y: 11)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = true
                            localValue = (value.location.x / width).clamped01
                        }
                        .onEnded { _ in
                            dragging = false
                            Task { await model.setSlider(localValue) }
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.7)
                        .onEnded { _ in
                            guard !dragging else { return }
                            Task { await model.saveBaselines() }
                        }
                )
            }
            .frame(height: 22)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var percentLabel: String {
        let pct = Int(((dragging ? localValue : model.sliderPosition).clamped01 * 100).rounded())
        return "\(pct)%"
    }
}

struct ReorderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.presets) { preset in
                    Text(preset.name).font(.system(size: 17, weight: .bold))
                }
                .onMove { from, to in
                    var ids = model.presets.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    model.reorder(ids)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("My order")
            .toolbar { Button("Done") { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}

extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}
