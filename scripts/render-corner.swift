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

// Curved label along the bezel, letters upright to the arc (reads correctly).
struct CurvedText: View {
    let text: String; let radius: CGFloat; let color: Color; let centerDeg: Double
    var body: some View {
        let chars = Array(text)
        let spacing = 8.0
        let total = Double(chars.count - 1) * spacing
        let start = centerDeg - total/2
        return ZStack {
            ForEach(0..<chars.count, id: \.self) { i in
                let a = start + Double(i) * spacing
                let rad = a * .pi/180
                Text(String(chars[i]))
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(color)
                    .rotationEffect(.degrees(a + 90))
                    .offset(x: CGFloat(cos(rad)) * radius, y: CGFloat(sin(rad)) * radius)
            }
        }
    }
}

struct FaceCorner: View {
    let size: CGFloat = 420
    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            ForEach(0..<60) { i in
                Rectangle().fill(Color(hex: "3a3a55"))
                    .frame(width: 2, height: i % 5 == 0 ? 12 : 6)
                    .offset(y: -size/2 + 14).rotationEffect(.degrees(Double(i) * 6))
            }
            Capsule().fill(.white).frame(width: 6, height: 150).offset(y: -55).rotationEffect(.degrees(200))
            Circle().fill(orange).frame(width: 12, height: 12)

            // Bold solid corner arc in the preset colour (top-left), thicker than
            // the weather gauge, no gradient.
            Circle()
                .trim(from: 0.5, to: 0.625) // 180 to 225 deg span, hugging the top-left
                .stroke(orange, style: .init(lineWidth: 12, lineCap: .round))
                .frame(width: size - 34, height: size - 34)

            // Curved preset name just inside the arc.
            CurvedText(text: "DJ TIME", radius: size/2 - 40, color: orange, centerDeg: 202)
        }
        .frame(width: size, height: size).padding(30).background(Color(hex: "0A0A0A"))
    }
}

@MainActor func render() {
    let r = ImageRenderer(content: FaceCorner()); r.scale = 3
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
        print("fail"); return
    }
    try? png.write(to: URL(fileURLWithPath: "/tmp/corner.png"))
    print("wrote /tmp/corner.png")
}
MainActor.assumeIsolated { render() }
