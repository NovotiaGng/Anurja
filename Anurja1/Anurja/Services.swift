import CoreMotion
import Foundation
import UserNotifications

// MARK: - Notifications

/// Pop-up activity suggestions when glucose leaves the target range, and the
/// "Remind me" nudge from Your next step. Banners also show while the app is
/// open.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    private let lastAlertKey = "anurja.lastActivityAlert"
    private let lastStatusKey = "anurja.lastActivityStatus"
    private static let reminderID = "anurja.reminder"

    func configure() {
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Sends at most one alert per 45 minutes, and only when the status is
    /// high or low (or just changed into one of them).
    func notifyIfNeeded(_ recommendation: ActivityRecommendation, glucose: Double) {
        let defaults = UserDefaults.standard
        guard recommendation.status.needsAttention else {
            defaults.set(recommendation.status.rawValue, forKey: lastStatusKey)
            return
        }
        let changed = defaults.string(forKey: lastStatusKey) != recommendation.status.rawValue
        let last = defaults.double(forKey: lastAlertKey)
        let quietEnough = Date().timeIntervalSince1970 - last > 45 * 60
        guard changed || quietEnough else { return }
        defaults.set(recommendation.status.rawValue, forKey: lastStatusKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastAlertKey)

        let content = UNMutableNotificationContent()
        content.title = recommendation.status.title
        let actions = recommendation.actions.prefix(2).map(\.title).joined(separator: " · ")
        content.body = String(localized: "\(Int(glucose.rounded())) mg/dL. \(actions)")
        content.sound = .default
        content.interruptionLevel = recommendation.status == .low ? .timeSensitive : .active
        let request = UNNotificationRequest(identifier: "anurja.activity.\(UUID().uuidString)", content: content, trigger: nil)
        center.add(request)
    }

    func scheduleReminder(_ slot: ReminderSlot, title: String, mealHours: [Int] = [8, 13, 20]) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
        guard slot != .off else { return }
        let calendar = Calendar.current
        let now = Date()
        var fire: Date?
        switch slot {
        case .nextMeal:
            for hour in mealHours {
                if let date = calendar.date(bySettingHour: hour, minute: 30, second: 0, of: now), date > now {
                    fire = date
                    break
                }
            }
            if fire == nil, let first = mealHours.first, let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                fire = calendar.date(bySettingHour: first, minute: 30, second: 0, of: tomorrow)
            }
        case .tomorrowMorning:
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                fire = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
            }
        case .off:
            break
        }
        guard let fire else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your next step")
        content.body = title
        content.sound = .default
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: trigger))
    }

    func clearAll() {
        center.removeAllPendingNotificationRequests()
        UserDefaults.standard.removeObject(forKey: lastAlertKey)
        UserDefaults.standard.removeObject(forKey: lastStatusKey)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

// MARK: - Motion

/// Step counting from the iPhone's motion coprocessor. Used to detect the
/// walk after a meal without the person having to tick a box, and as the
/// recent-activity input to the activity model.
@MainActor
final class MotionService: ObservableObject {
    @Published var liveSteps = 0
    @Published var isWalking = false
    private let pedometer = CMPedometer()
    private let activity = CMMotionActivityManager()

    static var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    func steps(from start: Date, to end: Date) async -> Int? {
        guard CMPedometer.isStepCountingAvailable(), start < end else { return nil }
        let pedometer = pedometer
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                continuation.resume(returning: data?.numberOfSteps.intValue)
            }
        }
    }

    func startLive(from start: Date) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: start) { [weak self] data, _ in
            let steps = data?.numberOfSteps.intValue ?? 0
            Task { @MainActor in self?.liveSteps = steps }
        }
        if CMMotionActivityManager.isActivityAvailable() {
            activity.startActivityUpdates(to: .main) { [weak self] motion in
                guard let motion else { return }
                Task { @MainActor in self?.isWalking = motion.walking || motion.running }
            }
        }
    }

    func stop() {
        pedometer.stopUpdates()
        activity.stopActivityUpdates()
    }
}
