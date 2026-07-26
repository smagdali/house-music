import WidgetKit
import SwiftUI

@main
struct HouseMusicWidgetBundle: WidgetBundle {
    var body: some Widget {
        LaunchComplication()
    }
}

struct LaunchEntry: TimelineEntry {
    let date: Date
}

/// Static provider: the complication is a launch shortcut, so there is no
/// changing timeline to schedule (tapping it opens House Music on the watch).
struct LaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry { LaunchEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) {
        completion(LaunchEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        completion(Timeline(entries: [LaunchEntry(date: Date())], policy: .never))
    }
}

struct LaunchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HouseMusicLaunch", provider: LaunchProvider()) { _ in
            ComplicationView()
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("House Music")
        .description("Open House Music to control your rooms.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            nutmeg.clipShape(Circle())
        case .accessoryCorner:
            nutmeg.frame(width: 26, height: 26).clipShape(Circle())
                .widgetLabel("House Music")
        case .accessoryInline:
            // Inline only supports SF Symbols, not custom images.
            Label("House Music", systemImage: "cat.fill")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                nutmeg.frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("House Music").font(.system(size: 16, weight: .heavy))
                    Text("Tap to control").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        default:
            nutmeg.frame(width: 26, height: 26).clipShape(Circle())
        }
    }

    /// The full app icon, rendered in its own colours (the watch face may still
    /// tint it monochrome depending on the face).
    private var nutmeg: some View {
        Image("Nutmeg").resizable().renderingMode(.original).scaledToFit()
    }
}
