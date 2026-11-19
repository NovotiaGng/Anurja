import Charts
import SwiftUI

struct MealsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let helps = state.whatHelps
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(
                    title: "Meals",
                    subtitle: "Tell us what you eat and how it sits with you. No right answers, nothing to fix."
                )
                addMealButton
                if state.profile.takesInsulin {
                    insulinPrompt
                }
                carbsToday
                mealsLanded
                whatHelps(helps)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var addMealButton: some View {
        Button {
            state.showAddMeal = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.terracotta)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add meal")
                        .scaledFont(size: 18, weight: .bold)
                    Text("Camera or food library")
                        .scaledFont(size: 13)
                        .opacity(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "camera")
                    .font(.system(size: 18, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.terracotta, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add meal"))
    }

    /// The pop-up entry point sits right below Add meal.
    private var insulinPrompt: some View {
        Button {
            state.showInsulin = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "syringe")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.maroon)
                    .frame(width: 44, height: 44)
                    .background(Color.blush.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Took insulin?")
                        .scaledFont(size: 16, weight: .bold)
                        .foregroundStyle(Color.ink)
                    Text(lastInsulinText)
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("Log units")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(Color.terracotta, in: Capsule())
            }
            .anurjaCard(padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Log insulin"))
    }

    private var lastInsulinText: String {
        guard let last = state.insulinLogs.first else {
            return String(localized: "Log the time, units and whether it was before or after a meal.")
        }
        let units = last.units.formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "Last: \(units) units at \(last.date.formatted(date: .omitted, time: .shortened)) · \(last.relation.title)")
    }

    private var carbsToday: some View {
        let target = max(1, state.profile.carbTarget)
        let eaten = state.carbsToday
        return VStack(alignment: .leading, spacing: 8) {
            Text("Carbs today")
                .scaledFont(size: 17, weight: .bold)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(eaten) g")
                    .scaledFont(size: 28, weight: .bold)
                    .foregroundStyle(Color.ink)
                Text("of \(target) g target")
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sand)
                    Capsule()
                        .fill(eaten > target ? Color.terracotta : Color.forest)
                        .frame(width: geo.size.width * min(1, CGFloat(eaten) / CGFloat(target)))
                }
            }
            .frame(height: 8)
            .accessibilityLabel(Text("\(eaten) of \(target) grams"))
        }
        .anurjaCard()
    }

    private var mealsLanded: some View {
        let recent = Array((state.meals.isEmpty ? MealLog.samples : state.meals).prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            Text("How your meals landed")
                .scaledFont(size: 17, weight: .bold)
            ForEach(recent) { meal in
                Button {
                    state.insightMeal = meal
                } label: {
                    HStack(spacing: 12) {
                        if let photo = MealPhotoStore.load(meal.photoFile) {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "fork.knife")
                                .foregroundStyle(Color.maroon)
                                .frame(width: 44, height: 44)
                                .background(Color.blush.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.displayName)
                                .scaledFont(size: 15, weight: .semibold)
                                .foregroundStyle(Color.ink)
                            Text(meal.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                                .scaledFont(size: 12)
                                .foregroundStyle(Color.muted)
                        }
                        Spacer(minLength: 8)
                        Text("↑ \(meal.rise) mg/dL rise")
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(meal.rise >= 55 ? Color.terracotta : Color.forest)
                    }
                }
                .buttonStyle(.plain)
            }
            if state.meals.isEmpty {
                Text("Sample meals until you've logged your own.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
            }
        }
        .anurjaCard()
    }

    private func whatHelps(_ helps: WhatHelps) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What helps you")
                .scaledFont(size: 21, weight: .bold)
                .foregroundStyle(Color.ink)
                .padding(.top, 6)

            if let snack = helps.snack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggested snack")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text(snack.item.name)
                        .scaledFont(size: 22, weight: .bold)
                    Text("\(snack.item.serving) · keeps your glucose level steadier between meals")
                        .scaledFont(size: 14)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Expected ↑ \(snack.rise) mg/dL")
                        .scaledFont(size: 13, weight: .semibold)
                        .opacity(0.9)
                }
                .foregroundStyle(Color.white)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.forest, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }

            if !helps.comparisons.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your meals compared")
                        .scaledFont(size: 17, weight: .bold)
                    ForEach(helps.comparisons) { comparison in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(comparison.item.name)
                                    .scaledFont(size: 15, weight: .semibold)
                                Spacer()
                                Text("↑ \(comparison.averageRise) mg/dL")
                                    .scaledFont(size: 14, weight: .semibold)
                                    .foregroundStyle(Color.terracotta)
                            }
                            if let swap = comparison.swap, let saving = comparison.saving, saving > 0 {
                                Text("Try \(swap.item.name): about \(saving) mg/dL lower glucose level")
                                    .scaledFont(size: 13)
                                    .foregroundStyle(Color.forest)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("Already one of your steadier choices")
                                    .scaledFont(size: 13)
                                    .foregroundStyle(Color.muted)
                            }
                        }
                        .padding(12)
                        .background(Color.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .anurjaCard()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Foods that keep your glucose level steady")
                    .scaledFont(size: 17, weight: .bold)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(helps.steadyFoods) { score in
                    HStack {
                        Text(score.item.name)
                            .scaledFont(size: 15)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Text("↑ \(score.rise) mg/dL")
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(Color.forest)
                    }
                    .frame(minHeight: 32)
                }
            }
            .anurjaCard()

            if !helps.habits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Average rise by habit")
                        .scaledFont(size: 17, weight: .bold)
                    Chart {
                        ForEach(helps.habits) { habit in
                            BarMark(
                                x: .value("Rise (mg/dL)", habit.withAverage),
                                y: .value("Habit", habit.context.localizedName)
                            )
                            .foregroundStyle(habit.delta > 0 ? Color.terracotta : Color.forest)
                            .cornerRadius(4)
                        }
                    }
                    .chartXScale(domain: 0...max(80, helps.habits.map(\.withAverage).max() ?? 80))
                    .frame(height: CGFloat(helps.habits.count) * 44 + 24)
                    .accessibilityLabel(Text("Average rise by habit"))
                    if let best = helps.habits.first, best.delta < 0 {
                        Text("“\(best.context.localizedName)” keeps your glucose level about \(-best.delta) mg/dL lower.")
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.forest)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .anurjaCard()
            }

            Text(helps.personalisedFrom > 0
                 ? String(localized: "Learned from \(helps.personalisedFrom) meals by Anurja's on-device model (typical error ±\(Int(GeneratedModels.riseMAE.rounded())) mg/dL). Suggestions skip your allergies.")
                 : String(localized: "Anurja's on-device model fills in until you log meals. Suggestions skip your allergies."))
                .scaledFont(size: 12)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
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
                    Text("Your glucose moved ↑ \(meal.rise) mg/dL around this meal. Here is what may have played a part.")
                        .scaledFont(size: 15)
                        .foregroundStyle(Color.forest)
                        .fixedSize(horizontal: false, vertical: true)
                    loggedAmounts
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
                    if state.profile.takesInsulin {
                        Button {
                            dismiss()
                            Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                state.showInsulin = true
                            }
                        } label: {
                            Label("Log insulin for this meal", systemImage: "syringe")
                                .scaledFont(size: 16, weight: .semibold)
                                .foregroundStyle(Color.terracotta)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .overlay(Capsule().stroke(Color.terracotta, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
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
            Text("\(meal.displayName) · \(meal.carbsEstimate) g carbs")
                .scaledFont(size: 15, weight: .semibold)
            if let predicted = meal.predictedRise {
                Text("Anurja expected ↑ \(predicted) mg/dL; your sensor showed ↑ \(meal.rise) mg/dL. Anurja learns from the difference.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let insulin = meal.insulinUnits {
                Text("\(insulin.formatted(.number.precision(.fractionLength(0...1)))) units")
                    .scaledFont(size: 15)
            }
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
