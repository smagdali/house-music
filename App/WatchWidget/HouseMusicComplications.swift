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

    var body: some View {
        // Every accessory-widget view MUST declare a containerBackground or
        // watchOS fails to render it and shows the "!" placeholder.
        content.containerBackground(for: .widget) {
            if family == .accessoryCircular { AccessoryWidgetBackground() } else { Color.clear }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            // On the face watchOS desaturates complications, so lean on a
            // legible ring plus text rather than a colour fill (which the
            // system greys out, hiding the text on top).
            ZStack {
                Circle().strokeBorder(color, lineWidth: 4)
                Text(SharedSelection.abbreviate(entry.name))
                    .font(.system(size: 16, weight: .heavy))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(6)
            }

        case .accessoryRectangular:
            HStack(spacing: 8) {
                Capsule().fill(color).frame(width: 6)
                Text(entry.name)
                    .font(.system(size: 20, weight: .heavy))
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
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
        }
    }
}
