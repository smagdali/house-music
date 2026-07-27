import SwiftUI
import AppKit

// Mockups of every complication family at real proportions, for a sample preset
// (DJ time, orange) and the Off state, so we can compare designs before choosing.

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF)/255, green: Double((v >> 8) & 0xFF)/255, blue: Double(v & 0xFF)/255)
    }
}

let orange = Color(hex: "E8602B")
let ink = Color(hex: "161006")

func label(_ t: String) -> some View {
    Text(t).font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: "8A8A8A"))
        .frame(width: 150, alignment: .leading)
}

// A: filled circle (current)
struct CircFill: View {
    var body: some View {
        Text("DJ").font(.system(size: 17, weight: .heavy)).foregroundStyle(ink)
            .frame(width: 50, height: 50).background(orange).clipShape(Circle())
    }
}
// B: ring + text (colour outline, dark backdrop)
struct CircRing: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "1C1712"))
            Circle().strokeBorder(orange, lineWidth: 5)
            Text("DJ").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
        }.frame(width: 50, height: 50)
    }
}
// C: cat glyph + tint
struct CircGlyph: View {
    var body: some View {
        ZStack {
            Circle().fill(orange)
            Image(systemName: "cat.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(ink)
        }.frame(width: 50, height: 50)
    }
}
// D: gauge-style (progress ring = volume) with label
struct CircGauge: View {
    var body: some View {
        ZStack {
            Circle().stroke(Color(hex: "2A2018"), lineWidth: 5)
            Circle().trim(from: 0, to: 0.55).stroke(orange, style: .init(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("DJ").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
        }.frame(width: 50, height: 50)
    }
}

// Rectangular A: full fill (current)
struct RectFill: View {
    var body: some View {
        Text("DJ time").font(.system(size: 20, weight: .heavy)).foregroundStyle(ink)
            .frame(width: 170, height: 72, alignment: .leading).padding(.horizontal, 12)
            .background(orange).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
// Rectangular B: dark card, colour bar + title + subtitle
struct RectCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Capsule().fill(orange).frame(width: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text("DJ time").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                Text("Living Room").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "9A9A9A"))
            }
            Spacer(minLength: 0)
        }
        .frame(width: 170, height: 72, alignment: .leading).padding(.horizontal, 12)
        .background(Color(hex: "1C1712")).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
// Rectangular C: title + rooms, filled
struct RectRooms: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DJ time").font(.system(size: 19, weight: .heavy)).foregroundStyle(ink)
            Text("Living Room").font(.system(size: 12, weight: .bold)).foregroundStyle(ink.opacity(0.7))
        }
        .frame(width: 170, height: 72, alignment: .leading).padding(.horizontal, 12)
        .background(orange).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// Inline (single line at top of face): glyph + text
struct Inline: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "cat.fill").font(.system(size: 13, weight: .bold))
            Text("DJ time").font(.system(size: 15, weight: .semibold))
        }.foregroundStyle(.white).frame(width: 170, height: 24, alignment: .leading)
    }
}

// Corner (curved bottom/top corner): compact content + arc label approximated
struct Corner: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("DJ").font(.system(size: 16, weight: .heavy)).foregroundStyle(ink)
                .frame(width: 40, height: 40).background(orange).clipShape(Circle())
            Text("DJ time").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
        }
    }
}

struct Sheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("CIRCULAR options").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
            HStack(spacing: 14) { CircFill(); label("A fill (current)") }
            HStack(spacing: 14) { CircRing(); label("B colour ring") }
            HStack(spacing: 14) { CircGlyph(); label("C cat glyph") }
            HStack(spacing: 14) { CircGauge(); label("D gauge = volume") }

            Text("RECTANGULAR options").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white).padding(.top, 8)
            HStack(spacing: 14) { RectFill(); label("A fill (current)") }
            HStack(spacing: 14) { RectCard(); label("B dark card + rooms") }
            HStack(spacing: 14) { RectRooms(); label("C fill + rooms") }

            Text("INLINE / CORNER").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white).padding(.top, 8)
            HStack(spacing: 14) { Inline(); label("inline (top of face)") }
            HStack(spacing: 14) { Corner(); label("corner") }
        }
        .padding(28).frame(width: 620, alignment: .leading).background(Color.black)
    }
}

@MainActor func render() {
    let r = ImageRenderer(content: Sheet()); r.scale = 3
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed"); return
    }
    try? png.write(to: URL(fileURLWithPath: "/tmp/complication-families.png"))
    print("wrote /tmp/complication-families.png")
}
MainActor.assumeIsolated { render() }
