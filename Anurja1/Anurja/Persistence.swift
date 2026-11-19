import Foundation

/// Settings and a JSON snapshot of the app. Logged records also live in the
/// SQLite store (LocalDatabase). Fields added after 1.0 are optional so older
/// files still load.
struct PersistedState: Codable {
    var didFinishOnboarding: Bool
    var tab: AppTab
    var watchConnected: Bool
    var cgmConnected: Bool
    var meals: [MealLog]
    var checkIns: [HabitCheckIn]
    var sessions: [CoachSession]
    var plan: HabitPlan
    var handledWatchIDs: [String]
    var profile: UserProfile?
    var insulinLogs: [InsulinLog]?
    var reminder: ReminderSlot?
    var gmiHistory: [String: Double]?
}

enum Persistence {
    static func load() -> PersistedState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    static func save(_ state: PersistedState) {
        let folder = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Anurja", isDirectory: true).appendingPathComponent("state.json")
    }
}
