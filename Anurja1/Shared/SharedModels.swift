import Foundation

struct GlucosePoint: Codable, Identifiable, Hashable, Sendable {
    var time: Date
    var value: Double
    var id: TimeInterval { time.timeIntervalSinceReferenceDate }
}

struct GlucoseSnapshot: Codable, Equatable, Sendable {
    var value: Double
    var trendSymbol: String
    var timeInRange: Int
    var recent: [Double]
    var updatedAt: Date

    static let demo = GlucoseSnapshot(
        value: 118,
        trendSymbol: "arrow.up.right",
        timeInRange: 86,
        recent: [96, 102, 110, 128, 142, 136, 124, 118, 114, 116, 122, 130, 126, 118],
        updatedAt: Date()
    )
}

enum MealFood: String, Codable, CaseIterable, Identifiable, Sendable {
    case riceDal = "Rice & dal"
    case idliDosa = "Idli / dosa"
    case roti = "Roti & sabzi"
    case biryani = "Biryani"
    case salad = "Salad & curd"
    case somethingElse = "Something else"

    var id: String { rawValue }

    var localizedName: String {
        String(localized: String.LocalizationValue(stringLiteral: rawValue))
    }
}

enum GlucoseMath {
    /// Demo trace used until a CGM is connected. `days` > 1 gives the week
    /// view something to show; each day varies a little.
    static func simulated(endingAt now: Date = Date(), days: Int = 1) -> [GlucosePoint] {
        let events: [(hour: Double, amplitude: Double)] = [
            (3.5, -20), (8.5, 52), (13.0, 78), (16.5, 28), (20.5, 60)
        ]
        let steps = 96 * max(1, days)
        var points: [GlucosePoint] = []
        points.reserveCapacity(steps + 1)
        for index in -steps...0 {
            let time = now.addingTimeInterval(Double(index) * 900)
            let hour = hourOfDay(time)
            let dayIndex = Double(index + steps) / 96
            let dayScale = 1 + 0.18 * sin(floor(dayIndex) * 1.7)
            var value = 104 + 5 * sin(hour * 0.9) + 2 * sin(Double(index) * 1.7)
            for event in events {
                let delta = positiveMod(hour - event.hour, 24)
                if delta < 4 {
                    value += event.amplitude * dayScale * (delta / 0.9) * exp(1 - delta / 0.9)
                }
            }
            points.append(GlucosePoint(time: time, value: value))
        }
        return points
    }

    private static func hourOfDay(_ date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    private static func positiveMod(_ value: Double, _ modulus: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder < 0 ? remainder + modulus : remainder
    }
}

extension Array where Element == GlucosePoint {
    var currentValue: Double {
        last?.value ?? 0
    }

    var trendSymbol: String {
        guard count >= 2 else { return "arrow.right" }
        let delta = self[count - 1].value - self[count - 2].value
        if delta > 3 { return "arrow.up.right" }
        if delta < -3 { return "arrow.down.right" }
        return "arrow.right"
    }

    var timeInRange: Int {
        guard !isEmpty else { return 0 }
        let inside = filter { $0.value >= 70 && $0.value <= 180 }.count
        return Int((Double(inside) / Double(count) * 100).rounded())
    }

    var averageValue: Int {
        guard !isEmpty else { return 0 }
        let total = reduce(0) { $0 + $1.value }
        return Int((total / Double(count)).rounded())
    }

    var highReadings: Int {
        filter { $0.value > 180 }.count
    }

    var recentRise: Int {
        guard let end = last?.time else { return 0 }
        let window = filter { end.timeIntervalSince($0.time) <= 2 * 60 * 60 }
        guard let high = window.map(\.value).max(), let low = window.map(\.value).min() else { return 0 }
        return Int((high - low).rounded())
    }
}

extension GlucoseSnapshot {
    init(points: [GlucosePoint], updatedAt: Date = Date()) {
        self.value = points.currentValue
        self.trendSymbol = points.trendSymbol
        self.timeInRange = points.timeInRange
        self.recent = Array(points.suffix(24).map(\.value))
        self.updatedAt = updatedAt
    }
}
