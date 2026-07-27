import SwiftUI
import KaysonicKit

@main
struct KaysonicWatchApp: App {
    @State private var model = AppModel.shared

    init() {
        SyncBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchMainView()
                .environment(model)
        }
    }
}

struct WatchMainView: View {
    @Environment(AppModel.self) private var model
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        Group {
            if model.presets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                    Text("Open Kaysonic on your iPhone to set up.")
                        .font(.system(size: 13, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
            } else {
                // Two pages: the scrolling preset list, and a dedicated volume
                // screen so the crown drives volume there without fighting the
                // list's scroll here.
                TabView {
                    PresetListView()
                    VolumeView()
                }
                .tabViewStyle(.page)
            }
        }
        .onAppear { pollTask = model.startPolling() }
        .onDisappear { pollTask?.cancel() }
    }
}

/// Scrolling list of preset tiles; the crown scrolls, a tap fires.
struct PresetListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.presets) { preset in
                Button {
                    Task { await model.fire(preset) }
                } label: {
                    WatchTile(preset: preset, active: model.activePreset?.id == preset.id)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.carousel)
        .navigationTitle(model.nowPlayingText)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WatchTile: View {
    @Environment(AppModel.self) private var model
    let preset: Preset
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(preset.name)
                .font(.system(size: 20, weight: .black))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(roomsLabel)
                .font(.system(size: 12, weight: .bold))
                .opacity(0.72)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18).fill(tileColor))
        .foregroundStyle(preset.source == nil ? Color.white : Color(hex: "161006"))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(active ? Color.white : Color.clear, lineWidth: 3))
    }

    private var tileColor: Color {
        preset.source == nil ? Color(hex: "211D19") : model.color(for: preset)
    }

    private var roomsLabel: String {
        preset.isAllOff ? "everything" : model.roomList(preset.rooms)
    }
}

/// Dedicated volume page: crown adjusts, big readout, mute below.
struct VolumeView: View {
    @Environment(AppModel.self) private var model
    @State private var crownVolume: Double = 0.3

    var body: some View {
        VStack(spacing: 12) {
            Text("VOLUME")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color(hex: "BEB5A8"))

            Text("\(Int(min(max(model.sliderPosition, 0), 1) * 100))%")
                .font(.system(size: 44, weight: .black).monospacedDigit())

            Button {
                Task { await model.toggleMute() }
            } label: {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(model.muted ? Color(hex: "0D0B09") : .white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(model.muted ? Color.white : Color(hex: "211D19")))
                    .overlay(Circle().strokeBorder(Color(hex: "BEB5A8").opacity(model.muted ? 0 : 0.6), lineWidth: 2))
            }
            .buttonStyle(.plain)
            .disabled(model.activePreset == nil)
            .opacity(model.activePreset == nil ? 0.4 : 1)
        }
        .focusable()
        .digitalCrownRotation($crownVolume, from: 0, through: 1, by: 0.02,
                              sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crownVolume) { _, newValue in
            Task { await model.setSlider(newValue) }
        }
        .onAppear { crownVolume = model.sliderPosition }
    }
}
