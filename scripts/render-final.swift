import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF)/255, green: Double((v >> 8) & 0xFF)/255, blue: Double(v & 0xFF)/255)
    }
}
let ink = Color(hex: "161006")
func fg(_ hex: String) -> Color { hex.uppercased() == "211D19" ? .white : ink }
func abbrev(_ n: String) -> String { let l = n.lowercased(); return (l == "all quiet" || l == "all off") ? "OFF" : String(n.split(separator: " ").first ?? "") }

// Circular: filled disc, one bold word, dark ink for max contrast.
struct Circ: View { let n: String; let hex: String
    var body: some View {
        Text(abbrev(n)).font(.system(size: 21, weight: .black)).minimumScaleFactor(0.5).lineLimit(1)
            .foregroundStyle(fg(hex)).padding(3)
            .frame(width: 51, height: 51).background(Color(hex: hex)).clipShape(Circle())
    }
}
// Rectangular: filled card, largest name that fits, dark ink.
struct Rect: View { let n: String; let hex: String
    var body: some View {
        Text(n).font(.system(size: 26, weight: .black)).minimumScaleFactor(0.5).lineLimit(2)
            .foregroundStyle(fg(hex)).frame(width: 168, height: 74, alignment: .leading).padding(.horizontal, 12)
            .background(Color(hex: hex)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// Corner: bold solid arc in the preset colour hugging the top-left bezel plus
// the curved abbreviation, as accessoryCorner renders on Infograph.
struct CurvedText: View { let text: String; let radius: CGFloat; let color: Color; let centerDeg: Double
    var body: some View {
        let chars = Array(text); let spacing = 9.0
        let total = Double(chars.count - 1) * spacing; let start = centerDeg - total/2
        return ZStack {
            ForEach(0..<chars.count, id: \.self) { i in
                let a = start + Double(i) * spacing; let rad = a * .pi/180
                Text(String(chars[i])).font(.system(size: 13, weight: .black)).foregroundStyle(color)
                    .rotationEffect(.degrees(a + 90))
                    .offset(x: CGFloat(cos(rad)) * radius, y: CGFloat(sin(rad)) * radius)
            }
        }
    }
}
// A solid annular sector hugging the top-left bezel: the whole corner region
// filled with colour, per the fill standard.
// The full top-left quarter of the face filled: a 90-degree pie sector from
// centre to bezel, the maximum area an accessoryCorner-style fill could claim.
struct CornerWedge: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.move(to: c)
        p.addArc(center: c, radius: rect.width/2, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}
struct CornerTile: View { let n: String; let hex: String
    let d: CGFloat = 150
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "0A0A0A"))
            CornerWedge().fill(Color(hex: hex)).frame(width: d, height: d)
            // Largest abbreviation that fits, dark ink, in the wedge.
            Text(abbrev(n)).font(.system(size: 20, weight: .black)).minimumScaleFactor(0.4).lineLimit(1)
                .foregroundStyle(fg(hex)).frame(width: 62)
                .rotationEffect(.degrees(-45))
                .offset(x: -d*0.19, y: -d*0.19)
        }.frame(width: d, height: d).clipShape(Circle())
    }
}

let samples: [(String,String)] = [
    ("DJ time","E8602B"), ("Spotify","3DDC6A"), ("Telly time","B9A7FF"),
    ("AirKay","5FB2FF"), ("Decks whole house","E8602B"), ("All quiet","211D19"),
]

struct Sheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CIRCULAR  -  RECTANGULAR  -  CORNER (on face)")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            ForEach(samples, id: \.0) { s in
                HStack(spacing: 16) { Circ(n: s.0, hex: s.1); Rect(n: s.0, hex: s.1); CornerTile(n: s.0, hex: s.1) }
            }
        }.padding(24).background(Color.black)
    }
}
@MainActor func render() {
    let r = ImageRenderer(content: Sheet()); r.scale = 3
    if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/final.png")); print("wrote /tmp/final.png")
    }
}
MainActor.assumeIsolated { render() }
