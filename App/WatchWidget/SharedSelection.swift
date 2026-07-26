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
                defaults?.string(forKey: colorKey) ?? "3E372E")
    }

    /// Short form for the tightest slots: first word, or the initials of a
    /// multi-word name (e.g. "Decks whole house" -> "DWH", "Spotify" -> "SPOT").
    static func abbreviate(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count > 1 { return words.map { String($0.prefix(1)) }.joined().uppercased() }
        return String(name.prefix(5)).uppercased()
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
