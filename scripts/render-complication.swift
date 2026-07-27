import SwiftUI
import AppKit

// Headless preview of the complication look at real accessory sizes, so we can
// iterate on colour/text/abbreviation without deploying to the watch. This
// mirrors the visual of HouseMusicComplications.swift; it is not the widget
// itself (no WidgetKit chrome), just the fill + label we control.

func foreground(_ hex: String) -> Color { hex.uppercased() == "211D19" ? .white : Color(hex: "161006") }
func abbreviate(_ name: String) -> String {
    let l = name.lowercased()
    if l == "all quiet" || l == "all off" { return "Off" }
    return String(name.split(separator: " ").first ?? "")
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF)/255, green: Double((v >> 8) & 0xFF)/255, blue: Double(v & 0xFF)/255)
    }
}

struct Circular: View {
    let name: String; let hex: String
    var body: some View {
        Text(abbreviate(name))
            .font(.system(size: 16, weight: .heavy)).minimumScaleFactor(0.4).lineLimit(1)
            .foregroundStyle(foreground(hex)).padding(4)
            .frame(width: 50, height: 50).background(Color(hex: hex)).clipShape(Circle())
    }
}

struct Rectangular: View {
    let name: String; let hex: String
    var body: some View {
        Text(name)
            .font(.system(size: 20, weight: .heavy)).minimumScaleFactor(0.5).lineLimit(2)
            .foregroundStyle(foreground(hex))
            .frame(width: 170, height: 76, alignment: .leading).padding(.horizontal, 10)
            .background(Color(hex: hex)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// The real preset colours from Palette.
let samples: [(String, String)] = [
    ("DJ time", "E8602B"), ("Spotify", "3DDC6A"), ("Telly time", "B9A7FF"),
    ("AirKay", "5FB2FF"), ("Decks whole house", "E8602B"), ("All quiet", "211D19"),
]

struct Sheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(samples, id: \.0) { s in
                HStack(spacing: 16) {
                    Circular(name: s.0, hex: s.1)
                    Rectangular(name: s.0, hex: s.1)
                    Text(s.0).foregroundStyle(.white).font(.system(size: 13))
                }
            }
        }
        .padding(24).background(Color.black)
    }
}

@MainActor func render() {
    let r = ImageRenderer(content: Sheet())
    r.scale = 3
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed"); return
    }
    let out = "/tmp/complication-preview.png"
    try? png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}

MainActor.assumeIsolated { render() }
