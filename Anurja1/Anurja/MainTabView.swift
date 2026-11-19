import Charts
import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CreamBackground()
            ZStack {
                HomeView()
                    .opacity(state.tab == .home ? 1 : 0)
                    .allowsHitTesting(state.tab == .home)
                    .accessibilityHidden(state.tab != .home)
                TrendsView()
                    .opacity(state.tab == .trends ? 1 : 0)
                    .allowsHitTesting(state.tab == .trends)
                    .accessibilityHidden(state.tab != .trends)
                MealsView()
                    .opacity(state.tab == .meals ? 1 : 0)
                    .allowsHitTesting(state.tab == .meals)
                    .accessibilityHidden(state.tab != .meals)
                HabitsView()
                    .opacity(state.tab == .habits ? 1 : 0)
                    .allowsHitTesting(state.tab == .habits)
                    .accessibilityHidden(state.tab != .habits)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar()
        }
        .sheet(item: $state.insightMeal) { meal in
            MealInsightSheet(meal: meal)
        }
        .sheet(isPresented: $state.showMe) {
            MeView()
        }
        .fullScreenCover(item: $state.coach) { exercise in
            CoachScreen(exercise: exercise)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: state.tab)
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
                        VStack(spacing: 4) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 22))
                                .symbolVariant(state.tab == tab ? .fill : .none)
                                .accessibilityHidden(true)
                            Text(tab.title)
                                .font(.system(size: 12, weight: state.tab == tab ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(state.tab == tab ? Color.ink : Color.cream)
                        .frame(maxWidth: .infinity)
                        .frame(width: 66, height: 66)
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
            .padding(5)
            .background(Color.pillGreen, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 6)

            Menu {
                Button {
                    state.tab = .meals
                } label: {
                    Label("Log a meal", systemImage: "fork.knife")
                }
                Button {
                    state.tab = .habits
                } label: {
                    Label("Habit check-in", systemImage: "checkmark.circle")
                }
                Button {
                    state.openCoach(.squat)
                } label: {
                    Label("Coached exercise", systemImage: "figure.strengthtraining.functional")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 64, height: 64)
                    .background(Color.terracotta, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 6)
            }
            .accessibilityLabel(Text("Quick add"))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var greeting: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: greeting, subtitle: "Your rhythm today")
                glucoseCard
                forecastChip
                if state.forecast.contains(where: { $0.value < 70 }) {
                    ForecastBanner(low: true)
                }
                if state.forecast.contains(where: { $0.value > 180 }) {
                    ForecastBanner(low: false)
                }
                if state.gamified {
                    gardenCard
                    questsCard
                } else {
                    simpleStats
                }
                if let meal = state.meals.first {
                    latestInsight(meal)
                }
                PrimaryButton(
                    title: state.goal == .meals ? "Log a meal" : "Today's habit"
                ) {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                        state.tab = state.goal == .meals ? .meals : .habits
                    }
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
        VStack(alignment: .leading, spacing: 10) {
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
                    Text((Double(state.points.timeInRange) / 100), format: .percent.precision(.fractionLength(0)))
                        .scaledFont(size: 24, weight: .bold)
                        .foregroundStyle(Color.forest)
                    Text("in range, 24h")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.trailing)
                }
            }
            if state.points.count > 1 {
                GlucoseLineChart(points: state.points, showsAxes: false)
                    .frame(height: 80)
                    .accessibilityLabel(Text("Glucose chart"))
            } else {
                Text("No readings yet")
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.muted)
            }
        }
        .anurjaCard()
    }

    private var forecastChip: some View {
        let hourValue = Int((state.forecast.last?.value ?? state.points.currentValue).rounded())
        let tone = GlucoseForecast.tone(last: state.points.currentValue, forecast: state.forecast)
        return HStack(spacing: 8) {
            Image(systemName: tone.symbol)
                .foregroundStyle(Color.terracotta)
                .accessibilityHidden(true)
            Text("In 1 hour: about \(hourValue) mg/dL")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Color.sand, lineWidth: 1))
    }

    private var gardenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: gardenSymbol)
                    .font(.system(size: 42))
                    .foregroundStyle(Color.forest)
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Level \(state.level) garden")
                        .scaledFont(size: 18, weight: .bold)
                        .foregroundStyle(Color.ink)
                    Text("Small steps help it grow")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.terracotta)
                    Text(state.streak.formatted())
                        .scaledFont(size: 16, weight: .bold)
                        .foregroundStyle(Color.terracotta)
                }
                .accessibilityLabel(Text("Streak \(state.streak)"))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sand)
                    Capsule()
                        .fill(Color.terracotta)
                        .frame(width: geo.size.width * CGFloat(state.xpIntoLevel) / 100)
                }
            }
            .frame(height: 8)
            .accessibilityLabel(Text("\(state.xpIntoLevel) / 100 XP to the next level"))
            Text("\(state.xpIntoLevel) / 100 XP to the next level")
                .scaledFont(size: 12)
                .foregroundStyle(Color.muted)
        }
        .anurjaCard()
    }

    private var gardenSymbol: String {
        switch min(3, state.level - 1) {
        case 0: "leaf"
        case 1: "leaf.fill"
        case 2: "camera.macro"
        default: "tree.fill"
        }
    }

    private var questsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today's gentle quests")
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(Color.ink)
            questRow(done: state.loggedMealToday, title: "Log one meal", tab: .meals)
            questRow(done: state.walkedToday, title: "A walk after lunch", tab: .habits)
            questRow(done: state.coachedToday, title: "One coached exercise", tab: .habits)
        }
        .anurjaCard()
    }

    private func questRow(done: Bool, title: LocalizedStringKey, tab: AppTab) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                state.tab = tab
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? Color.forest : Color.terracotta)
                Text(title)
                    .scaledFont(size: 15)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    private var simpleStats: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                stat(state.meals.count.formatted(), "meals logged")
                stat(state.points.averageValue.formatted(), "avg mg/dL")
                stat(state.positiveCheckIns.formatted(), "walks done")
            }
            VStack(spacing: 10) {
                stat(state.meals.count.formatted(), "meals logged")
                stat(state.points.averageValue.formatted(), "avg mg/dL")
                stat(state.positiveCheckIns.formatted(), "walks done")
            }
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .scaledFont(size: 24, weight: .bold)
                .foregroundStyle(Color.ink)
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

    private func latestInsight(_ meal: MealLog) -> some View {
        let insight = state.insights.insight(for: meal)
        let food = meal.food.localizedName
        let shownFood = Locale.current.language.languageCode?.identifier == "en" ? food.lowercased() : food
        return VStack(alignment: .leading, spacing: 6) {
            Text("Latest insight")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
            Text("\(insight.title) after \(shownFood)")
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = insight.items.first?.detail {
                Text(detail)
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.forest)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .anurjaCard()
    }
}

struct TrendsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: "Trends", subtitle: "Last 24 hours")
                chartCard
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        trendStat((Double(state.points.timeInRange) / 100).formatted(.percent.precision(.fractionLength(0))), "time in range")
                        trendStat(state.points.averageValue.formatted(), "average")
                        trendStat(state.points.highReadings.formatted(), "high readings")
                    }
                    VStack(spacing: 10) {
                        trendStat((Double(state.points.timeInRange) / 100).formatted(.percent.precision(.fractionLength(0))), "time in range")
                        trendStat(state.points.averageValue.formatted(), "average")
                        trendStat(state.points.highReadings.formatted(), "high readings")
                    }
                }
                nextHourCard
                if state.forecast.contains(where: { $0.value < 70 }) {
                    ForecastBanner(low: true)
                }
                if state.forecast.contains(where: { $0.value > 180 }) {
                    ForecastBanner(low: false)
                }
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

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.points.count > 1 {
                GlucoseLineChart(points: state.points, forecast: state.forecast, meals: state.meals, showsAxes: true)
                    .frame(height: 220)
            } else {
                Text("No readings yet")
                    .scaledFont(size: 15)
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.forest, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 22, height: 2)
                Text("Predicted")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
            }
        }
        .anurjaCard()
    }

    private var nextHourCard: some View {
        let hourValue = Int((state.forecast.last?.value ?? state.points.currentValue).rounded())
        let tone = GlucoseForecast.tone(last: state.points.currentValue, forecast: state.forecast)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Next hour")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
            Text(hourValue, format: .number.precision(.fractionLength(0)))
                .scaledFont(size: 32, weight: .bold)
                .foregroundStyle(Color.ink)
            Text("mg/dL")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
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
            if state.todayMeals.isEmpty {
                Text("Nothing logged yet. Tap + to log a meal.")
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
                            Text("+\(meal.rise)")
                                .scaledFont(size: 13, weight: .semibold)
                                .foregroundStyle(Color.forest)
                        }
                        Text(meal.food.localizedName)
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(Color.ink)
                        HStack(spacing: 12) {
                            if let carbs = meal.carbsGrams {
                                Text("\(carbs) g")
                                    .scaledFont(size: 13)
                                    .foregroundStyle(Color.muted)
                            }
                            if let insulin = meal.insulinUnits {
                                Text("\(insulin.formatted(.number.precision(.fractionLength(0...1)))) units")
                                    .scaledFont(size: 13)
                                    .foregroundStyle(Color.muted)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .anurjaCard()
    }

    private func trendStat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .scaledFont(size: 24, weight: .bold)
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
    var showsAxes: Bool

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
                    y: .value("Glucose", point.value),
                    series: .value("Series", "Actual")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.terracotta)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
            ForEach(forecastLine) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Glucose", point.value),
                    series: .value("Series", "Predicted")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(Color.forest)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            ForEach(mealMarks) { mark in
                PointMark(
                    x: .value("Time", mark.time),
                    y: .value("Glucose", mark.value)
                )
                .foregroundStyle(Color.maroon)
                .symbolSize(50)
            }
        }
        .chartYScale(domain: 50...250)
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine().foregroundStyle(Color.sand)
                    AxisValueLabel(format: .dateTime.hour())
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
        .chartLegend(.hidden)
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
