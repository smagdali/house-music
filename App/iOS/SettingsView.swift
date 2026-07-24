import SwiftUI
import HouseMusicKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var spotifyLoggedIn = false

    var body: some View {
        NavigationStack {
            List {
                Section("Rooms") {
                    ForEach(model.config.devices) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.roomName).font(.system(size: 16, weight: .bold))
                                Text("\(device.modelName)  \u{00B7}  \(device.ipAddress)")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle()
                                .fill(model.roomStates[device.id]?.power == true ? Color(hex: "3DDC6A") : Color(hex: "3E372E"))
                                .frame(width: 10, height: 10)
                        }
                    }
                }

                Section("Inputs") {
                    ForEach(model.config.devices) { device in
                        NavigationLink {
                            InputCurationView(device: device)
                        } label: {
                            HStack {
                                Text(device.roomName)
                                Spacer()
                                Text("\((model.config.curatedInputs[device.id] ?? []).count) shown")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Spotify") {
                    if spotifyLoggedIn {
                        Button("Log out of Spotify", role: .destructive) {
                            Task {
                                await model.spotify.logout()
                                spotifyLoggedIn = false
                            }
                        }
                    } else {
                        Button("Connect Spotify") { SpotifyAuth.begin() }
                    }
                }

                Section("Household") {
                    LabeledContent("Sharing", value: "This device only")
                    Button("Re-run device setup") {
                        model.adoptConfig(HouseConfig())
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.bold) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            spotifyLoggedIn = await model.spotify.isLoggedIn
        }
    }
}

struct InputCurationView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    @State private var all: [YXCNameText.Entry] = []

    var body: some View {
        List {
            ForEach(all, id: \.id) { entry in
                Toggle(isOn: binding(entry)) {
                    HStack {
                        Text(entry.text).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(entry.id).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .tint(Color(hex: "E9A23B"))
            }
        }
        .navigationTitle(device.roomName)
        .task {
            all = (try? await model.client.nameText(host: device.ipAddress))?.inputList ?? []
        }
    }

    private func binding(_ entry: YXCNameText.Entry) -> Binding<Bool> {
        Binding {
            (model.config.curatedInputs[device.id] ?? []).contains { $0.id == entry.id }
        } set: { on in
            var inputs = model.config.curatedInputs[device.id] ?? []
            inputs.removeAll { $0.id == entry.id }
            if on { inputs.append(InputChoice(id: entry.id, label: entry.text)) }
            model.config.curatedInputs[device.id] = inputs
            model.persist()
        }
    }
}
