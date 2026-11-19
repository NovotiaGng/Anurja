import Combine
import SwiftUI
import WidgetKit

@MainActor
final class AppState: ObservableObject {
    static var useRealHealthKit = false

    @Published var stage: Stage = .welcome
    @Published var tab: AppTab = .home
    @Published var gamified = true
    @Published var goal: Goal = .meals
    @Published var watchLink: LinkState = .idle
    @Published var cgmLink: LinkState = .idle
    @Published var didFinishOnboarding = false
    @Published var points: [GlucosePoint] = []
    @Published var meals: [MealLog] = []
    @Published var checkIns: [HabitCheckIn] = []
    @Published var sessions: [CoachSession] = []
    @Published var plan = HabitPlan()
    @Published var xp = 40
    @Published var streak = 3
    @Published var stepsToday = 0
    @Published var healthSleepHours: Double?
    @Published var insightMeal: MealLog?
    @Published var coach: ExerciseKind?
    @Published var showMe = false

    let insights: any InsightProviding = RuleInsightEngine()

    private var suppressSave = true
    private var saveGeneration = 0
    private var saveTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private var handledWatchIDs: [String] = []
    private var usingHealthData = false
    private let isPreview: Bool
    private let health = HealthKitService()
    private let link = WatchConnectivityManager()

    var level: Int { xp / 100 + 1 }
    var xpIntoLevel: Int { xp % 100 }

    var forecast: [GlucosePoint] {
        GlucoseForecast.next60Minutes(from: points)
    }

    var loggedMealToday: Bool {
        meals.contains { Calendar.current.isDateInToday($0.date) }
    }

    var walkedToday: Bool {
        checkIns.contains { Calendar.current.isDateInToday($0.date) && $0.did != .notToday }
    }

    var coachedToday: Bool {
        sessions.contains { Calendar.current.isDateInToday($0.date) }
    }

    var positiveCheckIns: Int {
        checkIns.filter { $0.did != .notToday }.count
    }

    var checkInsThisWeek: Int {
        let calendar = Calendar.current
        return checkIns.filter {
            calendar.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) && $0.did != .notToday
        }.count
    }

    var hardCheckIns: Int {
        checkIns.filter { $0.effort == .hard }.count
    }

    var todayMeals: [MealLog] {
        meals.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date > $1.date }
    }

    init(preview: Bool = false) {
        isPreview = preview
        points = GlucoseMath.simulated()
        if !preview && CommandLine.arguments.contains("-resetDemo") {
            Persistence.clear()
            SharedStore.clear()
        }
        if preview {
            didFinishOnboarding = true
            stage = .main
            watchLink = .connected
            cgmLink = .connected
            meals = [MealLog.previewToday] + MealLog.samples
            checkIns = [HabitCheckIn(did: .yes, feel: .lighter, effort: .easy)]
            suppressSave = false
            return
        }
        if let saved = Persistence.load(), saved.didFinishOnboarding {
            apply(saved)
        }
        observe()
        link.onMeal = { [weak self] food, id in
            Task { @MainActor in
                self?.addWatchMeal(food: food, id: id)
            }
        }
        link.activate()
        suppressSave = false
        if didFinishOnboarding {
            broadcast()
            refreshHealthIfNeeded()
        }
    }

    func connectWatch() {
        guard watchLink == .idle else { return }
        watchLink = .connecting
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            watchLink = .connected
        }
    }

    func connectCGM() {
        guard cgmLink == .idle else { return }
        cgmLink = .connecting
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            if Self.useRealHealthKit {
                await health.requestAccess()
                let fetched = await health.fetchGlucose(hours: 24)
                if !fetched.isEmpty {
                    points = fetched
                    usingHealthData = true
                }
                stepsToday = await health.fetchStepsToday()
                healthSleepHours = await health.fetchSleepHours()
            }
            cgmLink = .connected
        }
    }

    func skipConnect() {
        watchLink = .connected
        cgmLink = .connected
        stage = .dashboard
    }

    func goBack() {
        switch stage {
        case .connect: stage = .welcome
        case .dashboard: stage = .connect
        case .goal: stage = .dashboard
        default: break
        }
    }

    func finishOnboarding() {
        didFinishOnboarding = true
        tab = goal == .habits ? .habits : .meals
        stage = .main
        Persistence.save(persisted())
        broadcast()
    }

    func refreshClock() {
        guard stage == .main else { return }
        if !usingHealthData {
            points = GlucoseMath.simulated()
        }
        broadcast()
    }

    func addMeal(_ meal: MealLog) {
        meals.insert(meal, at: 0)
        xp += 15
        insightMeal = meal
    }

    func addWatchMeal(food: String, id: String) {
        guard !handledWatchIDs.contains(id) else { return }
        handledWatchIDs.append(id)
        if handledWatchIDs.count > 40 {
            handledWatchIDs.removeFirst(handledWatchIDs.count - 40)
        }
        let meal = MealLog(
            food: MealFood(rawValue: food) ?? .somethingElse,
            duration: .medium,
            contexts: [.desk],
            drink: .water,
            sugarSpoons: 0,
            feelings: [],
            sleepHours: healthSleepHours ?? 5.5,
            stress: .medium,
            rise: points.recentRise,
            carbsGrams: nil,
            insulinUnits: nil,
            sourceID: id
        )
        meals.insert(meal, at: 0)
        xp += 15
    }

    func addCheckIn(_ checkIn: HabitCheckIn) {
        checkIns.insert(checkIn, at: 0)
        if checkIn.did != .notToday {
            xp += 20
        }
    }

    func addSession(exercise: ExerciseKind, reps: Int) {
        sessions.insert(CoachSession(date: Date(), exercise: exercise, reps: reps), at: 0)
        xp += 10 + reps * 2
    }

    func openCoach(_ exercise: ExerciseKind) {
        tab = .habits
        coach = exercise
    }

    func growPlan() {
        plan.startMinutes = plan.growMinutes
        plan.growMinutes += 5
    }

    func swapPlan() {
        plan.variant = (plan.variant + 1) % 3
        plan.startMinutes = 5
        plan.growMinutes = 10
    }

    func restart() {
        suppressSave = true
        saveGeneration += 1
        saveTask?.cancel()
        Persistence.clear()
        SharedStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
        stage = .welcome
        tab = .home
        gamified = true
        goal = .meals
        watchLink = .idle
        cgmLink = .idle
        didFinishOnboarding = false
        points = GlucoseMath.simulated()
        meals = []
        checkIns = []
        sessions = []
        plan = HabitPlan()
        xp = 40
        streak = 3
        stepsToday = 0
        healthSleepHours = nil
        insightMeal = nil
        coach = nil
        showMe = false
        handledWatchIDs = []
        usingHealthData = false
        suppressSave = false
    }

    private func refreshHealthIfNeeded() {
        guard Self.useRealHealthKit, cgmLink == .connected else { return }
        Task {
            await health.requestAccess()
            let fetched = await health.fetchGlucose(hours: 24)
            if !fetched.isEmpty {
                points = fetched
                usingHealthData = true
            }
            stepsToday = await health.fetchStepsToday()
            healthSleepHours = await health.fetchSleepHours()
        }
    }

    private func observe() {
        cancellable = objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.scheduleSave()
            }
        }
    }

    private func scheduleSave() {
        guard !suppressSave, !isPreview, didFinishOnboarding else { return }
        saveGeneration += 1
        let token = saveGeneration
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            guard token == self.saveGeneration else { return }
            Persistence.save(self.persisted())
            self.broadcast()
        }
    }

    private func broadcast() {
        let snapshot = GlucoseSnapshot(points: points)
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        link.push(snapshot)
    }

    private func persisted() -> PersistedState {
        PersistedState(
            didFinishOnboarding: didFinishOnboarding,
            gamified: gamified,
            goal: goal,
            tab: tab,
            xp: xp,
            streak: streak,
            watchConnected: watchLink == .connected,
            cgmConnected: cgmLink == .connected,
            meals: meals,
            checkIns: checkIns,
            sessions: sessions,
            plan: plan,
            handledWatchIDs: handledWatchIDs
        )
    }

    private func apply(_ saved: PersistedState) {
        didFinishOnboarding = true
        stage = .main
        gamified = saved.gamified
        goal = saved.goal
        tab = saved.tab
        xp = saved.xp
        streak = saved.streak
        watchLink = saved.watchConnected ? .connected : .idle
        cgmLink = saved.cgmConnected ? .connected : .idle
        meals = saved.meals
        checkIns = saved.checkIns
        sessions = saved.sessions
        plan = saved.plan
        handledWatchIDs = saved.handledWatchIDs
    }
}
