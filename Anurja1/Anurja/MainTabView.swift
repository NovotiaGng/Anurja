import HealthKit
import Charts
import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var state: AppState
    @State private var pillWidth: CGFloat = 0

    var body: some View {
        tabs
            .tint(Color.terracotta)
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
            .fullScreenCover(isPresented: $state.showWalk) {
                WalkScreen()
            }
    }

    /// Native tab bar with Home/Meals/Train; "+" is a separate button on
    /// the same line, never a tab.
    private var tabs: some View {
        TabView(selection: $state.tab) {
            page { HomeView() }.tabItem { Label(AppTab.home.title, systemImage: AppTab.home.symbol) }.tag(AppTab.home)
            page { MealsView() }.tabItem { Label(AppTab.meals.title, systemImage: AppTab.meals.symbol) }.tag(AppTab.meals)
            page { HabitsView() }.tabItem { Label(AppTab.habits.title, systemImage: AppTab.habits.symbol) }.tag(AppTab.habits)
        }
        .overlay(alignment: .bottom) {
            QuickAddButton(pillWidth: pillWidth)
        }
    }

    /// Each tab has its own navigation stack, so Trends (from the glucose
    /// card) and Me (from the profile button) push in place, tab bar kept.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            ZStack {
                CreamBackground()
                content()
            }
            .background(TabBarCentring { pillWidth = $0 })
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Shifts the native tab bar's pill left so the pill and "+" are centred
/// together as one group. iOS 26+ draws a content-sized pill centred inside a
/// full-width UITabBar; the bar stays native, only shifted. Older iOS: no-op.
private struct TabBarCentring: UIViewRepresentable {
    /// Reports the pill's width so "+" can sit just after it.
    var onPillWidth: (CGFloat) -> Void

    func makeUIView(context: Context) -> Aligner { Aligner() }
    func updateUIView(_ view: Aligner, context: Context) { view.onPillWidth = onPillWidth }

    final class Aligner: UIView {
        var onPillWidth: (CGFloat) -> Void = { _ in }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { self.align() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            align()
        }

        private func align() {
            var responder: UIResponder? = self
            while let r = responder, !(r is UITabBarController) { responder = r.next }
            guard let bar = (responder as? UITabBarController)?.tabBar,
                  let pill = bar.subviews.first(where: { $0.frame.width > 0 && $0.frame.width < bar.bounds.width - 1 })
            else { return }
            let group = pill.frame.width + QuickAddButton.gap + QuickAddButton.size
            bar.transform = CGAffineTransform(translationX: (bar.bounds.width - group) / 2 - pill.frame.minX, y: 0)
            let width = pill.frame.width
            DispatchQueue.main.async { self.onPillWidth(width) }
        }
    }
}

/// Pushed pages (Trends, Me) on the app's cream background.
struct PushedPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            CreamBackground()
            content
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// Quick-add choices, shared by the tab-bar "+" and the iOS 17 button.
struct QuickAddActions: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
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
            state.showWalk = true
        } label: {
            Label("Start a walk", systemImage: "figure.walk")
        }
        Button {
            state.tab = .habits
        } label: {
            Label("Exercises", systemImage: "figure.strengthtraining.functional")
        }
    }
}

/// iOS 17 only: floating quick-add beside the tab bar.
struct QuickAddButton: View {
    static let size: CGFloat = 58
    static let gap: CGFloat = 12
    /// Width of the iOS 26+ tab bar pill; "+" sits `gap` after it.
    var pillWidth: CGFloat

    var body: some View {
        // ponytail: bottom offset measured against the iOS 26+ floating tab
        // bar (62pt pill, centred 17pt below the safe area); classic bar below that.
        if #available(iOS 26, *) {
            menu(size: Self.size)
                .offset(x: (pillWidth + Self.gap) / 2)
                .padding(.bottom, -12)
        } else {
            menu(size: 52)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
        }
    }

    private func menu(size: CGFloat) -> some View {
        Menu {
            QuickAddActions()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .background(Color.terracotta, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 6)
        }
        .accessibilityLabel(Text("Quick add"))
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("waterDay") private var waterDay = ""
    @AppStorage("waterGlasses") private var waterGlasses = 0

    private var greeting: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var targetLow: Int { state.activity?.targetLow ?? 70 }
    private var targetHigh: Int { state.activity?.targetHigh ?? 180 }
    private var current: Int { Int(state.points.currentValue.rounded()) }
    private var today: String { Date().formatted(.iso8601.year().month().day()) }
    private var glassesToday: Int { waterDay == today ? waterGlasses : 0 }
    static let stepGoal = 8000
    static let waterGoal = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                glucoseCard
                HStack(spacing: 10) {
                    RingTile(symbol: "fork.knife", color: .terracotta,
                             progress: Double(state.carbsToday) / Double(max(state.profile.carbTarget, 1)),
                             value: "\(state.carbsToday) g carbs",
                             detail: "^[\(state.todayMeals.count) meal](inflect: true)",
                             action: "+ Log meal") { state.openAddMeal() }
                    RingTile(symbol: "figure.walk", color: .forest,
                             progress: Double(state.stepsToday) / Double(Self.stepGoal),
                             value: "\(state.stepsToday.formatted())",
                             detail: "steps",
                             action: "+ Add walk") { state.showWalk = true }
                    RingTile(symbol: "drop", color: .water,
                             progress: Double(glassesToday) / Double(Self.waterGoal),
                             value: "\(glassesToday)",
                             detail: "of \(Self.waterGoal) glasses",
                             action: "+ Log water") {
                        if waterDay != today { waterDay = today; waterGlasses = 0 }
                        waterGlasses += 1
                    }
                }
                if let activity = state.activity {
                    DoThisNextCard(recommendation: activity, current: current)
                }
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .scaledFont(size: 17)
                    .foregroundStyle(Color.ink)
                if !state.profile.firstName.isEmpty {
                    Text(state.profile.firstName)
                        .scaledFont(size: 30, weight: .heavy, relativeTo: .largeTitle)
                        .foregroundStyle(Color.ink)
                }
            }
            Spacer()
            ProfileButton()
        }
    }

    private var statusBadge: (LocalizedStringKey, Color) {
        if current > targetHigh { return ("Above target", Color.terracotta) }
        if current < targetLow { return ("Below target", Color.maroon) }
        return ("In target", Color.forest)
    }

    private var glucoseCard: some View {
        let shown = state.points.within(hours: 18)
        return NavigationLink {
            PushedPage { TrendsView() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(current)")
                            .scaledFont(size: 60, weight: .heavy, relativeTo: .largeTitle)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                        Text("mg/dL")
                            .scaledFont(size: 15)
                            .foregroundStyle(Color.muted)
                        Image(systemName: state.points.trendSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.terracotta)
                            .accessibilityLabel(Text(trendWord(for: state.points.trendSymbol)))
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(statusBadge.0)
                            .scaledFont(size: 14, weight: .bold)
                            .foregroundStyle(statusBadge.1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(statusBadge.1.opacity(0.15), in: Capsule())
                        Text("Target \(targetLow)–\(targetHigh)")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.muted)
                    }
                }
                if shown.count > 1 {
                    GlucoseLineChart(points: shown, band: Double(targetLow)...Double(targetHigh), showsAxes: false, compact: true)
                        .frame(height: 80)
                    HStack {
                        ForEach([18, 12, 6], id: \.self) { hoursAgo in
                            Text(Date().addingTimeInterval(Double(-hoursAgo) * 3600), format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                            Spacer()
                        }
                        Text("Now")
                    }
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
                } else {
                    Text("No readings yet")
                        .scaledFont(size: 14)
                        .foregroundStyle(Color.muted)
                }
            }
            .anurjaCard(padding: 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("glucoseCard")
        .accessibilityHint(Text("Opens trends"))
    }

}

/// Home summary tile: progress ring with an icon, today's value and a
/// quick action. The whole tile is the button.
private struct RingTile: View {
    let symbol: String
    let color: Color
    let progress: Double
    let value: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: LocalizedStringKey
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.sand, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(color)
                }
                .frame(width: 62, height: 62)
                .padding(.bottom, 4)
                Text(value)
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(detail)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(action)
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color.terracotta)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 6)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.sand, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// "Do this next": the top action from the on-device activity model, with
/// the runner-up as a fallback link.
struct DoThisNextCard: View {
    @EnvironmentObject private var state: AppState
    var recommendation: ActivityRecommendation
    var current: Int

    private static let movement: Set<String> = ["brisk_walk", "light_walk", "squats", "stairs"]

    var body: some View {
        let actions = recommendation.actions
        VStack(alignment: .leading, spacing: 10) {
            Text("DO THIS NEXT")
                .scaledFont(size: 13, weight: .bold)
                .tracking(1)
                .foregroundStyle(Color.white.opacity(0.85))
            if let main = actions.first {
                Text(main.title)
                    .scaledFont(size: 24, weight: .heavy)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reason(main))
                    .scaledFont(size: 16)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                // No exercise button during a low: the advice there is eat and rest.
                if recommendation.status != .low {
                    Button { perform(main) } label: {
                        Label(main.id == "squats" ? "Start squats" : "Start walk", systemImage: "play.fill")
                            .scaledFont(size: 18, weight: .bold)
                            .foregroundStyle(Color.forest)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                if actions.count > 1, Self.movement.contains(actions[1].id) {
                    Button { perform(actions[1]) } label: {
                        (Text("Can't do that now? ") + Text(actions[1].title).underline().bold())
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                }
            }
            if recommendation.status == .low {
                Text("Follow your care team's plan for lows.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.forest, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func reason(_ action: ActivityAction) -> String {
        let gap = current - recommendation.targetHigh
        let lead = gap > 0 ? String(localized: "Your glucose is \(gap) above your target. ") : ""
        return lead + (recommendation.personalNote ?? action.detail)
    }

    private func perform(_ action: ActivityAction) {
        if action.id == "squats" {
            state.openCoach(.squat)
        } else {
            // Walks, stairs and "keep going" all start the live walk screen.
            state.showWalk = true
        }
    }
}

/// Live walk: steps, heart rate, distance and energy read from Apple Health
/// (merged from iPhone and Apple Watch), refreshed every few seconds.
struct WalkScreen: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var steps = 0
    @State private var heartRate: Int?
    @State private var meters = 0.0
    @State private var kcal = 0
    @State private var finishedAt: Date?
    @State private var loggingMeal = false
    @AppStorage("skippedMeals") private var skippedMeals = ""

    var body: some View {
        ZStack {
            Color.forest.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("BRISK WALK")
                            .scaledFont(size: 13, weight: .bold)
                            .tracking(1)
                            .foregroundStyle(Color.white.opacity(0.85))
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(Text("Close"))
                    }
                    if let finishedAt {
                        afterWalk(minutes: Int(finishedAt.timeIntervalSince(start) / 60))
                    } else {
                        Text(start, style: .timer)
                            .scaledFont(size: 64, weight: .heavy, relativeTo: .largeTitle)
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                        Text("Aim for 10 minutes at a pace where talking takes a little effort.")
                            .scaledFont(size: 16)
                            .foregroundStyle(Color.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            tile("figure.walk", "Steps", steps.formatted(), "this walk")
                            tile("heart.fill", "Heart rate", heartRate.map { "\($0)" } ?? "–", heartRate == nil ? String(localized: "Wear your Apple Watch") : "bpm")
                            tile("map", "Distance", (meters / 1000).formatted(.number.precision(.fractionLength(2))), "km")
                            tile("flame.fill", "Active energy", kcal.formatted(), "kcal")
                        }
                        HStack {
                            Label("Glucose now", systemImage: "drop.fill")
                            Spacer()
                            Text("\(Int(state.points.currentValue.rounded())) mg/dL")
                                .fontWeight(.bold)
                        }
                        .scaledFont(size: 16)
                        .foregroundStyle(Color.ink)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text("Live from Apple Health. Apple Watch readings can take a minute to arrive.")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: finish) {
                            Text("Finish walk")
                                .scaledFont(size: 18, weight: .bold)
                                .foregroundStyle(Color.forest)
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .background(Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $loggingMeal, onDismiss: { state.pendingMealDate = nil }) {
            AddMealFlow()
        }
        // Saving a meal closes the sheet and moves on to the next question.
        .onChange(of: state.meals.count) { loggingMeal = false }
        .task {
            await state.health.requestAccess()
            while !Task.isCancelled && finishedAt == nil {
                await refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func refresh() async {
        let health = state.health
        steps = Int(await health.sum(.stepCount, unit: .count(), since: start))
        meters = await health.sum(.distanceWalkingRunning, unit: .meter(), since: start)
        kcal = Int(await health.sum(.activeEnergyBurned, unit: .kilocalorie(), since: start))
        heartRate = await health.latestHeartRate(since: start.addingTimeInterval(-5 * 60))
    }

    /// Counts as a walk check-in so Train and the activity model learn from it,
    /// then asks about missed meals and whether to keep exercising.
    private func finish() {
        let minutes = Date().timeIntervalSince(start) / 60
        // ponytail: feel/effort aren't asked on this screen, so neutral values are stored.
        state.addCheckIn(HabitCheckIn(did: minutes >= 5 ? .yes : .little, feel: .fine, effort: .okay, steps: steps))
        withAnimation { finishedAt = Date() }
    }

    private var todayKey: String { Date().formatted(.iso8601.year().month().day()) }

    /// Meals whose time has passed today with nothing logged and no "I had nothing".
    private var missedMeals: [MealSlot] {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        return MealSlot.allCases.filter { slot in
            hour >= slot.dueHour
                && !skippedMeals.contains("\(todayKey)-\(slot.rawValue)")
                && !state.meals.contains { calendar.isDateInToday($0.date) && slot.hours.contains(calendar.component(.hour, from: $0.date)) }
        }
    }

    @ViewBuilder
    private func afterWalk(minutes: Int) -> some View {
        Text("Walk done")
            .scaledFont(size: 40, weight: .heavy, relativeTo: .largeTitle)
            .foregroundStyle(Color.white)
        Text("\(minutes) min · \(steps.formatted()) steps")
            .scaledFont(size: 17)
            .foregroundStyle(Color.white.opacity(0.9))
        if let slot = missedMeals.first {
            question(slot.question, slot.detail) {
                answer(slot.logTitle, filled: true) {
                    state.pendingMealDate = slot.usualTime
                    loggingMeal = true
                }
                answer("I had nothing then", filled: false) {
                    // Keep only today's answers so the string never grows.
                    let kept = skippedMeals.split(separator: ";").filter { $0.hasPrefix(todayKey) }
                    skippedMeals = (kept + ["\(todayKey)-\(slot.rawValue)"]).joined(separator: ";")
                }
            }
        } else {
            question("Do you want to continue exercising?", "Today's other exercises are in Train.") {
                answer("Yes, show exercises", filled: true) {
                    state.tab = .habits
                    dismiss()
                }
                answer("No, I'm done", filled: false) { dismiss() }
            }
        }
    }

    private func question<Buttons: View>(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .scaledFont(size: 22, weight: .bold)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .scaledFont(size: 15)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            buttons()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 8)
    }

    private func answer(_ title: LocalizedStringKey, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(filled ? Color.white : Color.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(filled ? Color.terracotta : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(filled ? Color.clear : Color.sand, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func tile(_ symbol: String, _ title: LocalizedStringKey, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Color.muted)
            Text(value)
                .scaledFont(size: 30, weight: .heavy)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .scaledFont(size: 12)
                .foregroundStyle(Color.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Meals checked after a walk. A meal counts as logged if one was saved in its hours.
enum MealSlot: String, CaseIterable {
    case breakfast, lunch

    var hours: Range<Int> { self == .breakfast ? 4..<11 : 11..<16 }
    /// Only ask once this hour has passed.
    var dueHour: Int { self == .breakfast ? 10 : 14 }

    var usualTime: Date {
        Calendar.current.date(bySettingHour: self == .breakfast ? 8 : 13, minute: self == .breakfast ? 30 : 0, second: 0, of: Date()) ?? Date()
    }

    var question: LocalizedStringKey { self == .breakfast ? "Did you have breakfast?" : "Did you have lunch?" }
    var detail: LocalizedStringKey {
        self == .breakfast ? "You haven't logged breakfast today. It helps Anurja read your walk." : "You haven't logged lunch today. It helps Anurja read your walk."
    }
    var logTitle: LocalizedStringKey { self == .breakfast ? "Log breakfast" : "Log lunch" }
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
    var band: ClosedRange<Double> = 70...180
    var showsAxes: Bool
    var compact = false

    var body: some View {
        let forecastLine = anchorForecast()
        Chart {
            if let first = points.first, let last = (forecastLine.last?.time ?? points.last?.time) {
                RectangleMark(
                    xStart: .value("Start", first.time),
                    xEnd: .value("End", last),
                    yStart: .value("Low", band.lowerBound),
                    yEnd: .value("High", band.upperBound)
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
    TrendsView().environmentObject(PreviewData.state())
}
