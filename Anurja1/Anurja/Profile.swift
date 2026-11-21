import Foundation
import SwiftUI

// MARK: - Personalisation

enum Allergy: String, Codable, CaseIterable, Identifiable {
    case nuts, peanut, dairy, gluten, egg, soy, seafood

    var id: String { rawValue }

    /// Shown as checkboxes in onboarding; the rest stay selectable via Add Custom.
    static let common: [Allergy] = [.nuts, .peanut, .dairy, .gluten]

    var title: String {
        switch self {
        case .nuts: String(localized: "Tree nuts")
        case .peanut: String(localized: "Peanuts")
        case .dairy: String(localized: "Dairy / lactose")
        case .gluten: String(localized: "Gluten / wheat")
        case .egg: String(localized: "Eggs")
        case .soy: String(localized: "Soy")
        case .seafood: String(localized: "Fish & seafood")
        }
    }
}

enum InsulinType: String, Codable, CaseIterable, Identifiable {
    case rapid, basal, both, pump

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .rapid: "Rapid-acting"
        case .basal: "Long-acting (basal)"
        case .both: "Both"
        case .pump: "Insulin pump"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .rapid: "Taken around meals"
        case .basal: "Once or twice a day"
        case .both: "Basal plus meal-time doses"
        case .pump: "Continuous delivery"
        }
    }

    var symbol: String {
        switch self {
        case .rapid: "bolt.heart"
        case .basal: "clock"
        case .both: "square.stack"
        case .pump: "cross.vial"
        }
    }
}

enum MedicineTiming: String, Codable, CaseIterable, Identifiable {
    case morning = "Morning"
    case withMeals = "With meals"
    case night = "Night"
    case twice = "Twice a day"

    var id: String { rawValue }
    var localizedName: String { String(localized: String.LocalizationValue(stringLiteral: rawValue)) }
}

struct Medicine: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var dose: String = ""
    var timing: MedicineTiming = .morning

    static let common = ["Metformin", "Glimepiride", "Sitagliptin", "Vildagliptin", "Empagliflozin", "Dapagliflozin", "Pioglitazone", "Teneligliptin"]
}

struct UserProfile: Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var age: Int = 35
    var heightCm: Double = 165
    var weightKg: Double = 65
    var allergies: Set<Allergy> = []
    var otherAllergy: String = ""
    var takesInsulin: Bool = false
    var insulinType: InsulinType?
    var medicines: [Medicine] = []
    var carbTarget: Int = 150
    var activityAlerts: Bool = true

    var bmi: Double {
        let metres = heightCm / 100
        guard metres > 0 else { return 0 }
        return weightKg / (metres * metres)
    }

    /// Asian-Indian BMI cut-offs (WHO expert consultation).
    var bmiLabel: String {
        switch bmi {
        case ..<18.5: String(localized: "Below the healthy range")
        case ..<23: String(localized: "Healthy range")
        case ..<25: String(localized: "Slightly above")
        default: String(localized: "Above the healthy range")
        }
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? ""
    }

    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "A" : String(letters).uppercased()
    }

    var allergenTags: Set<String> {
        Set(allergies.map(\.rawValue))
    }
}

// MARK: - Insulin

enum InsulinRelation: String, Codable, CaseIterable, Identifiable {
    case preMeal = "pre_meal"
    case postMeal = "post_meal"
    case activity = "activity"
    case standalone = "standalone"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preMeal: String(localized: "Before a meal")
        case .postMeal: String(localized: "After a meal")
        case .activity: String(localized: "Around activity")
        case .standalone: String(localized: "Not linked")
        }
    }
}

struct InsulinLog: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var units: Double
    var relation: InsulinRelation
    var mealID: UUID?
    var note: String?
}

struct InsulinLink: Equatable {
    var relation: InsulinRelation
    var meal: MealLog?
    var minutes: Int
    var explanation: String
}

enum InsulinLinker {
    /// Matches a dose to what happened around it: a meal up to 45 min after
    /// the dose is "before a meal", a meal up to 2 h before it is "after a
    /// meal", otherwise exercise or a walk within an hour is "around activity".
    static func link(dose: Date, meals: [MealLog], sessions: [CoachSession], checkIns: [HabitCheckIn]) -> InsulinLink {
        let before = meals
            .map { ($0, $0.date.timeIntervalSince(dose) / 60) }
            .filter { $0.1 >= 0 && $0.1 <= 45 }
            .min { $0.1 < $1.1 }
        let after = meals
            .map { ($0, dose.timeIntervalSince($0.date) / 60) }
            .filter { $0.1 >= 0 && $0.1 <= 120 }
            .min { $0.1 < $1.1 }
        let food: (MealLog) -> String = { $0.displayName }
        if let before, before.1 <= (after?.1 ?? .infinity) {
            let minutes = Int(before.1.rounded())
            return InsulinLink(
                relation: .preMeal,
                meal: before.0,
                minutes: minutes,
                explanation: String(localized: "Taken \(minutes) min before \(food(before.0))")
            )
        }
        if let after {
            let minutes = Int(after.1.rounded())
            return InsulinLink(
                relation: .postMeal,
                meal: after.0,
                minutes: minutes,
                explanation: String(localized: "Taken \(minutes) min after \(food(after.0))")
            )
        }
        let activityDates = sessions.map(\.date) + checkIns.filter { $0.did != .notToday }.map(\.date)
        if let nearest = activityDates.map({ abs($0.timeIntervalSince(dose)) / 60 }).filter({ $0 <= 60 }).min() {
            let minutes = Int(nearest.rounded())
            return InsulinLink(
                relation: .activity,
                meal: nil,
                minutes: minutes,
                explanation: String(localized: "Within \(minutes) min of your exercise")
            )
        }
        return InsulinLink(
            relation: .standalone,
            meal: nil,
            minutes: 0,
            explanation: String(localized: "No meal or activity close by")
        )
    }
}

// MARK: - Targets and glucose maths

enum GlucoseTargets {
    static let fasting: ClosedRange<Double> = 70...130
    static let afterMealMax: Double = 180
    static let low: Double = 70

    /// Glucose Management Indicator (Bergenstal et al., 2018).
    static func gmi(meanGlucose: Double) -> Double {
        3.31 + 0.02392 * meanGlucose
    }
}

enum TimeRange: String, CaseIterable, Identifiable, Codable {
    case twelve, day, week

    var id: String { rawValue }

    var hours: Double {
        switch self {
        case .twelve: 12
        case .day: 24
        case .week: 24 * 7
        }
    }

    var title: String {
        switch self {
        case .twelve: String(localized: "12 hr")
        case .day: String(localized: "24 hr")
        case .week: String(localized: "1 week")
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .twelve: "Last 12 hours"
        case .day: "Last 24 hours"
        case .week: "Last 7 days"
        }
    }
}

struct GlucosePeak {
    var point: GlucosePoint
    var change: Int
    var meal: MealLog?
}

extension Array where Element == GlucosePoint {
    func within(hours: Double, of end: Date? = nil) -> [GlucosePoint] {
        guard let anchor = end ?? last?.time else { return [] }
        return filter { anchor.timeIntervalSince($0.time) <= hours * 3600 && $0.time <= anchor }
    }

    var meanValue: Double {
        guard !isEmpty else { return 0 }
        return reduce(0) { $0 + $1.value } / Double(count)
    }

    /// Change in mg/dL per 5 minutes over the last 30 minutes.
    var slopePerFiveMinutes: Double {
        let window = within(hours: 0.5)
        guard let first = window.first, let last = window.last, last.time > first.time else { return 0 }
        let minutes = last.time.timeIntervalSince(first.time) / 60
        return (last.value - first.value) / minutes * 5
    }

    func highestPeak(meals: [MealLog]) -> GlucosePeak? {
        guard let top = self.max(by: { $0.value < $1.value }) else { return nil }
        let before = filter { top.time.timeIntervalSince($0.time) <= 2 * 3600 && $0.time <= top.time }
        let base = before.map(\.value).min() ?? top.value
        let meal = meals
            .filter { top.time.timeIntervalSince($0.date) >= 0 && top.time.timeIntervalSince($0.date) <= 3 * 3600 }
            .max { $0.date < $1.date }
        return GlucosePeak(point: top, change: Int((top.value - base).rounded()), meal: meal)
    }

    func lowestPeak() -> GlucosePeak? {
        guard let bottom = self.min(by: { $0.value < $1.value }) else { return nil }
        let before = filter { bottom.time.timeIntervalSince($0.time) <= 2 * 3600 && $0.time < bottom.time }
        let base = before.isEmpty ? bottom.value : before.meanValue
        return GlucosePeak(point: bottom, change: Int((bottom.value - base).rounded()), meal: nil)
    }
}

// MARK: - Reminders and sync

enum ReminderSlot: String, Codable, CaseIterable, Identifiable {
    case nextMeal, tomorrowMorning, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextMeal: String(localized: "Next meal")
        case .tomorrowMorning: String(localized: "Tomorrow morning")
        case .off: String(localized: "Off")
        }
    }
}

enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced(Date, Int)
    case offline(String)

    var label: String {
        switch self {
        case .idle: String(localized: "Not synced yet")
        case .syncing: String(localized: "Syncing…")
        case let .synced(date, count):
            String(localized: "Synced \(date.formatted(date: .omitted, time: .shortened)) · \(count) records")
        case let .offline(reason): String(localized: "Saved on this phone. Server unavailable: \(reason)")
        }
    }
}
