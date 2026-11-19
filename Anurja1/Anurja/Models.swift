import Foundation
import SwiftUI

enum Stage: Equatable {
    case welcome, connect, dashboard, goal, main
}

enum AppTab: String, Codable, CaseIterable, Identifiable {
    case home, trends, meals, habits

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .trends: "Trends"
        case .meals: "Meals"
        case .habits: "Habits"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .trends: "chart.bar"
        case .meals: "fork.knife"
        case .habits: "leaf"
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable {
    case meals, habits

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .meals: "Understand my meals"
        case .habits: "Build gentler habits"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .meals: "Learn what keeps my energy steady"
        case .habits: "Find a rhythm I can sustain"
        }
    }

    var symbol: String {
        switch self {
        case .meals: "fork.knife"
        case .habits: "figure.walk"
        }
    }

    var shortTitle: LocalizedStringKey {
        switch self {
        case .meals: "Meals"
        case .habits: "Habits"
        }
    }
}

enum LinkState: Equatable {
    case idle, connecting, connected
}

enum MealDuration: String, Codable, CaseIterable, Identifiable {
    case quick = "Under 10 min"
    case medium = "10–20 min"
    case longer = "Longer"

    var id: String { rawValue }
    var localizedName: String { String(localized: String.LocalizationValue(stringLiteral: rawValue)) }
}

enum MealContext: String, Codable, CaseIterable, Identifiable {
    case desk = "At my desk"
    case screen = "Screen on"
    case move = "On the move"
    case walked = "Walked after"
    case lay = "Lay down after"

    var id: String { rawValue }
    var localizedName: String { String(localized: String.LocalizationValue(stringLiteral: rawValue)) }
}

enum Drink: String, Codable, CaseIterable, Identifiable {
    case tea = "Tea"
    case coffee = "Coffee"
    case juice = "Juice / soft drink"
    case water = "Water"

    var id: String { rawValue }
    var localizedName: String { String(localized: String.LocalizationValue(stringLiteral: rawValue)) }
}

enum Feeling: String, Codable, CaseIterable, Identifiable {
    case fine = "Fine"
    case heavy = "Heavy"
    case bloated = "Bloated"
    case acidity = "Acidity"
    case sleepy = "Sleepy"
    case hungry = "Hungry soon"

    var id: String { rawValue }
    var localizedName: String { String(localized: String.LocalizationValue(stringLiteral: rawValue)) }
}

enum Stress: String, Codable, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }
    var localizedName: String { String(localized: String.LocalizationValue(stringLiteral: rawValue)) }
}

enum DidIt: String, Codable, CaseIterable, Identifiable {
    case yes = "Yes"
    case little = "A little"
    case notToday = "Not today"

    var id: String { rawValue }
    var localizedName: String { String(localized: String.LocalizationValue(stringLiteral: rawValue)) }
}

enum HabitFeel: String, Codable, CaseIterable, Identifiable {
    case fine = "Fine"
    case lighter = "Lighter"
    case same = "Same"
    case heavy = "Heavy"
    case sleepy = "Sleepy"

    var id: String { rawValue }
    var localizedName: String { String(localized: String.LocalizationValue(stringLiteral: rawValue)) }
}

enum Effort: String, Codable, CaseIterable, Identifiable {
    case easy = "Easy"
    case okay = "Okay"
    case hard = "Hard"

    var id: String { rawValue }
    var localizedName: String { String(localized: String.LocalizationValue(stringLiteral: rawValue)) }
}

enum ExerciseKind: String, Codable, CaseIterable, Identifiable {
    case squat, curl, press

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .squat: "Bodyweight squat"
        case .curl: "Arm curl"
        case .press: "Overhead press"
        }
    }

    var blurb: LocalizedStringKey {
        switch self {
        case .squat: "Big leg muscles soak up glucose. Side-on to the camera."
        case .curl: "Light weights or a water bottle. Face the camera."
        case .press: "Hands at shoulders, press up. Face the camera."
        }
    }

    var symbol: String {
        switch self {
        case .squat: "figure.strengthtraining.functional"
        case .curl: "dumbbell"
        case .press: "figure.arms.open"
        }
    }

    var cues: [LocalizedStringKey] {
        switch self {
        case .squat:
            ["Feet shoulder-width", "Sit back and down", "Chest tall", "Stand up fully"]
        case .curl:
            ["Elbows by your sides", "Curl up slowly", "Squeeze at the top", "Lower with control"]
        case .press:
            ["Hands at shoulders", "Press straight up", "Arms fully straight", "Lower to shoulders"]
        }
    }

    var extendedAngle: Double {
        switch self {
        case .squat: 160
        case .curl: 150
        case .press: 160
        }
    }

    var depthAngle: Double {
        switch self {
        case .squat: 100
        case .curl: 55
        case .press: 85
        }
    }

    var furtherCue: String {
        switch self {
        case .squat: String(localized: "Go a little lower next time")
        case .curl: String(localized: "Curl a bit higher")
        case .press: String(localized: "Lower your hands to shoulder level")
        }
    }

    var goodCue: String {
        switch self {
        case .squat: String(localized: "Good depth, now stand tall")
        case .curl: String(localized: "Nice squeeze, lower slowly")
        case .press: String(localized: "Strong press, lower back down")
        }
    }

    func simulatedAngle(elapsed: TimeInterval) -> Double {
        let period = 4.0
        let phase = elapsed.truncatingRemainder(dividingBy: period) / period
        let cycle = Int(elapsed / period) + 1
        let shallow = cycle % 4 == 0
        let standing = extendedAngle + 5
        let bottom = shallow ? (extendedAngle + depthAngle) / 2 + 6 : depthAngle - 4
        return bottom + (standing - bottom) * (1 + cos(2 * Double.pi * phase)) / 2
    }
}

struct MealLog: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var food: MealFood
    var duration: MealDuration
    var contexts: Set<MealContext>
    var drink: Drink?
    var sugarSpoons: Int
    var feelings: Set<Feeling>
    var sleepHours: Double
    var stress: Stress
    var rise: Int
    var carbsGrams: Int?
    var insulinUnits: Double?
    var sourceID: String?

    static let samples: [MealLog] = [
        MealLog(date: .distantPastOffset(6), food: .roti, duration: .medium, contexts: [.walked], drink: .water, sugarSpoons: 0, feelings: [.fine], sleepHours: 7.5, stress: .low, rise: 22, carbsGrams: 40, insulinUnits: nil, sourceID: nil),
        MealLog(date: .distantPastOffset(5), food: .salad, duration: .quick, contexts: [.move], drink: .water, sugarSpoons: 0, feelings: [.fine], sleepHours: 7, stress: .low, rise: 28, carbsGrams: nil, insulinUnits: nil, sourceID: nil),
        MealLog(date: .distantPastOffset(4), food: .riceDal, duration: .medium, contexts: [.desk], drink: .tea, sugarSpoons: 1, feelings: [.heavy], sleepHours: 6.5, stress: .medium, rise: 48, carbsGrams: 70, insulinUnits: 4, sourceID: nil),
        MealLog(date: .distantPastOffset(3), food: .somethingElse, duration: .longer, contexts: [.desk, .screen], drink: .coffee, sugarSpoons: 0, feelings: [.sleepy], sleepHours: 5.5, stress: .medium, rise: 55, carbsGrams: nil, insulinUnits: nil, sourceID: nil),
        MealLog(date: .distantPastOffset(2), food: .idliDosa, duration: .quick, contexts: [.screen], drink: .coffee, sugarSpoons: 0, feelings: [.hungry], sleepHours: 6, stress: .high, rise: 69, carbsGrams: 55, insulinUnits: 3, sourceID: nil),
        MealLog(date: .distantPastOffset(1), food: .biryani, duration: .longer, contexts: [.lay], drink: .juice, sugarSpoons: 0, feelings: [.bloated, .sleepy], sleepHours: 5, stress: .high, rise: 72, carbsGrams: 90, insulinUnits: 6, sourceID: nil)
    ]

    static var previewToday: MealLog {
        MealLog(
            date: Date(),
            food: .riceDal,
            duration: .quick,
            contexts: [.desk, .screen],
            drink: .juice,
            sugarSpoons: 1,
            feelings: [.heavy, .sleepy],
            sleepHours: 5,
            stress: .high,
            rise: 64,
            carbsGrams: 80,
            insulinUnits: 5
        )
    }
}

private extension Date {
    static func distantPastOffset(_ days: Int) -> Date {
        Date().addingTimeInterval(-86400 * Double(days))
    }
}

struct HabitCheckIn: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var did: DidIt
    var feel: HabitFeel
    var effort: Effort
}

struct CoachSession: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var exercise: ExerciseKind
    var reps: Int
}

struct HabitPlan: Codable, Hashable {
    var variant: Int = 0
    var startMinutes: Int = 5
    var growMinutes: Int = 10
    var timesThisWeek: Int = 3

    var title: String {
        switch variant {
        case 1:
            return String(localized: "10 squats before dinner")
        case 2:
            return String(localized: "A glass of water before meals")
        default:
            return String(localized: "A \(startMinutes)-minute walk after lunch")
        }
    }

    var reason: LocalizedStringKey {
        switch variant {
        case 1:
            "Big leg muscles use glucose well. Short, guided sets are an easy way in."
        case 2:
            "A tiny pre-meal pause slows the first bites and is easy to repeat."
        default:
            "You eat at your desk and the canteen sets the menu, so we start after the meal."
        }
    }

    var startText: String {
        if variant == 1 {
            return setText(max(1, startMinutes / 5))
        }
        return String(localized: "\(startMinutes) minutes")
    }

    var growText: String {
        if variant == 1 {
            return setText(max(2, growMinutes / 5))
        }
        return String(localized: "\(growMinutes) minutes")
    }

    private func setText(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 set")
        }
        return String(localized: "\(count) sets")
    }
}
