import Foundation

struct InsightItem: Identifiable, Hashable {
    var symbol: String
    var title: String
    var detail: String
    var weight: Int
    var id: String { title }
}

struct MealInsight: Hashable {
    var title: String
    var items: [InsightItem]
    var suggestions: [String]
}

protocol InsightProviding {
    func insight(for meal: MealLog) -> MealInsight
}

struct RuleInsightEngine: InsightProviding {
    func insight(for meal: MealLog) -> MealInsight {
        var items: [InsightItem] = []
        var suggestions: [String] = []

        if meal.duration == .quick {
            items.append(InsightItem(
                symbol: "hare",
                title: String(localized: "Eaten quickly"),
                detail: String(localized: "Meals under 10 minutes tend to give a faster, higher rise."),
                weight: 2
            ))
            suggestions.append(String(localized: "Put your fork down between bites; aim for 15 minutes."))
        }
        if meal.contexts.contains(.screen) || meal.contexts.contains(.move) {
            items.append(InsightItem(
                symbol: "iphone",
                title: String(localized: "Distracted eating"),
                detail: String(localized: "Screens and eating on the move make it easier to miss fullness cues."),
                weight: 1
            ))
            suggestions.append(String(localized: "Keep screens away for the first five minutes of the meal."))
        }
        if meal.sugarSpoons > 0 || meal.drink == .juice {
            items.append(InsightItem(
                symbol: "drop",
                title: String(localized: "Sweet drink with the meal"),
                detail: String(localized: "Sugar in tea, juice or soft drinks reaches your blood quickly."),
                weight: 3
            ))
            suggestions.append(String(localized: "Swap the sweet drink for water or unsweetened tea with this meal."))
        }
        if meal.contexts.contains(.lay) {
            items.append(InsightItem(
                symbol: "bed.double",
                title: String(localized: "Lying down right after"),
                detail: String(localized: "Staying still gives your muscles no chance to use the glucose."),
                weight: 2
            ))
        }
        if meal.contexts.contains(.walked) {
            items.append(InsightItem(
                symbol: "figure.walk",
                title: String(localized: "You walked afterwards"),
                detail: String(localized: "Light movement after eating usually flattens the curve. Nicely done."),
                weight: 1
            ))
        } else {
            suggestions.append(String(localized: "Take a 5-minute walk within 30 minutes after eating."))
        }
        if meal.sleepHours < 6 {
            items.append(InsightItem(
                symbol: "moon",
                title: String(localized: "Short sleep"),
                detail: String(localized: "A night under 6 hours can make your body respond less smoothly to food."),
                weight: 2
            ))
        }
        if meal.stress == .high {
            items.append(InsightItem(
                symbol: "waveform.path",
                title: String(localized: "High stress today"),
                detail: String(localized: "Stress hormones can nudge glucose up on their own."),
                weight: 2
            ))
            suggestions.append(String(localized: "Three slow breaths before eating can help you settle."))
        }
        if meal.food == .biryani || meal.food == .riceDal || meal.food == .idliDosa {
            suggestions.append(String(localized: "Add vegetables or curd and eat them first, then the rice."))
        }
        if items.isEmpty {
            items.append(InsightItem(
                symbol: "checkmark.circle",
                title: String(localized: "Nothing stands out"),
                detail: String(localized: "This meal looks balanced. We will keep learning your pattern."),
                weight: 1
            ))
        }

        return MealInsight(title: Self.riseTitle(meal.rise), items: items, suggestions: Array(suggestions.prefix(4)))
    }

    static func riseTitle(_ rise: Int) -> String {
        if rise < 30 { return String(localized: "A gentle rise") }
        if rise < 55 { return String(localized: "A moderate rise") }
        return String(localized: "A sharp rise")
    }
}
