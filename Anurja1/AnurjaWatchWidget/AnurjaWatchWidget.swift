import WidgetKit
import SwiftUI

struct WatchGlucoseEntry: TimelineEntry {
    var date: Date
    var snapshot: GlucoseSnapshot?
}

struct WatchGlucoseProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchGlucoseEntry {
        WatchGlucoseEntry(date: Date(), snapshot: .demo)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchGlucoseEntry) -> Void) {
        let snapshot = SharedStore.load() ?? (context.isPreview ? .demo : nil)
        completion(WatchGlucoseEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchGlucoseEntry>) -> Void) {
        let entry = WatchGlucoseEntry(date: Date(), snapshot: SharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct WatchGlucoseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AnurjaWatchGlucose", provider: WatchGlucoseProvider()) { entry in
            WatchComplicationView(entry: entry)
        }
        .configurationDisplayName(Text("Glucose"))
        .description(Text("Your latest glucose and time in range."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchGlucoseEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .accessoryRectangular:
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anurja")
                                .font(.caption2)
                            Text("\(Int(snapshot.value.rounded()).formatted()) mg/dL")
                                .font(.headline)
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: snapshot.trendSymbol)
                    }
                default:
                    VStack(spacing: 0) {
                        Image(systemName: snapshot.trendSymbol)
                            .font(.system(size: 10, weight: .semibold))
                        Text(Int(snapshot.value.rounded()).formatted())
                            .font(.system(size: 16, weight: .bold))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Open Anurja")
                    .font(.caption)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
            }
        }
        .containerBackground(for: .widget) {
            Color.cream
        }
    }
}

@main
struct AnurjaWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchGlucoseWidget()
    }
}
