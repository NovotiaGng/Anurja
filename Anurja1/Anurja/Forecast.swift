import Foundation
import SwiftUI

enum GlucoseForecast {
    static func next60Minutes(from points: [GlucosePoint]) -> [GlucosePoint] {
        guard let last = points.last else { return [] }
        let window = points.filter { last.time.timeIntervalSince($0.time) <= 30 * 60 }
        let slope = leastSquaresSlope(window, anchor: last.time)
        let tau = 20.0
        return (1...12).map { step in
            let minutes = Double(step * 5)
            let projected = last.value + slope * tau * (1 - exp(-minutes / tau))
            let clamped = min(350, max(40, projected))
            return GlucosePoint(time: last.time.addingTimeInterval(minutes * 60), value: clamped)
        }
    }

    static func tone(last: Double, forecast: [GlucosePoint]) -> ForecastTone {
        guard let end = forecast.last?.value else { return .steady }
        if end > last + 3 { return .rising }
        if end < last - 3 { return .falling }
        return .steady
    }

    private static func leastSquaresSlope(_ window: [GlucosePoint], anchor: Date) -> Double {
        guard window.count >= 2 else { return 0 }
        let xs = window.map { $0.time.timeIntervalSince(anchor) / 60 }
        let ys = window.map(\.value)
        let count = Double(xs.count)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        let numerator = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard denominator != 0 else { return 0 }
        return numerator / denominator
    }
}

enum ForecastTone {
    case steady, rising, falling

    var message: LocalizedStringKey {
        switch self {
        case .steady: "Looking steady"
        case .rising: "Heading up after your last meal"
        case .falling: "Easing down"
        }
    }

    var symbol: String {
        switch self {
        case .steady: "arrow.right"
        case .rising: "arrow.up.right"
        case .falling: "arrow.down.right"
        }
    }
}
