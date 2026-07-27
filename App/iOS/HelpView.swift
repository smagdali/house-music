import SwiftUI

/// Short how-it-works page, reached from Settings. Explains the two things that
/// are not self-evident from the preset grid: the AirKay streaming route and
/// how Spotify handoff works.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                section("AirKay: streaming from your phone", [
                    "AirKay is the AirPort Express wired into the Living Room amp, a permanent AirPlay target.",
                    "To play phone or laptop audio (podcasts, BBC Sounds) in any rooms: AirPlay to \u{201C}AirKay\u{201D} from Control Centre, then in Kaysonic pick AirKay as the source and choose the rooms.",
                    "For one room quickly, you can AirPlay straight to that room\u{2019}s speaker instead, no app needed.",
                ])

                section("Spotify", [
                    "Connect your account once in Settings. Each person connects their own on their own phone.",
                    "Tap a Spotify preset: Kaysonic switches the rooms on and hands your Spotify playback to them.",
                    "It moves whatever you\u{2019}re already playing. If nothing is playing, it opens Spotify so you can press play.",
                    "Multi-room Spotify plays as one MusicCast group and appears in Spotify Connect named after the preset (e.g. \u{201C}Spotify \u{00B7} Whole House\u{201D}).",
                ])

                section("Tips", [
                    "Long-press the volume slider to save the current levels as a preset\u{2019}s baseline.",
                    "Hold a preset tile to edit, reorder, or delete it.",
                ])
            }
            .padding(20)
        }
        .background(Color(hex: "0D0B09").ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.bold) }
            }
        }
    }

    private func section(_ title: String, _ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color(hex: "E9A23B"))
            ForEach(points, id: \.self) { point in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color(hex: "E9A23B")).frame(width: 7, height: 7).padding(.top, 8)
                    Text(point)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: "E7DED2"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
