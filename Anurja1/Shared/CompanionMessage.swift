import Foundation

protocol WatchConnectivityManaging: AnyObject {
    func activate()
    func handle(payload: [String: Any])
}

enum CompanionMessage {
    static let kind = "kind"
    static let meal = "meal"
    static let snapshotKind = "snapshot"
    static let food = "food"
    static let identifier = "id"
    static let value = "value"
    static let trend = "trend"
    static let range = "range"
    static let spark = "spark"
    static let updated = "updated"

    static func mealPayload(food: String, id: String) -> [String: Any] {
        [kind: meal, self.food: food, identifier: id]
    }

    static func snapshotPayload(_ snapshot: GlucoseSnapshot) -> [String: Any] {
        [
            kind: snapshotKind,
            value: snapshot.value,
            trend: snapshot.trendSymbol,
            range: snapshot.timeInRange,
            spark: snapshot.recent,
            updated: snapshot.updatedAt.timeIntervalSince1970
        ]
    }

    static func meal(from payload: [String: Any]) -> (food: String, id: String)? {
        guard (payload[kind] as? String) == meal,
              let foodName = payload[food] as? String,
              let mealID = payload[identifier] as? String else { return nil }
        return (foodName, mealID)
    }

    static func snapshot(from payload: [String: Any]) -> GlucoseSnapshot? {
        guard (payload[kind] as? String) == snapshotKind,
              let reading = payload[value] as? Double,
              let trendName = payload[trend] as? String,
              let range = payload[range] as? Int,
              let spark = payload[spark] as? [Double],
              let updated = payload[updated] as? TimeInterval else { return nil }
        return GlucoseSnapshot(
            value: reading,
            trendSymbol: trendName,
            timeInRange: range,
            recent: spark,
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }
}
