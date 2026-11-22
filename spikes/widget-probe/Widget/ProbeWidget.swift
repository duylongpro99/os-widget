import SwiftUI
import WidgetKit

struct ProbeEntry: TimelineEntry {
    let date: Date
    let text: String
}

struct ProbeProvider: TimelineProvider {
    private func read() -> String {
        let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
        guard let defaults = UserDefaults(suiteName: id),
              let value = defaults.string(forKey: "lastWrite") else {
            return "App Group: lỗi"
        }
        return value
    }

    func placeholder(in context: Context) -> ProbeEntry {
        ProbeEntry(date: Date(), text: "…")
    }

    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        completion(ProbeEntry(date: Date(), text: read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        completion(Timeline(entries: [ProbeEntry(date: Date(), text: read())], policy: .never))
    }
}

struct ProbeWidgetView: View {
    let entry: ProbeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Probe").font(.caption).foregroundStyle(.secondary)
            Text(entry.text).font(.headline)
            Text("Đọc lúc \(entry.date.formatted(date: .omitted, time: .standard))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProbeWidget", provider: ProbeProvider()) { entry in
            ProbeWidgetView(entry: entry)
        }
        .configurationDisplayName("Probe")
        .description("Hiện chuỗi app ghi vào App Group.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
