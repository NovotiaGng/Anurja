import SwiftUI
import WidgetKit

struct GlucoseWidgetEntry: View {
    @Environment(\.widgetFamily) private var family
    var entry: GlucoseEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                Text("Open Anurja")
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
        }
        .containerBackground(for: .widget) {
            Color.cream
        }
    }

    @ViewBuilder
    private func content(_ snapshot: GlucoseSnapshot) -> some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 12) {
                valueStack(snapshot)
                SparklineChart(values: snapshot.recent, showsBand: true)
            }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: snapshot.trendSymbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(reading(snapshot))
                    .font(.system(size: 16, weight: .bold))
                    .minimumScaleFactor(0.6)
            }
        case .accessoryRectangular:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anurja")
                        .font(.caption2)
                    Text("\(reading(snapshot)) mg/dL")
                        .font(.headline)
                        .minimumScaleFactor(0.7)
                    Text(range(snapshot))
                        .font(.caption2)
                }
                Spacer(minLength: 4)
                Image(systemName: snapshot.trendSymbol)
            }
        case .accessoryInline:
            Text("\(reading(snapshot)) mg/dL")
        default:
            valueStack(snapshot)
        }
    }

    private func valueStack(_ snapshot: GlucoseSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(reading(snapshot))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Image(systemName: snapshot.trendSymbol)
                    .foregroundStyle(Color.terracotta)
            }
            Text("mg/dL")
                .font(.caption)
                .foregroundStyle(Color.muted)
            Spacer(minLength: 0)
            Text(range(snapshot))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.forest)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("in range")
                .font(.caption2)
                .foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reading(_ snapshot: GlucoseSnapshot) -> String {
        Int(snapshot.value.rounded()).formatted()
    }

    private func range(_ snapshot: GlucoseSnapshot) -> String {
        (Double(snapshot.timeInRange) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
