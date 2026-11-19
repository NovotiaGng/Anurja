import WidgetKit
import SwiftUI

struct GlucoseEntry: TimelineEntry {
    var date: Date
    var snapshot: GlucoseSnapshot?
}

struct GlucoseProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlucoseEntry {
        GlucoseEntry(date: Date(), snapshot: .demo)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlucoseEntry) -> Void) {
        let snapshot = SharedStore.load() ?? (context.isPreview ? .demo : nil)
        completion(GlucoseEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlucoseEntry>) -> Void) {
        let entry = GlucoseEntry(date: Date(), snapshot: SharedStore.load())
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct AnurjaGlucoseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AnurjaGlucose", provider: GlucoseProvider()) { entry in
            GlucoseWidgetEntry(entry: entry)
        }
        .configurationDisplayName(Text("Glucose"))
        .description(Text("Your latest glucose and time in range."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct AnurjaWidgetBundle: WidgetBundle {
    var body: some Widget {
        AnurjaGlucoseWidget()
    }
}
