import AppIntents
import HouseMusicKit

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
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PresetEntity] {
        AppModel.shared.presets
            .filter { identifiers.contains($0.id) }
            .map { PresetEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PresetEntity] {
        AppModel.shared.presets
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { PresetEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PresetEntity] {
        AppModel.shared.presets.map { PresetEntity(id: $0.id, name: $0.name) }
    }
}

struct ActivatePresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Activate Preset"
    static let description = IntentDescription("Puts the house into a House Music preset.")
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

struct HouseMusicShortcuts: AppShortcutsProvider {
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
