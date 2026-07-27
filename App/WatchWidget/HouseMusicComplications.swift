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
    let rooms: String
}

/// Reads the current selection from the shared App Group. The app reloads the
/// timeline whenever it changes, so a single non-expiring entry is enough.
struct SelectionProvider: TimelineProvider {
    private func current() -> SelectionEntry {
        let s = SharedSelection.read()
        return SelectionEntry(date: Date(), name: s.name, colorHex: s.colorHex, rooms: s.rooms)
    }
    func placeholder(in context: Context) -> SelectionEntry {
        SelectionEntry(date: Date(), name: "Decks", colorHex: "E8602B", rooms: "Whole House")
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
        content
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            Text(SharedSelection.abbreviate(entry.name))
                .font(.system(size: 22, weight: .black))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(textColor)
                .padding(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .containerBackground(color, for: .widget)

        case .accessoryRectangular:
            Text(entry.name)
                .font(.system(size: 26, weight: .black))
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .foregroundStyle(textColor)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .containerBackground(color, for: .widget)

        case .accessoryCorner:
            // widgetCurvesContent draws the content large along the outer arc,
            // the treatment Weather uses for its "50%". The watch face sets the
            // metric and palette, so font size and colour here are ignored;
            // keep the string short (about 7 characters) or it truncates.
            // The big curved word sits on the outer arc; the rooms go on the
            // inner arc. The curved treatment only engages when a widgetLabel
            // is present, so always supply one (verified in the simulator).
            Text(SharedSelection.abbreviate(entry.name).uppercased())
                .widgetCurvesContent()
                .widgetLabel {
                    Text(entry.rooms.isEmpty ? entry.name : entry.rooms)
                }

        case .accessoryInline:
            Text(entry.name)

        default:
            Text(SharedSelection.abbreviate(entry.name))
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(textColor)
                .containerBackground(color, for: .widget)
        }
    }
}
