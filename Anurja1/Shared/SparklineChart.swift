import Charts
import SwiftUI

struct SparklineChart: View {
    var values: [Double]
    var showsBand: Bool = false

    var body: some View {
        let series = values.isEmpty ? [0] : values
        Chart {
            if showsBand {
                RectangleMark(
                    xStart: .value("Start", 0),
                    xEnd: .value("End", max(series.count - 1, 1)),
                    yStart: .value("Low", 70),
                    yEnd: .value("High", 180)
                )
                .foregroundStyle(Color.forest.opacity(0.12))
            }
            ForEach(Array(series.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Index", index),
                    y: .value("Glucose", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.terracotta)
                .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 50...250)
        .accessibilityHidden(true)
    }
}
