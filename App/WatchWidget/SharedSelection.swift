import SwiftUI

/// The current selection, shared from the watch app to the complication via an
/// App Group. Written by AppModel on each refresh; read by the widget timeline.
enum SharedSelection {
    static let suite = "group.org.whitelabel.housemusic"
    private static let nameKey = "selectionName"
    private static let colorKey = "selectionColor"

    static func write(name: String, colorHex: String) {
        let defaults = UserDefaults(suiteName: suite)
        defaults?.set(name, forKey: nameKey)
        defaults?.set(colorHex, forKey: colorKey)
    }

    static func read() -> (name: String, colorHex: String) {
        let defaults = UserDefaults(suiteName: suite)
        return (defaults?.string(forKey: nameKey) ?? "All quiet",
                defaults?.string(forKey: colorKey) ?? offHex)
    }

    /// Tile colour for the idle/off state (matches the phone preset tiles).
    static let offHex = "211D19"

    /// Foreground for text on a tile of `colorHex`: dark on a source colour,
    /// white on the dark off tile, exactly like the phone tiles.
    static func foreground(for colorHex: String) -> Color {
        colorHex.uppercased() == offHex ? .white : Color(hexString: "161006")
    }

    /// Short, readable form for the tightest slots: the first word (e.g.
    /// "DJ time" -> "DJ", "Decks whole house" -> "Decks", "Spotify" -> "Spotify").
    static func abbreviate(_ name: String) -> String {
        let lower = name.lowercased()
        if lower == "all quiet" || lower == "all off" { return "Off" }
        return String(name.split(separator: " ").first ?? "")
    }
}

extension Color {
    init(hexString: String) {
        var value: UInt64 = 0
        Scanner(string: hexString.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
