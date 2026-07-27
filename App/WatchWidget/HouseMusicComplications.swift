import WidgetKit
import SwiftUI

@main
struct HouseMusicWidgetBundle: WidgetBundle {
    var body: some Widget {
        SelectionComplication()
    }
}

struct SelectionEntry: TimelineEntry {
    let date: Date
    let name: String
    let colorHex: String
}

/// Reads the current selection from the shared App Group. The app reloads the
/// timeline whenever it changes, so a single non-expiring entry is enough.
struct SelectionProvider: TimelineProvider {
    private func current() -> SelectionEntry {
        let s = SharedSelection.read()
        return SelectionEntry(date: Date(), name: s.name, colorHex: s.colorHex)
    }
    func placeholder(in context: Context) -> SelectionEntry {
        SelectionEntry(date: Date(), name: "Decks", colorHex: "E8602B")
    }
    func getSnapshot(in context: Context, completion: @escaping (SelectionEntry) -> Void) {
        completion(current())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SelectionEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }
}

struct SelectionComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HouseMusicSelection", provider: SelectionProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Shows what House Music is playing; tap to control.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SelectionEntry

    private var color: Color { Color(hexString: entry.colorHex) }

    private var textColor: Color { SharedSelection.foreground(for: entry.colorHex) }

    var body: some View {
        // Every accessory-widget view MUST declare a containerBackground or
        // watchOS renders the "!" placeholder. Fill it with the tile colour.
        content.containerBackground(color, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            Text(SharedSelection.abbreviate(entry.name))
                .font(.system(size: 16, weight: .heavy))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(textColor)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .accessoryRectangular:
            Text(entry.name)
                .font(.system(size: 20, weight: .heavy))
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .foregroundStyle(textColor)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        case .accessoryCorner:
            Text(SharedSelection.abbreviate(entry.name))
                .font(.system(size: 17, weight: .heavy))
                .widgetLabel(entry.name)

        case .accessoryInline:
            Text(entry.name)

        default:
            Text(SharedSelection.abbreviate(entry.name))
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(textColor)
        }
    }
}
