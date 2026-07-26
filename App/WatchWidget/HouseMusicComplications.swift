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
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 17, weight: .bold))
            }
        case .accessoryCorner:
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: 20, weight: .bold))
                .widgetLabel("House Music")
        case .accessoryInline:
            Label("House Music", systemImage: "hifispeaker.2.fill")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 22, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("House Music").font(.system(size: 16, weight: .heavy))
                    Text("Tap to control").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        default:
            Image(systemName: "hifispeaker.2.fill")
        }
    }
}
