import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF)/255, green: Double((v >> 8) & 0xFF)/255, blue: Double(v & 0xFF)/255)
    }
}
let orange = Color(hex: "E8602B")
let ink = Color(hex: "161006")

// The corner content: the "A fill" look as it appears in an Infograph corner
// slot, a filled disc hugging the bezel with a short curved-style label.
struct CornerContent: View {
    let text: String
    var body: some View {
        Text("DJ").font(.system(size: 15, weight: .heavy)).foregroundStyle(ink)
            .frame(width: 42, height: 42).background(orange).clipShape(Circle())
    }
}

struct Infograph: View {
    let size: CGFloat = 420
    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            Circle().strokeBorder(Color(hex: "1A1A1A"), lineWidth: 2)

            // tick ring
            ForEach(0..<60) { i in
                Rectangle().fill(Color(hex: "444"))
                    .frame(width: 2, height: i % 5 == 0 ? 12 : 6)
                    .offset(y: -size/2 + 14)
                    .rotationEffect(.degrees(Double(i) * 6))
            }

            // hands
            Capsule().fill(.white).frame(width: 6, height: 120).offset(y: -50).rotationEffect(.degrees(20))
            Capsule().fill(.white).frame(width: 5, height: 150).offset(y: -60).rotationEffect(.degrees(200))
            Circle().fill(orange).frame(width: 12, height: 12)

            // four corner complications with the fill look + curved label
            corner("DJ time", angle: -135)
            corner("Spotify", angle: -45, color: Color(hex: "3DDC6A"))
            corner("Telly", angle: 135, color: Color(hex: "B9A7FF"))
            corner("AirKay", angle: 45, color: Color(hex: "5FB2FF"))
        }
        .frame(width: size, height: size)
        .padding(30).background(Color(hex: "0A0A0A"))
    }

    func corner(_ label: String, angle: Double, color: Color = orange) -> some View {
        let r = size/2 - 46
        let rad = angle * .pi / 180
        return ZStack {
            // curved label following the bezel
            Text(label.uppercased()).font(.system(size: 12, weight: .heavy)).foregroundStyle(color)
                .offset(y: -20)
            Text("DJ").font(.system(size: 14, weight: .heavy)).foregroundStyle(ink)
                .frame(width: 38, height: 38).background(color).clipShape(Circle())
        }
        .offset(x: CGFloat(cos(rad)) * r, y: CGFloat(sin(rad)) * r)
    }
}

@MainActor func render() {
    let r = ImageRenderer(content: Infograph()); r.scale = 3
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed"); return
    }
    try? png.write(to: URL(fileURLWithPath: "/tmp/infograph-corners.png"))
    print("wrote /tmp/infograph-corners.png")
}
MainActor.assumeIsolated { render() }
