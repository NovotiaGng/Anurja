import Foundation

/// A one-hidden-layer ReLU network exported from scikit-learn
/// (backend/ml/train.py writes the weights into GeneratedModel.swift).
struct DenseNetwork {
    let mean: [Double]
    let scale: [Double]
    /// [input][hidden]
    let hiddenWeights: [[Double]]
    let hiddenBias: [Double]
    /// [hidden][output]
    let outputWeights: [[Double]]
    let outputBias: [Double]

    func forward(_ input: [Double]) -> [Double] {
        var hidden = hiddenBias
        for i in 0..<min(input.count, hiddenWeights.count) {
            let z = (input[i] - mean[i]) / (scale[i] == 0 ? 1 : scale[i])
            let row = hiddenWeights[i]
            for j in 0..<hidden.count {
                hidden[j] += z * row[j]
            }
        }
        var output = outputBias
        for j in 0..<hidden.count {
            let activation = max(0, hidden[j])
            guard activation > 0 else { continue }
            let row = outputWeights[j]
            for k in 0..<output.count {
                output[k] += activation * row[k]
            }
        }
        return output
    }

    func softmax(_ input: [Double]) -> [Double] {
        let logits = forward(input)
        let top = logits.max() ?? 0
        let exps = logits.map { Foundation.exp($0 - top) }
        let total = exps.reduce(0, +)
        return exps.map { $0 / total }
    }
}

// MARK: - Results

struct RisePrediction: Equatable {
    var rise: Int
    var populationRise: Int
    var personalisedFrom: Int
    var source: Source

    enum Source: Equatable { case device, server }

    var band: String { RuleInsightEngine.riseTitle(rise) }
}

enum ActivityStatus: String, CaseIterable {
    case inRange = "in_range"
    case rising
    case high
    case low

    var title: String {
        switch self {
        case .inRange: String(localized: "You're in your target range")
        case .rising: String(localized: "Heading towards your upper target")
        case .high: String(localized: "Above your target range")
        case .low: String(localized: "Below your target range")
        }
    }

    var symbol: String {
        switch self {
        case .inRange: "checkmark.circle"
        case .rising: "arrow.up.right"
        case .high: "arrow.up"
        case .low: "arrow.down"
        }
    }

    var needsAttention: Bool { self == .high || self == .low }
}

struct ActivityAction: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
}

struct ActivityRecommendation: Equatable {
    var status: ActivityStatus
    var confidence: Double
    var fasting: Bool
    var targetLow: Int
    var targetHigh: Int
    var actions: [ActivityAction]
    var personalNote: String?

    var targetText: String {
        fasting
            ? String(localized: "Fasting target \(targetLow)–\(targetHigh) mg/dL")
            : String(localized: "After-meal target under \(targetHigh) mg/dL")
    }
}

struct FoodScore: Identifiable, Hashable {
    var item: FoodItem
    var rise: Int
    var id: String { item.id }
}

struct FoodComparison: Identifiable, Hashable {
    var item: FoodItem
    var averageRise: Int
    var count: Int
    var swap: FoodScore?
    var id: String { item.id }
    var saving: Int? { swap.map { averageRise - $0.rise } }
}

struct HabitEffect: Identifiable, Hashable {
    var context: MealContext
    var withAverage: Int
    var withoutAverage: Int
    var id: String { context.rawValue }
    var delta: Int { withAverage - withoutAverage }
}

struct WhatHelps: Equatable {
    var steadyFoods: [FoodScore]
    var snack: FoodScore?
    var comparisons: [FoodComparison]
    var habits: [HabitEffect]
    var personalisedFrom: Int
}

// MARK: - Engine

enum MLEngine {
    // Feature order must match backend/anurja_api/features.py (RISE_FEATURES).
    static func riseFeatures(
        item: FoodItem,
        servings: Double,
        carbsGrams: Int?,
        duration: MealDuration,
        contexts: Set<MealContext>,
        drink: Drink?,
        sugarSpoons: Int,
        sleepHours: Double,
        stress: Stress,
        hour: Int
    ) -> [Double] {
        let carbs = carbsGrams.map(Double.init) ?? item.carbs * servings
        let stressLevel: Double
        switch stress {
        case .low: stressLevel = 0
        case .medium: stressLevel = 1
        case .high: stressLevel = 2
        }
        return [
            carbs,
            carbs * item.gi / 100,
            item.fiber * servings,
            item.protein * servings,
            item.fat * servings,
            duration == .quick ? 1 : 0,
            duration == .longer ? 1 : 0,
            contexts.contains(.desk) ? 1 : 0,
            contexts.contains(.screen) ? 1 : 0,
            contexts.contains(.move) ? 1 : 0,
            contexts.contains(.walked) ? 1 : 0,
            contexts.contains(.lay) ? 1 : 0,
            drink == .juice ? 1 : 0,
            Double(sugarSpoons),
            max(0, 7 - sleepHours),
            stressLevel,
            (5..<11).contains(hour) ? 1 : 0
        ]
    }

    static func features(for meal: MealLog) -> [Double] {
        riseFeatures(
            item: meal.foodItem,
            servings: meal.servings ?? 1,
            carbsGrams: meal.carbsGrams,
            duration: meal.duration,
            contexts: meal.contexts,
            drink: meal.drink,
            sugarSpoons: meal.sugarSpoons,
            sleepHours: meal.sleepHours,
            stress: meal.stress,
            hour: Calendar.current.component(.hour, from: meal.date)
        )
    }

    static func populationRise(_ features: [Double]) -> Double {
        max(0, GeneratedModels.rise.forward(features).first ?? 0)
    }

    static func predictRise(for meal: MealLog, history: [MealLog]) -> RisePrediction {
        let raw = populationRise(features(for: meal))
        let person = Personaliser(meals: history)
        let value = max(0, person.adjust(foodID: meal.foodItem.id, raw: raw))
        return RisePrediction(
            rise: Int(value.rounded()),
            populationRise: Int(raw.rounded()),
            personalisedFrom: person.count,
            source: .device
        )
    }

    // MARK: Activity

    static func recommendActivity(
        points: [GlucosePoint],
        lastMeal: Date?,
        stepsLastHour: Int,
        meals: [MealLog],
        checkIns: [HabitCheckIn],
        sessions: [CoachSession],
        now: Date = Date()
    ) -> ActivityRecommendation {
        let glucose = points.currentValue
        let slope = points.slopePerFiveMinutes
        let minutes = lastMeal.map { max(0, now.timeIntervalSince($0) / 60) } ?? 600
        let fasting = minutes >= 240
        let hour = Double(Calendar.current.component(.hour, from: now)) + Double(Calendar.current.component(.minute, from: now)) / 60
        let angle = 2 * Double.pi * hour / 24
        let input = [glucose, slope, min(minutes, 600) / 60, fasting ? 1 : 0, Double(stepsLastHour) / 1000, sin(angle), cos(angle)]
        let probabilities = GeneratedModels.activity.softmax(input)
        let best = probabilities.indices.max { probabilities[$0] < probabilities[$1] } ?? 0
        var status = ActivityStatus(rawValue: GeneratedModels.activityClasses[best]) ?? .inRange
        // Safety net: never let the model talk someone out of a real low.
        if glucose < GlucoseTargets.low { status = .low }
        let targetHigh = fasting ? Int(GlucoseTargets.fasting.upperBound) : Int(GlucoseTargets.afterMealMax)
        var suggested = Self.actions(for: status)
        var note: String?
        if status == .high || status == .rising {
            let effect = personalEffects(points: points, checkIns: checkIns, sessions: sessions)
            if let walk = effect.walk, let move = effect.exercise, move > walk {
                let strength: Set<String> = ["squats", "stairs"]
                suggested = suggested.filter { strength.contains($0.id) } + suggested.filter { !strength.contains($0.id) }
                note = String(localized: "For you, short strength sets have lowered glucose about \(move) mg/dL.")
            } else if let walk = effect.walk {
                note = String(localized: "When you walked before, your glucose came down about \(walk) mg/dL.")
            }
        }
        return ActivityRecommendation(
            status: status,
            confidence: probabilities[best],
            fasting: fasting,
            targetLow: Int(GlucoseTargets.fasting.lowerBound),
            targetHigh: targetHigh,
            actions: suggested,
            personalNote: note
        )
    }

    static func actions(for status: ActivityStatus) -> [ActivityAction] {
        switch status {
        case .high:
            [
                ActivityAction(id: "brisk_walk", title: String(localized: "Brisk walk, 10–15 minutes"), detail: String(localized: "Working muscles pull glucose out of your blood."), symbol: "figure.walk"),
                ActivityAction(id: "stairs", title: String(localized: "Climb stairs for 5 minutes"), detail: String(localized: "Short, strong bursts help bring it down."), symbol: "figure.stairs"),
                ActivityAction(id: "water", title: String(localized: "Drink a glass of water"), detail: String(localized: "Staying hydrated helps your body clear extra glucose."), symbol: "drop")
            ]
        case .rising:
            [
                ActivityAction(id: "light_walk", title: String(localized: "Light walk, 5–10 minutes"), detail: String(localized: "A short walk now can flatten the rise."), symbol: "figure.walk"),
                ActivityAction(id: "squats", title: String(localized: "10 slow squats"), detail: String(localized: "Big leg muscles soak up glucose."), symbol: "figure.strengthtraining.functional"),
                ActivityAction(id: "water", title: String(localized: "Drink a glass of water"), detail: String(localized: "Skip sweet drinks for now."), symbol: "drop")
            ]
        case .low:
            [
                ActivityAction(id: "fast_carbs", title: String(localized: "Eat 15 g of quick carbs"), detail: String(localized: "Half a glass of juice, 3 glucose tablets or 1 tbsp sugar."), symbol: "cup.and.saucer"),
                ActivityAction(id: "rest", title: String(localized: "Sit down and rest"), detail: String(localized: "Recheck in 15 minutes. Follow your care team's plan."), symbol: "chair")
            ]
        case .inRange:
            [
                ActivityAction(id: "keep_going", title: String(localized: "Keep doing what you're doing"), detail: String(localized: "A short walk after your next meal keeps it steady."), symbol: "leaf")
            ]
        }
    }

    /// How much glucose fell in the 45 minutes after this person's walks and
    /// strength sessions. Learned from their own data, used to rank actions.
    static func personalEffects(points: [GlucosePoint], checkIns: [HabitCheckIn], sessions: [CoachSession]) -> (walk: Int?, exercise: Int?) {
        func drop(after date: Date) -> Double? {
            let start = points.filter { abs($0.time.timeIntervalSince(date)) <= 10 * 60 }.map(\.value).first
            let later = points.filter { $0.time > date && $0.time.timeIntervalSince(date) <= 45 * 60 }.map(\.value).min()
            guard let start, let later else { return nil }
            return start - later
        }
        let walks = checkIns.filter { $0.did != .notToday }.compactMap { drop(after: $0.date) }
        let sets = sessions.compactMap { drop(after: $0.date) }
        let average: ([Double]) -> Int? = { values in
            values.count >= 2 ? Int((values.reduce(0, +) / Double(values.count)).rounded()) : nil
        }
        return (average(walks), average(sets))
    }

    // MARK: What helps you

    static func whatHelps(meals: [MealLog], profile: UserProfile) -> WhatHelps {
        let person = Personaliser(meals: meals)
        let typical: (FoodItem) -> [Double] = { item in
            riseFeatures(item: item, servings: 1, carbsGrams: nil, duration: .medium, contexts: [], drink: .water, sugarSpoons: 0, sleepHours: 7, stress: .medium, hour: 13)
        }
        let scored = FoodLibrary.all
            .filter { $0.isSafe(for: profile) }
            .map { item in
                FoodScore(item: item, rise: Int(max(0, person.adjust(foodID: item.id, raw: populationRise(typical(item)))).rounded()))
            }
            .sorted { $0.rise < $1.rise }
        let mains = scored.filter { !["Snacks", "Drinks", "Sweets", "Fruits"].contains($0.item.category) }
        let snack = scored.first { $0.item.category == "Snacks" }

        var grouped: [String: [Int]] = [:]
        for meal in meals {
            grouped[meal.foodItem.id, default: []].append(meal.rise)
        }
        let comparisons = grouped.compactMap { id, rises -> FoodComparison? in
            guard let item = FoodLibrary.item(id: id) else { return nil }
            let average = Int((Double(rises.reduce(0, +)) / Double(rises.count)).rounded())
            let swap = scored.first { $0.item.category == item.category && $0.item.id != id && $0.rise < average }
            return FoodComparison(item: item, averageRise: average, count: rises.count, swap: swap)
        }
        .sorted { $0.averageRise > $1.averageRise }

        let habits = MealContext.allCases.compactMap { context -> HabitEffect? in
            let with = meals.filter { $0.contexts.contains(context) }.map(\.rise)
            let without = meals.filter { !$0.contexts.contains(context) }.map(\.rise)
            guard !with.isEmpty, !without.isEmpty else { return nil }
            return HabitEffect(
                context: context,
                withAverage: Int((Double(with.reduce(0, +)) / Double(with.count)).rounded()),
                withoutAverage: Int((Double(without.reduce(0, +)) / Double(without.count)).rounded())
            )
        }
        .sorted { $0.delta < $1.delta }

        return WhatHelps(
            steadyFoods: Array(mains.prefix(4)),
            snack: snack,
            comparisons: Array(comparisons.prefix(4)),
            habits: habits,
            personalisedFrom: person.count
        )
    }
}

/// Per-person correction learned from logged meals: for each meal we know
/// the real rise from the sensor, so actual minus predicted shows how this
/// person reacts compared with the population model. Shrunk towards zero
/// until there is enough data. Mirrors backend/anurja_api/ml.py.
struct Personaliser {
    private(set) var count = 0
    private var foodAdjust: [String: Double] = [:]
    private var userAdjust = 0.0

    init(meals: [MealLog]) {
        guard !meals.isEmpty else { return }
        var residuals: [String: [Double]] = [:]
        for meal in meals {
            let predicted = MLEngine.populationRise(MLEngine.features(for: meal))
            residuals[meal.foodItem.id, default: []].append(Double(meal.rise) - predicted)
        }
        let all = residuals.values.flatMap { $0 }
        count = all.count
        userAdjust = all.reduce(0, +) / (Double(all.count) + 5)
        for (id, values) in residuals {
            foodAdjust[id] = values.reduce(0, +) / (Double(values.count) + 3)
        }
    }

    func adjust(foodID: String, raw: Double) -> Double {
        raw + (foodAdjust[foodID] ?? userAdjust)
    }
}
