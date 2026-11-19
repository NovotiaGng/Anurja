import Foundation

enum SharedStore {
    static let appGroupID = "group.com.anurja.app"
    private static let fileName = "glucose.json"
    private static let defaultsKey = "anurja.glucose.snapshot"

    static func save(_ snapshot: GlucoseSnapshot) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot) else { return }
        if let url = fileURL() {
            try? data.write(to: url, options: .atomic)
        }
        UserDefaults(suiteName: appGroupID)?.set(data, forKey: defaultsKey)
    }

    static func load() -> GlucoseSnapshot? {
        if let url = fileURL(),
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(GlucoseSnapshot.self, from: data) {
            return snapshot
        }
        if let data = UserDefaults(suiteName: appGroupID)?.data(forKey: defaultsKey),
           let snapshot = try? JSONDecoder().decode(GlucoseSnapshot.self, from: data) {
            return snapshot
        }
        return nil
    }

    static func clear() {
        if let url = fileURL() {
            try? FileManager.default.removeItem(at: url)
        }
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: defaultsKey)
    }

    private static func fileURL() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        return container.appendingPathComponent(fileName)
    }
}
