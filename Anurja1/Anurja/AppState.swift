import Combine
import SwiftUI
import WidgetKit

@MainActor
final class AppState: ObservableObject {
    static var useRealHealthKit = false

    @Published var stage: Stage = .welcome
    @Published var tab: AppTab = .home
    @Published var watchLink: LinkState = .idle
    @Published var cgmLink: LinkState = .idle
    @Published var didFinishOnboarding = false
    @Published var profile = UserProfile()
    /// Up to seven days of readings, oldest first.
    @Published var points: [GlucosePoint] = []
    @Published var meals: [MealLog] = []
    @Published var insulinLogs: [InsulinLog] = []
    @Published var checkIns: [HabitCheckIn] = []
    @Published var sessions: [CoachSession] = []
    @Published var plan = HabitPlan()
    @Published var reminder: ReminderSlot = .off
    @Published var gmiHistory: [String: Double] = [:]
    @Published var stepsToday = 0
    @Published var caloriesToday = 0
    @Published var stepsLastHour = 0
    @Published var healthSleepHours: Double?
    @Published var insightMeal: MealLog?
    @Published var coach: ExerciseKind?
    @Published var showAddMeal = false
    @Published var showInsulin = false
    @Published var syncStatus: SyncStatus = .idle
    @Published private(set) var activity: ActivityRecommendation?

    let insights: any InsightProviding = RuleInsightEngine()

    private var suppressSave = true
    private var saveGeneration = 0
    private var saveTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private var handledWatchIDs: [String] = []
    private var usingHealthData = false
    private let isPreview: Bool
    private let health = HealthKitService()
    private let link = WatchConnectivityManager()
    private let motion = MotionService()
    private let database = LocalDatabase.shared

    // MARK: - Derived values

    /// The last 24 hours, used for headline numbers, widgets and the watch.
    var day: [GlucosePoint] { points.within(hours: 24) }

    func points(in range: TimeRange) -> [GlucosePoint] {
        points.within(hours: range.hours)
    }

    var forecast: [GlucosePoint] {
        GlucoseForecast.next60Minutes(from: points)
    }

    var forecastTone: ForecastTone {
        GlucoseForecast.tone(last: points.currentValue, forecast: forecast)
    }

    var lastMealDate: Date? {
        meals.map(\.date).max()
    }

    var gmi: Double {
        GlucoseTargets.gmi(meanGlucose: points.meanValue)
    }

    var previousGMI: Double? {
        gmiHistory[Self.monthKey(Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date())]
    }

    var loggedMealToday: Bool {
        meals.contains { Calendar.current.isDateInToday($0.date) }
    }

    var walkedToday: Bool {
        checkIns.contains { Calendar.current.isDateInToday($0.date) && $0.did != .notToday }
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

    var todayInsulin: [InsulinLog] {
        insulinLogs.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date > $1.date }
    }

    var carbsToday: Int {
        todayMeals.reduce(0) { $0 + $1.carbsEstimate }
    }

    /// Meals the "What helps you" model learns from. Sample meals fill in
    /// until the person has logged their own.
    var learningMeals: [MealLog] {
        meals.isEmpty ? MealLog.samples : meals
    }

    var whatHelps: WhatHelps {
        MLEngine.whatHelps(meals: learningMeals, profile: profile)
    }

    // MARK: - Lifecycle

    init(preview: Bool = false) {
        isPreview = preview
        points = GlucoseMath.simulated(days: 7)
        if !preview && CommandLine.arguments.contains("-resetDemo") {
            Persistence.clear()
            SharedStore.clear()
            LocalDatabase.shared.clear()
        }
        if preview {
            didFinishOnboarding = true
            stage = .main
            watchLink = .connected
            cgmLink = .connected
            profile.name = "Asha Rao"
            profile.age = 41
            profile.takesInsulin = true
            profile.insulinType = .rapid
            meals = [MealLog.previewToday] + MealLog.samples
            checkIns = [HabitCheckIn(did: .yes, feel: .lighter, effort: .easy)]
            evaluateActivity(notify: false)
            suppressSave = false
            return
        }
        NotificationService.shared.configure()
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
        evaluateActivity(notify: false)
        if didFinishOnboarding {
            broadcast()
            refreshHealthIfNeeded()
            sync()
        }
    }

    // MARK: - Onboarding

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
                await loadHealth()
            }
            cgmLink = .connected
        }
    }

    func skipConnect() {
        watchLink = .connected
        cgmLink = .connected
        stage = .aboutYou
    }

    func advance() {
        switch stage {
        case .welcome: stage = .connect
        case .connect: stage = .aboutYou
        case .aboutYou: stage = .allergies
        case .allergies: stage = .insulin
        case .insulin: stage = .medicines
        case .medicines: stage = .allSet
        case .allSet: finishOnboarding()
        case .main: break
        }
    }

    func goBack() {
        switch stage {
        case .connect: stage = .welcome
        case .aboutYou: stage = .connect
        case .allergies: stage = .aboutYou
        case .insulin: stage = .allergies
        case .medicines: stage = .insulin
        case .allSet: stage = .medicines
        default: break
        }
    }

    func finishOnboarding() {
        didFinishOnboarding = true
        tab = .home
        stage = .main
        recordMonthlyGMI()
        Persistence.save(persisted())
        broadcast()
        evaluateActivity(notify: false)
        Task {
            _ = await NotificationService.shared.requestAuthorization()
        }
        refreshHealthIfNeeded()
        sync()
    }

    // MARK: - Clock and health

    func refreshClock() {
        guard stage == .main else { return }
        if !usingHealthData {
            points = GlucoseMath.simulated(days: 7)
        }
        recordMonthlyGMI()
        broadcast()
        refreshHealthIfNeeded()
        evaluateActivity(notify: true)
    }

    func evaluateActivity(notify: Bool) {
        let recommendation = MLEngine.recommendActivity(
            points: points,
            lastMeal: lastMealDate,
            stepsLastHour: stepsLastHour,
            meals: meals,
            checkIns: checkIns,
            sessions: sessions
        )
        activity = recommendation
        if notify, profile.activityAlerts, !isPreview {
            NotificationService.shared.notifyIfNeeded(recommendation, glucose: points.currentValue)
        }
    }

    private func refreshHealthIfNeeded() {
        guard !isPreview else { return }
        Task {
            if Self.useRealHealthKit, cgmLink == .connected {
                await loadHealth()
            }
            let now = Date()
            if let recent = await motion.steps(from: now.addingTimeInterval(-3600), to: now) {
                stepsLastHour = recent
            }
            if stepsToday == 0, let today = await motion.steps(from: Calendar.current.startOfDay(for: now), to: now) {
                stepsToday = today
            }
        }
    }

    private func loadHealth() async {
        await health.requestAccess()
        let fetched = await health.fetchGlucose(hours: 24 * 7)
        if !fetched.isEmpty {
            points = fetched
            usingHealthData = true
        }
        stepsToday = await health.fetchStepsToday()
        caloriesToday = await health.fetchActiveCaloriesToday()
        healthSleepHours = await health.fetchSleepHours()
    }

    /// Est. GMI is stored once per calendar month so Home can compare it with
    /// last month.
    private func recordMonthlyGMI() {
        guard !points.isEmpty else { return }
        gmiHistory[Self.monthKey(Date())] = (gmi * 10).rounded() / 10
    }

    static func monthKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    // MARK: - Logging

    func addMeal(_ meal: MealLog) {
        meals.insert(meal, at: 0)
        database.save(meals: [meal])
        showAddMeal = false
        evaluateActivity(notify: false)
        sync()
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            insightMeal = meal
        }
    }

    func addInsulin(_ log: InsulinLog) {
        insulinLogs.insert(log, at: 0)
        insulinLogs.sort { $0.date > $1.date }
        database.save(insulin: [log])
        sync()
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
        database.save(meals: [meal])
        sync()
    }

    func addCheckIn(_ checkIn: HabitCheckIn) {
        checkIns.insert(checkIn, at: 0)
        database.save(checkIns: [checkIn])
        sync()
    }

    func addSession(exercise: ExerciseKind, reps: Int) {
        let session = CoachSession(date: Date(), exercise: exercise, reps: reps)
        sessions.insert(session, at: 0)
        database.save(sessions: [session])
        sync()
    }

    func openCoach(_ exercise: ExerciseKind) {
        tab = .habits
        coach = exercise
    }

    // MARK: - Daily session: walk, then today's exercises one after another

    /// Exercises still to run in the current session.
    @Published var sessionQueue: [ExerciseKind] = []
    @Published var walking = false

    func startDailySession() {
        tab = .habits
        sessionQueue = DayPlan.make(for: profile).queue
        walking = true
    }

    /// Called when the walk or a coach screen closes.
    func nextInSession() {
        guard !sessionQueue.isEmpty else { return }
        let next = sessionQueue.removeFirst()
        // Let the previous full-screen cover finish dismissing first.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            openCoach(next)
        }
    }

    func endSession() {
        sessionQueue = []
    }

    func openAddMeal() {
        tab = .meals
        showAddMeal = true
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

    func setReminder(_ slot: ReminderSlot, goal: String) {
        reminder = slot
        NotificationService.shared.scheduleReminder(slot, title: goal)
    }

    func predictRise(for meal: MealLog) async -> RisePrediction {
        let local = MLEngine.predictRise(for: meal, history: learningMeals)
        guard !isPreview else { return local }
        do {
            return try await APIClient.shared.predictRise(meal: meal, userID: profile.id)
        } catch {
            return local
        }
    }

    // MARK: - Sync

    func sync() {
        guard !isPreview, didFinishOnboarding else { return }
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            syncStatus = .syncing
            do {
                let result = try await APIClient.shared.sync(profile: profile, glucose: day)
                syncStatus = .synced(Date(), result.uploaded)
            } catch is CancellationError {
                return
            } catch {
                syncStatus = .offline(error.localizedDescription)
            }
        }
    }

    // MARK: - Reset

    func restart() {
        suppressSave = true
        saveGeneration += 1
        saveTask?.cancel()
        syncTask?.cancel()
        Persistence.clear()
        SharedStore.clear()
        database.clear()
        MealPhotoStore.clear()
        NotificationService.shared.clearAll()
        WidgetCenter.shared.reloadAllTimelines()
        stage = .welcome
        tab = .home
        watchLink = .idle
        cgmLink = .idle
        didFinishOnboarding = false
        profile = UserProfile()
        points = GlucoseMath.simulated(days: 7)
        meals = []
        insulinLogs = []
        checkIns = []
        sessions = []
        plan = HabitPlan()
        reminder = .off
        gmiHistory = [:]
        stepsToday = 0
        caloriesToday = 0
        stepsLastHour = 0
        healthSleepHours = nil
        insightMeal = nil
        coach = nil
        sessionQueue = []
        showAddMeal = false
        showInsulin = false
        syncStatus = .idle
        handledWatchIDs = []
        usingHealthData = false
        evaluateActivity(notify: false)
        suppressSave = false
    }

    // MARK: - Persistence

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
        let snapshot = GlucoseSnapshot(points: day)
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        link.push(snapshot)
    }

    private func persisted() -> PersistedState {
        PersistedState(
            didFinishOnboarding: didFinishOnboarding,
            tab: tab,
            watchConnected: watchLink == .connected,
            cgmConnected: cgmLink == .connected,
            meals: meals,
            checkIns: checkIns,
            sessions: sessions,
            plan: plan,
            handledWatchIDs: handledWatchIDs,
            profile: profile,
            insulinLogs: insulinLogs,
            reminder: reminder,
            gmiHistory: gmiHistory
        )
    }

    private func apply(_ saved: PersistedState) {
        didFinishOnboarding = true
        stage = .main
        tab = saved.tab
        watchLink = saved.watchConnected ? .connected : .idle
        cgmLink = saved.cgmConnected ? .connected : .idle
        plan = saved.plan
        handledWatchIDs = saved.handledWatchIDs
        profile = saved.profile ?? UserProfile()
        reminder = saved.reminder ?? .off
        gmiHistory = saved.gmiHistory ?? [:]

        // The SQLite store is the source of truth for logged records. Older
        // installs only had the JSON file, so copy those across once.
        let storedMeals = database.load(.meals, as: MealLog.self)
        if storedMeals.isEmpty, !saved.meals.isEmpty {
            database.save(meals: saved.meals)
            database.save(checkIns: saved.checkIns)
            database.save(sessions: saved.sessions)
            database.save(insulin: saved.insulinLogs ?? [])
        }
        meals = database.load(.meals, as: MealLog.self)
        insulinLogs = database.load(.insulin, as: InsulinLog.self)
        checkIns = database.load(.checkins, as: HabitCheckIn.self)
        sessions = database.load(.sessions, as: CoachSession.self)
        if meals.isEmpty { meals = saved.meals }
        if checkIns.isEmpty { checkIns = saved.checkIns }
        if sessions.isEmpty { sessions = saved.sessions }
    }
}
