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

struct PresetQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PresetEntity] {
        AppModel.shared.presets
            .filter { identifiers.contains($0.id) }
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
    }
}
