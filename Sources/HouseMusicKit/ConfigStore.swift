import Foundation

/// Local-first persistence for the household config plus the per-person preset
/// order. CloudKit sync layers on top of this store; the app always reads and
/// writes locally and reconciles with the cloud in the background.
public final class ConfigStore: @unchecked Sendable {
    let defaults: UserDefaults
    static let configKey = "houseConfig.v1"
    static let orderKey = "presetOrder.v1"   // personal, never synced

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadConfig() -> HouseConfig {
        guard let data = defaults.data(forKey: Self.configKey),
              let config = try? JSONDecoder().decode(HouseConfig.self, from: data) else {
            return HouseConfig()
        }
        return config
    }

    public func saveConfig(_ config: HouseConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: Self.configKey)
        }
    }

    // MARK: - Personal ordering

    /// Returns preset IDs in this person's order. Presets missing from the
    /// stored order (newly created by anyone) append at the end, in config order.
    public func orderedPresets(_ config: HouseConfig) -> [Preset] {
        let stored = (defaults.stringArray(forKey: Self.orderKey) ?? []).compactMap(UUID.init(uuidString:))
        var byID = Dictionary(uniqueKeysWithValues: config.presets.map { ($0.id, $0) })
        var result: [Preset] = []
        for id in stored {
            if let preset = byID.removeValue(forKey: id) { result.append(preset) }
        }
        result.append(contentsOf: config.presets.filter { byID[$0.id] != nil })
        return result
    }

    public func saveOrder(_ ids: [UUID]) {
        defaults.set(ids.map(\.uuidString), forKey: Self.orderKey)
    }
}
