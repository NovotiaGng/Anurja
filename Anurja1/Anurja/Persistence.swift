import Foundation

struct PersistedState: Codable {
    var didFinishOnboarding: Bool
    var gamified: Bool
    var goal: Goal
    var tab: AppTab
    var xp: Int
    var streak: Int
    var watchConnected: Bool
    var cgmConnected: Bool
    var meals: [MealLog]
    var checkIns: [HabitCheckIn]
    var sessions: [CoachSession]
    var plan: HabitPlan
    var handledWatchIDs: [String]
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
