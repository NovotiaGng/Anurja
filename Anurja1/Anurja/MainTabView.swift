import Charts
import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            CreamBackground()
            // Tabs switch instantly when tapped (no cross-fade that reads as scrolling).
            ZStack {
                tabPage(.home) { HomeView() }
                tabPage(.trends) { TrendsView() }
                tabPage(.meals) { MealsView() }
                tabPage(.habits) { HabitsView() }
                tabPage(.me) { ProfileView() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar()
        }
        .sheet(item: $state.insightMeal) { meal in
            MealInsightSheet(meal: meal)
        }
        .sheet(isPresented: $state.showAddMeal) {
            AddMealFlow()
        }
        .sheet(isPresented: $state.showInsulin) {
            InsulinSheet()
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $state.coach) { exercise in
            CoachScreen(exercise: exercise)
        }
    }

    private func tabPage<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(state.tab == tab ? 1 : 0)
            .animation(nil, value: state.tab)
            .allowsHitTesting(state.tab == tab)
            .accessibilityHidden(state.tab != tab)
    }
}

struct FloatingTabBar: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                            state.tab = tab
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 20))
                                .symbolVariant(state.tab == tab ? .fill : .none)
                                .accessibilityHidden(true)
                            Text(tab.title)
                                .font(.system(size: 11, weight: state.tab == tab ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(state.tab == tab ? Color.ink : Color.cream)
                        .frame(maxWidth: .infinity)
                        .frame(width: 56, height: 60)
                        .background {
                            if state.tab == tab {
                                Circle()
                                    .fill(Color.blush)
                                    .matchedGeometryEffect(id: "tab-highlight", in: highlight)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(tab.title))
                    .accessibilityAddTraits(state.tab == tab ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Color.pillGreen, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 6)

            Menu {
                Button {
                    state.openAddMeal()
                } label: {
                    Label("Add meal", systemImage: "fork.knife")
                }
                if state.profile.takesInsulin {
                    Button {
                        state.showInsulin = true
                    } label: {
                        Label("Log insulin", systemImage: "syringe")
                    }
                }
                Button {
                    state.tab = .habits
                } label: {
                    Label("Today's training", systemImage: "figure.walk")
                }
                Button {
                    state.openCoach(.squat)
                } label: {
                    Label("Coached exercise", systemImage: "figure.strengthtraining.functional")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 58, height: 58)
                    .background(Color.terracotta, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 6)
            }
            .accessibilityLabel(Text("Quick add"))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var range: TimeRange = .day

    private var greeting: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = state.profile.firstName
        if name.isEmpty {
            if hour < 12 { return "Good morning" }
            if hour < 17 { return "Good afternoon" }
            return "Good evening"
        }
        if hour < 12 { return "Good morning, \(name)" }
        if hour < 17 { return "Good afternoon, \(name)" }
        return "Good evening, \(name)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: greeting, subtitle: "Your rhythm today")
                glucoseCard
                forecastChip
                if let activity = state.activity {
                    ActivityCard(recommendation: activity)
                }
                statsRow
                if let meal = state.meals.first {
                    latestInsight(meal)
                }
                PrimaryButton(title: "Log a meal") {
                    state.openAddMeal()
                }
                .padding(.top, 4)
                Text("Predictions are estimates, not medical advice.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var glucoseCard: some View {
        let shown = state.points(in: range)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(state.points.currentValue, format: .number.precision(.fractionLength(0)))
                        .scaledFont(size: 56, weight: .bold, relativeTo: .largeTitle)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text("mg/dL")
                        .scaledFont(size: 15)
                        .foregroundStyle(Color.muted)
                    Image(systemName: state.points.trendSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.terracotta)
                        .accessibilityLabel(Text(trendWord(for: state.points.trendSymbol)))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text((Double(shown.timeInRange) / 100), format: .percent.precision(.fractionLength(0)))
                        .scaledFont(size: 24, weight: .bold)
                        .foregroundStyle(Color.forest)
                    Text("Time in Target range")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.trailing)
                }
            }
            RangePicker(range: $range)
            if shown.count > 1 {
                GlucoseLineChart(points: shown, range: range, showsAxes: true, compact: true)
                    .frame(height: 130)
                    .accessibilityLabel(Text("Glucose chart"))
            } else {
                Text("No readings yet")
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.muted)
            }
        }
        .anurjaCard()
    }

    /// Prediction stays abstract: rise / fall / steady, never a number.
    private var forecastChip: some View {
        let tone = state.forecastTone
        return HStack(spacing: 8) {
            Image(systemName: tone.symbol)
                .foregroundStyle(Color.terracotta)
                .accessibilityHidden(true)
            Text(tone.prediction)
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(state.activity.map { "\($0.targetLow)–\($0.targetHigh) mg/dL" } ?? "70–180 mg/dL")
                .scaledFont(size: 12)
                .foregroundStyle(Color.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Color.sand, lineWidth: 1))
    }

    private var statsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { gmiStat; stepsStat; caloriesStat }
            VStack(spacing: 10) { gmiStat; stepsStat; caloriesStat }
        }
    }

    private var gmiStat: some View {
        let current = (state.gmi * 10).rounded() / 10
        var compare: String = String(localized: "Updates monthly")
        if let previous = state.previousGMI {
            let delta = current - previous
            let arrow = delta > 0 ? "↑" : (delta < 0 ? "↓" : "→")
            compare = String(localized: "\(arrow) \(abs(delta).formatted(.number.precision(.fractionLength(1)))) vs last month")
        }
        return stat(
            "\(current.formatted(.number.precision(.fractionLength(1))))%",
            "Est. GMI",
            compare
        )
    }

    private var stepsStat: some View {
        stat(state.stepsToday.formatted(), "Steps", String(localized: "Today"))
    }

    private var caloriesStat: some View {
        stat(state.caloriesToday.formatted(), "Calories", String(localized: "Active kcal, Health"))
    }

    private func stat(_ value: String, _ label: LocalizedStringKey, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .scaledFont(size: 22, weight: .bold)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Color.ink)
            Text(detail)
                .scaledFont(size: 11)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .anurjaCard(padding: 13)
    }

    private func latestInsight(_ meal: MealLog) -> some View {
        let insight = state.insights.insight(for: meal)
        let food = meal.displayName
        let shownFood = Locale.current.language.languageCode?.identifier == "en" ? food.lowercased() : food
        return Button {
            state.insightMeal = meal
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Latest insight")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.muted)
                Text("\(insight.title) after \(shownFood)")
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = insight.items.first?.detail {
                    Text(detail)
                        .scaledFont(size: 14)
                        .foregroundStyle(Color.forest)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .anurjaCard()
        }
        .buttonStyle(.plain)
    }
}

/// Immediate activity suggestion from the on-device activity model.
struct ActivityCard: View {
    @EnvironmentObject private var state: AppState
    var recommendation: ActivityRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: recommendation.status.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(recommendation.status.needsAttention ? Color.white : Color.forest)
                    .frame(width: 40, height: 40)
                    .background(recommendation.status.needsAttention ? Color.terracotta : Color.sand, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Right now")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.muted)
                    Text(recommendation.status.title)
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recommendation.targetText)
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.forest)
                }
            }
            ForEach(recommendation.actions) { action in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: action.symbol)
                        .foregroundStyle(Color.maroon)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(Color.ink)
                        Text(action.detail)
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if action.id == "brisk_walk" || action.id == "light_walk" {
                        Button {
                            state.startDailySession()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.terracotta)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Start walk"))
                    } else if action.id == "squats" {
                        Button {
                            state.openCoach(.squat)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.terracotta)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Start squats"))
                    }
                }
                .padding(10)
                .background(Color.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let note = recommendation.personalNote {
                Text(note)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.forest)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if recommendation.status == .low {
                Text("Follow your care team's plan for lows.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
            }
        }
        .anurjaCard()
    }
}

struct RangePicker: View {
    @Binding var range: TimeRange

    var body: some View {
        SegmentedTabs(options: TimeRange.allCases, title: { $0.title }, selection: $range)
            .accessibilityLabel(Text("Time period"))
    }
}

// MARK: - Trends

struct TrendsView: View {
    @EnvironmentObject private var state: AppState
    @State private var range: TimeRange = .day

    var body: some View {
        let shown = state.points(in: range)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: "Trends", subtitle: range.subtitle)
                RangePicker(range: $range)
                chartCard(shown)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { stats(shown) }
                    VStack(spacing: 10) { stats(shown) }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) { peaks(shown) }
                    VStack(spacing: 10) { peaks(shown) }
                }
                nextHourCard
                todayLog
                Text("Shaded band is 70–180 mg/dL. Dots mark meals you logged.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Predictions are estimates, not medical advice.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
                DisclaimerText()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func chartCard(_ shown: [GlucosePoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Glucose trend (mg/dL)")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Color.ink)
            if shown.count > 1 {
                GlucoseLineChart(
                    points: shown,
                    forecast: range == .week ? [] : state.forecast,
                    meals: state.meals.filter { meal in shown.first.map { meal.date >= $0.time } ?? false },
                    range: range,
                    showsAxes: true
                )
                .frame(height: 230)
            } else {
                Text("No readings yet")
                    .scaledFont(size: 15)
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            if range != .week {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.forest, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .frame(width: 22, height: 2)
                    Text("Predicted direction")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.muted)
                }
            }
        }
        .anurjaCard()
    }

    @ViewBuilder
    private func stats(_ shown: [GlucosePoint]) -> some View {
        trendStat((Double(shown.timeInRange) / 100).formatted(.percent.precision(.fractionLength(0))), "Time in Target range")
        trendStat("\(shown.averageValue) mg/dL", "average")
        trendStat("\(GlucoseTargets.gmi(meanGlucose: shown.meanValue).formatted(.number.precision(.fractionLength(1))))%", "Est. GMI")
    }

    @ViewBuilder
    private func peaks(_ shown: [GlucosePoint]) -> some View {
        if let high = shown.highestPeak(meals: state.meals) {
            peakCard(
                title: "Highest peak",
                value: high.point.value,
                change: "↑ +\(high.change) mg/dL",
                time: high.point.time,
                detail: high.meal.map { String(localized: "After \($0.displayName)") }
            )
        }
        if let low = shown.lowestPeak() {
            peakCard(
                title: "Lowest peak",
                value: low.point.value,
                change: "↓ \(low.change) mg/dL",
                time: low.point.time,
                detail: nil
            )
        }
    }

    private func peakCard(title: LocalizedStringKey, value: Double, change: String, time: Date, detail: String?) -> some View {
        let timeStyle: Date.FormatStyle = range == .week
            ? .dateTime.weekday(.abbreviated).hour().minute()
            : .dateTime.hour().minute()
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value, format: .number.precision(.fractionLength(0)))
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(Color.ink)
                Text("mg/dL")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
            }
            Text(change)
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Color.terracotta)
            Text(time, format: timeStyle)
                .scaledFont(size: 13)
                .foregroundStyle(Color.forest)
            if let detail {
                Text(detail)
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .anurjaCard()
    }

    private var nextHourCard: some View {
        let tone = state.forecastTone
        return VStack(alignment: .leading, spacing: 6) {
            Text("Next hour")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
            HStack(spacing: 8) {
                Image(systemName: tone.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.terracotta)
                    .accessibilityHidden(true)
                Text(tone.prediction)
                    .scaledFont(size: 20, weight: .bold)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(tone.message)
                .scaledFont(size: 15)
                .foregroundStyle(Color.forest)
                .fixedSize(horizontal: false, vertical: true)
        }
        .anurjaCard()
    }

    private var todayLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's log")
                .scaledFont(size: 17, weight: .bold)
            if state.todayMeals.isEmpty && state.todayInsulin.isEmpty {
                Text("Nothing logged yet. Tap + to add a meal.")
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(state.todayMeals) { meal in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(meal.date, format: .dateTime.hour().minute())
                                .scaledFont(size: 13)
                                .foregroundStyle(Color.muted)
                            Spacer()
                            Text("↑ \(meal.rise) mg/dL rise")
                                .scaledFont(size: 13, weight: .semibold)
                                .foregroundStyle(Color.forest)
                        }
                        Text(meal.displayName)
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(Color.ink)
                        Text("\(meal.carbsEstimate) g carbs")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                ForEach(state.todayInsulin) { log in
                    HStack {
                        Image(systemName: "syringe")
                            .foregroundStyle(Color.maroon)
                            .accessibilityHidden(true)
                        Text("\(log.units.formatted(.number.precision(.fractionLength(0...1)))) units · \(log.relation.title)")
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Text(log.date, format: .dateTime.hour().minute())
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.muted)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .anurjaCard()
    }

    private func trendStat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .scaledFont(size: 21, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .scaledFont(size: 12)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .anurjaCard()
    }
}

struct ForecastBanner: View {
    var low: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: low ? "arrow.down.right" : "arrow.up.right")
                .foregroundStyle(Color.maroon)
                .accessibilityHidden(true)
            Text(low
                 ? "Your glucose may be heading low. Follow your care team's plan."
                 : "Your glucose may run high. A short walk can help; check your care team's plan if it stays high.")
                .scaledFont(size: 14)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sand.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct GlucoseLineChart: View {
    var points: [GlucosePoint]
    var forecast: [GlucosePoint] = []
    var meals: [MealLog] = []
    var range: TimeRange = .day
    var showsAxes: Bool
    var compact = false

    var body: some View {
        let forecastLine = anchorForecast()
        Chart {
            if let first = points.first, let last = (forecastLine.last?.time ?? points.last?.time) {
                RectangleMark(
                    xStart: .value("Start", first.time),
                    xEnd: .value("End", last),
                    yStart: .value("Low", 70),
                    yEnd: .value("High", 180)
                )
                .foregroundStyle(Color.forest.opacity(0.09))
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Glucose (mg/dL)", point.value),
                    series: .value("Series", "Actual")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.terracotta)
                .lineStyle(StrokeStyle(lineWidth: range == .week ? 1.5 : 2.5, lineJoin: .round))
            }
            ForEach(forecastLine) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Glucose (mg/dL)", point.value),
                    series: .value("Series", "Predicted")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(Color.forest)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            ForEach(mealMarks) { mark in
                PointMark(
                    x: .value("Time", mark.time),
                    y: .value("Glucose (mg/dL)", mark.value)
                )
                .foregroundStyle(Color.maroon)
                .symbolSize(50)
            }
        }
        .chartYScale(domain: 50...250)
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: axisValues) { _ in
                    AxisGridLine().foregroundStyle(Color.sand)
                    if range == .week {
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    } else {
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    }
                }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .leading, values: [70, 180]) { _ in
                    AxisGridLine().foregroundStyle(Color.sand)
                    AxisValueLabel()
                }
            }
        }
        .chartYAxisLabel(position: .leading) {
            if !compact {
                Text("mg/dL")
            }
        }
        .chartLegend(.hidden)
    }

    private var axisValues: AxisMarkValues {
        switch range {
        case .twelve: .stride(by: .hour, count: compact ? 4 : 3)
        case .day: .stride(by: .hour, count: 6)
        case .week: .stride(by: .day, count: 1)
        }
    }

    private var mealMarks: [GlucosePoint] {
        meals.compactMap { meal in
            points.min { abs($0.time.timeIntervalSince(meal.date)) < abs($1.time.timeIntervalSince(meal.date)) }
        }
    }

    private func anchorForecast() -> [GlucosePoint] {
        guard let last = points.last, !forecast.isEmpty else { return [] }
        return [last] + forecast
    }
}

#Preview("Home") {
    MainTabView().environmentObject(PreviewData.state(tab: .home))
}

#Preview("Trends") {
    MainTabView().environmentObject(PreviewData.state(tab: .trends))
}
