import OSWidgetKit
import SwiftUI
import WidgetKit

/// Entry point of the widget extension. It declares every widget the extension offers.
@main
struct OSWidgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

/// Stand-in for the items widget in medium and large sizes. It only shows the app name so the extension
/// builds and can be added to the desktop.
struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.items, provider: PlaceholderProvider()) { _ in
            Text("OS Widget")
                .font(.headline)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("OS Widget")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: Date())], policy: .never))
    }
}
