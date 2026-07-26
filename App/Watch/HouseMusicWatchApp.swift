import SwiftUI
import HouseMusicKit

@main
struct HouseMusicWatchApp: App {
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
    @State private var page = 0
    @State private var crownVolume: Double = 0.3
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        Group {
            if model.presets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                    Text("Open House Music on your iPhone to set up.")
                        .font(.system(size: 13, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
            } else {
                TabView(selection: $page) {
                    ForEach(Array(model.presets.enumerated()), id: \.element.id) { index, preset in
                        WatchPresetCard(preset: preset, active: model.activePreset?.id == preset.id)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page)
                .focusable()
                .digitalCrownRotation($crownVolume, from: 0, through: 1, by: 0.02,
                                      sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .onChange(of: crownVolume) { _, newValue in
                    Task { await model.setSlider(newValue) }
                }
            }
        }
        .onAppear {
            crownVolume = model.sliderPosition
            pollTask = model.startPolling()
        }
        .onDisappear { pollTask?.cancel() }
    }
}

struct WatchPresetCard: View {
    @Environment(AppModel.self) private var model
    let preset: Preset
    let active: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(nowLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                Task { await model.fire(preset) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(.system(size: 22, weight: .black))
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                    Text(roomsLabel)
                        .font(.system(size: 13, weight: .bold))
                        .opacity(0.72)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 18).fill(tileColor))
                .foregroundStyle(preset.source == nil ? Color.white : Color(hex: "161006"))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(active ? Color.white : Color.clear, lineWidth: 3))
            }
            .buttonStyle(.plain)

            Button {
                Task { await model.toggleMute() }
            } label: {
                Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(.bordered)
            .clipShape(Capsule())
            .disabled(model.activePreset == nil)
        }
        .padding(.horizontal, 6)
    }

    private var tileColor: Color {
        preset.source == nil ? Color(hex: "211D19") : model.color(for: preset)
    }

    private var roomsLabel: String {
        preset.isAllOff ? "everything" : model.roomList(preset.rooms)
    }

    private var nowLabel: String { model.nowPlayingText }
}
