import AppIntents
import KaysonicKit

/// Siri / Shortcuts: "DJ time", "Spotify in Dining Room", "Decks upstairs".
struct PresetEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Preset"
    static let defaultQuery = PresetQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// EntityStringQuery, not plain EntityQuery: a parameterised App Shortcut has
/// to match the spoken preset name against the entity list, and without string
/// matching the shortcut does not surface in Shortcuts or Siri at all.
struct PresetQuery: EntityStringQuery {
    /// Read straight from the store rather than AppModel. iOS runs this query
    /// out of process when it enumerates a parameterised shortcut's values, and
    /// spinning up the whole model (discovery, monitor, Spotify) there is both
    /// wasteful and liable to fail, which silently drops the shortcut.
    private var all: [PresetEntity] {
        let store = ConfigStore()
        return store.orderedPresets(store.loadConfig())
            // "All off" has its own dedicated shortcut, so leave it out here or
            // it is offered twice.
            .filter { !$0.isAllOff }
            .map { PresetEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [UUID]) async throws -> [PresetEntity] {
        all.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [PresetEntity] {
        all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        all
    }
}

struct ActivatePresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Activate Preset"
    static let description = IntentDescription("Puts the house into a Kaysonic preset.")
    static let openAppWhenRun = false

    @Parameter(title: "Preset")
    var preset: PresetEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let target = model.presets.first(where: { $0.id == preset.id }) else {
            return .result(dialog: "I could not find that preset.")
        }
        await model.fire(target)
        return .result(dialog: "\(target.name) on.")
    }
}

/// Turn everything off. Unparameterised, so it surfaces even when the preset
/// entity list is unavailable, and doubles as a check that App Shortcuts are
/// registering at all.
struct AllOffIntent: AppIntent {
    static let title: LocalizedStringResource = "All Off"
    static let description = IntentDescription("Turns off every room.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let target = model.presets.first(where: { $0.isAllOff })
            ?? Preset(name: "All off", source: nil, rooms: [])
        await model.fire(target)
        return .result(dialog: "All off.")
    }
}

struct KaysonicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ActivatePresetIntent(),
            phrases: [
                "\(.applicationName) \(\.$preset)",
                "Put on \(\.$preset) with \(.applicationName)",
                "Start \(\.$preset) in \(.applicationName)",
            ],
            shortTitle: "Activate preset",
            systemImageName: "hifispeaker.2"
        )
        AppShortcut(
            intent: AllOffIntent(),
            phrases: [
                "\(.applicationName) all off",
                "Turn everything off with \(.applicationName)",
            ],
            shortTitle: "All off",
            systemImageName: "speaker.slash"
        )
    }
}
