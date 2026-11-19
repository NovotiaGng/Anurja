import Charts
import SwiftUI

private enum MealPane: String, CaseIterable, Identifiable {
    case log, pattern
    var id: String { rawValue }
    var title: String {
        switch self {
        case .log: String(localized: "Log a meal")
        case .pattern: String(localized: "How I eat")
        }
    }
}

private struct MealDraft {
    var food: MealFood = .riceDal
    var duration: MealDuration = .medium
    var contexts: Set<MealContext> = [.desk]
    var drink: Drink? = .water
    var sugar = 0
    var feelings: Set<Feeling> = []
    var carbs = 0
    var insulin = 0.0
    var sleep = 5.5
    var stress: Stress = .medium
}

struct MealsView: View {
    @EnvironmentObject private var state: AppState
    @State private var pane: MealPane = .log
    @State private var draft = MealDraft()
    @State private var appliedSleep = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(
                    title: "Understand my meals",
                    subtitle: "Tell us what you eat and how it sits with you. No right answers, nothing to fix."
                )
                SegmentedTabs(options: MealPane.allCases, title: { $0.title }, selection: $pane)
                if pane == .log {
                    logForm
                } else {
                    pattern
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .onAppear(perform: applyHealthSleep)
        .onChange(of: state.healthSleepHours) { _, _ in
            applyHealthSleep()
        }
    }

    private var logForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What did you eat?")
                    .scaledFont(size: 17, weight: .bold)
                FlowLayout {
                    ForEach(MealFood.allCases) { food in
                        Chip(title: food.localizedName, selected: draft.food == food) {
                            draft.food = food
                        }
                    }
                }
            }
            .anurjaCard()

            FlowLayout {
                ForEach(MealDuration.allCases) { duration in
                    Chip(title: duration.localizedName, selected: draft.duration == duration) {
                        draft.duration = duration
                    }
                }
                ForEach(MealContext.allCases) { context in
                    Chip(title: context.localizedName, selected: draft.contexts.contains(context)) {
                        if draft.contexts.contains(context) {
                            draft.contexts.remove(context)
                        } else {
                            draft.contexts.insert(context)
                        }
                    }
                }
            }
            .anurjaCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("With the meal")
                    .scaledFont(size: 17, weight: .bold)
                FlowLayout {
                    ForEach(Drink.allCases) { drink in
                        Chip(title: drink.localizedName, selected: draft.drink == drink) {
                            draft.drink = draft.drink == drink ? nil : drink
                        }
                    }
                }
                StepperRow(
                    title: "Sugar, spoons",
                    value: draft.sugar.formatted(),
                    decreaseLabel: "Decrease sugar",
                    increaseLabel: "Increase sugar",
                    decrease: { draft.sugar = max(0, draft.sugar - 1) },
                    increase: { draft.sugar = min(6, draft.sugar + 1) }
                )
            }
            .anurjaCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("How do you feel now?")
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(Color.forest)
                Text("An hour or two after is best")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.muted)
                FlowLayout {
                    ForEach(Feeling.allCases) { feeling in
                        Chip(title: feeling.localizedName, selected: draft.feelings.contains(feeling), forest: true) {
                            if draft.feelings.contains(feeling) {
                                draft.feelings.remove(feeling)
                            } else {
                                draft.feelings.insert(feeling)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Carbs and insulin (optional)")
                    .scaledFont(size: 17, weight: .bold)
                StepperRow(
                    title: "Carbs, grams",
                    value: draft.carbs == 0 ? String(localized: "Not set") : draft.carbs.formatted(),
                    decreaseLabel: "Decrease carbs",
                    increaseLabel: "Increase carbs",
                    decrease: { draft.carbs = max(0, draft.carbs - 5) },
                    increase: { draft.carbs = min(200, draft.carbs + 5) }
                )
                StepperRow(
                    title: "Insulin taken, units",
                    value: draft.insulin == 0 ? String(localized: "Not set") : draft.insulin.formatted(.number.precision(.fractionLength(0...1))),
                    decreaseLabel: "Decrease insulin",
                    increaseLabel: "Increase insulin",
                    decrease: { draft.insulin = max(0, (draft.insulin - 0.5) * 2 / 2) },
                    increase: { draft.insulin = min(50, draft.insulin + 0.5) }
                )
                Text("Log only what you actually took. Anurja never suggests a dose.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .anurjaCard()

            VStack(alignment: .leading, spacing: 10) {
                Text("Around this meal")
                    .scaledFont(size: 17, weight: .bold)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        sleepBox
                        stressBox
                    }
                    VStack(spacing: 10) {
                        sleepBox
                        stressBox
                    }
                }
                FilledChip(title: String(localized: "From sensor: +\(state.points.recentRise)"))
            }
            .anurjaCard()

            PrimaryButton(title: "Save this meal", symbol: "chevron.right", action: save)
        }
    }

    private var sleepBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sleep last night")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
            Text(sleepLabel(draft.sleep))
                .scaledFont(size: 17, weight: .bold)
            HStack {
                Button {
                    draft.sleep = max(2, draft.sleep - 0.5)
                } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Decrease sleep"))
                Button {
                    draft.sleep = min(12, draft.sleep + 0.5)
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Increase sleep"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var stressBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stress today")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
            FlowLayout {
                ForEach(Stress.allCases) { stress in
                    Chip(title: stress.localizedName, selected: draft.stress == stress) {
                        draft.stress = stress
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var pattern: some View {
        let source = state.meals.isEmpty ? MealLog.samples : state.meals
        let bars = habitBars(from: source)
        let overall = source.isEmpty ? 0 : Int((Double(source.map(\.rise).reduce(0, +)) / Double(source.count)).rounded())
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Average rise by habit")
                    .scaledFont(size: 17, weight: .bold)
                if bars.isEmpty {
                    Text("Nothing logged yet. Tap + to log a meal.")
                        .scaledFont(size: 14)
                        .foregroundStyle(Color.muted)
                } else {
                    Chart {
                        ForEach(bars) { bar in
                            BarMark(
                                x: .value("Rise", bar.average),
                                y: .value("Habit", bar.name)
                            )
                            .foregroundStyle(bar.average > overall ? Color.terracotta : Color.forest)
                            .cornerRadius(4)
                        }
                        RuleMark(x: .value("Average", overall))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.muted)
                    }
                    .chartXScale(domain: 0...max(80, bars.map(\.average).max() ?? 80))
                    .frame(height: CGFloat(bars.count) * 48 + 24)
                    .accessibilityLabel(Text("Average rise by habit"))
                }
                Text("Based on \(source.count) meals; sample meals fill in until you've logged your own.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .anurjaCard()

            if let low = bars.min(by: { $0.average < $1.average }),
               let high = bars.max(by: { $0.average < $1.average }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your pattern")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                    Text("Meals with “\(low.name)” rise about +\(low.average), while “\(high.name)” average +\(high.average).")
                        .scaledFont(size: 16)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sand.opacity(0.65), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func habitBars(from meals: [MealLog]) -> [HabitBar] {
        MealContext.allCases.compactMap { context in
            let rows = meals.filter { $0.contexts.contains(context) }
            guard !rows.isEmpty else { return nil }
            let average = Int((Double(rows.map(\.rise).reduce(0, +)) / Double(rows.count)).rounded())
            return HabitBar(id: context.rawValue, name: context.localizedName, average: average)
        }
    }

    private func save() {
        let meal = MealLog(
            food: draft.food,
            duration: draft.duration,
            contexts: draft.contexts,
            drink: draft.drink,
            sugarSpoons: draft.sugar,
            feelings: draft.feelings,
            sleepHours: draft.sleep,
            stress: draft.stress,
            rise: state.points.recentRise,
            carbsGrams: draft.carbs > 0 ? draft.carbs : nil,
            insulinUnits: draft.insulin > 0 ? draft.insulin : nil
        )
        state.addMeal(meal)
        let rememberedSleep = draft.sleep
        draft = MealDraft()
        draft.sleep = rememberedSleep
    }

    private func applyHealthSleep() {
        guard !appliedSleep, let hours = state.healthSleepHours else { return }
        let snapped = (min(12, max(2, hours)) * 2).rounded() / 2
        draft.sleep = snapped
        appliedSleep = true
    }
}

private struct HabitBar: Identifiable {
    var id: String
    var name: String
    var average: Int
}

struct MealInsightSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var meal: MealLog

    var body: some View {
        let insight = state.insights.insight(for: meal)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(insight.title)
                        .scaledFont(size: 32, weight: .bold, design: .serif, relativeTo: .largeTitle)
                        .foregroundStyle(Color.maroon)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your glucose moved about +\(meal.rise) mg/dL around this meal. Here is what may have played a part.")
                        .scaledFont(size: 15)
                        .foregroundStyle(Color.forest)
                        .fixedSize(horizontal: false, vertical: true)
                    if meal.carbsGrams != nil || meal.insulinUnits != nil {
                        loggedAmounts
                    }
                    ForEach(insight.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 18))
                                .foregroundStyle(Color.maroon)
                                .frame(width: 44, height: 44)
                                .background(Color.blush.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.title)
                                        .scaledFont(size: 16, weight: .bold)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    HStack(spacing: 3) {
                                        ForEach(0..<3, id: \.self) { index in
                                            Circle()
                                                .fill(index < item.weight ? Color.terracotta : Color.sand)
                                                .frame(width: 8, height: 8)
                                        }
                                    }
                                    .accessibilityLabel(Text("Weight \(item.weight) of 3"))
                                }
                                Text(item.detail)
                                    .scaledFont(size: 13)
                                    .foregroundStyle(Color.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .anurjaCard()
                    }
                    if !insight.suggestions.isEmpty {
                        Text("Gentle things to try")
                            .scaledFont(size: 17, weight: .bold)
                            .padding(.top, 4)
                        ForEach(insight.suggestions, id: \.self) { suggestion in
                            Text(suggestion)
                                .scaledFont(size: 14)
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.sand.opacity(0.65), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    DisclaimerText()
                    PrimaryButton(title: "Build this into a habit") {
                        dismiss()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                            state.tab = .habits
                        }
                    }
                    Button("Done") { dismiss() }
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Color.terracotta)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(20)
            }
            .background(Color.cream)
        }
        .presentationDragIndicator(.visible)
    }

    private var loggedAmounts: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let carbs = meal.carbsGrams {
                Text("\(carbs) g")
                    .scaledFont(size: 15)
            }
            if let insulin = meal.insulinUnits {
                Text("\(insulin.formatted(.number.precision(.fractionLength(0...1)))) units")
                    .scaledFont(size: 15)
            }
            Text("Log only what you actually took. Anurja never suggests a dose.")
                .scaledFont(size: 12)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .anurjaCard()
    }
}

#Preview("Meals") {
    MainTabView().environmentObject(PreviewData.state(tab: .meals))
}

#Preview("Insight") {
    MealInsightSheet(meal: MealLog.previewToday)
        .environmentObject(PreviewData.state())
}
