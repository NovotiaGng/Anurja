import Foundation

/// Talks to the Anurja backend (backend/anurja_api). Everything is saved on
/// the phone first; the server is an optional mirror plus a place where the
/// models can learn across the person's full history.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()
    static let defaultServer = "http://localhost:8000"
    private static let serverKey = "anurja.serverURL"

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    var serverString: String {
        get { UserDefaults.standard.string(forKey: Self.serverKey) ?? Self.defaultServer }
        set { UserDefaults.standard.set(newValue, forKey: Self.serverKey) }
    }

    private var base: URL? {
        URL(string: serverString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Sync

    struct SyncResult {
        var uploaded: Int
    }

    func sync(profile: UserProfile, glucose: [GlucosePoint]) async throws -> SyncResult {
        let store = LocalDatabase.shared
        let meals = store.unsynced(.meals, as: MealLog.self)
        let insulin = store.unsynced(.insulin, as: InsulinLog.self)
        let checkIns = store.unsynced(.checkins, as: HabitCheckIn.self)
        let sessions = store.unsynced(.sessions, as: CoachSession.self)
        let body = SyncBody(
            profile: ProfileDTO(profile),
            meals: meals.map { MealDTO($0.value) },
            insulin: insulin.map { InsulinDTO($0.value) },
            checkins: checkIns.map { CheckInDTO($0.value) },
            sessions: sessions.map { SessionDTO($0.value) },
            glucose: glucose.suffix(96).map { GlucoseDTO(time: $0.time, value: $0.value) }
        )
        let _: SyncReply = try await send("api/users/\(profile.id)/sync", body: body)
        let ids = meals.map(\.id) + insulin.map(\.id) + checkIns.map(\.id) + sessions.map(\.id)
        store.markSynced(ids: ids)
        return SyncResult(uploaded: ids.count)
    }

    func predictRise(meal: MealLog, userID: String) async throws -> RisePrediction {
        struct Body: Encodable { var userId: String; var meal: MealDTO }
        struct Reply: Decodable { var rise: Double; var populationRise: Double; var personalisedFrom: Int }
        let reply: Reply = try await send("api/ml/predict-rise", body: Body(userId: userID, meal: MealDTO(meal)))
        return RisePrediction(
            rise: Int(reply.rise.rounded()),
            populationRise: Int(reply.populationRise.rounded()),
            personalisedFrom: reply.personalisedFrom,
            source: .server
        )
    }

    func health() async -> Bool {
        guard let url = base?.appendingPathComponent("health") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Transport

    private func send<Body: Encodable, Reply: Decodable>(_ path: String, body: Body) async throws -> Reply {
        guard let url = base?.appendingPathComponent(path) else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.status((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try decoder.decode(Reply.self, from: data)
    }
}

enum APIError: LocalizedError {
    case badURL
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: String(localized: "Server address is not valid")
        case let .status(code): String(localized: "Server replied \(code)")
        }
    }
}

// MARK: - Wire format (snake_case on the wire, see backend/anurja_api/main.py)

private struct SyncReply: Decodable { var ok: Bool }

private struct SyncBody: Encodable {
    var profile: ProfileDTO
    var meals: [MealDTO]
    var insulin: [InsulinDTO]
    var checkins: [CheckInDTO]
    var sessions: [SessionDTO]
    var glucose: [GlucoseDTO]
}

private struct ProfileDTO: Encodable {
    var name: String
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var allergies: [String]
    var takesInsulin: Bool
    var insulinType: String?
    var medicines: [MedicineDTO]
    var carbTarget: Int

    init(_ profile: UserProfile) {
        name = profile.name
        age = profile.age
        heightCm = profile.heightCm
        weightKg = profile.weightKg
        allergies = profile.allergies.map(\.rawValue).sorted()
        takesInsulin = profile.takesInsulin
        insulinType = profile.insulinType?.rawValue
        medicines = profile.medicines.map { MedicineDTO(name: $0.name, dose: $0.dose, timing: $0.timing.rawValue) }
        carbTarget = profile.carbTarget
    }
}

private struct MedicineDTO: Encodable {
    var name: String
    var dose: String
    var timing: String
}

struct MealDTO: Encodable {
    var id: String
    var date: Date
    var foodId: String
    var foodName: String
    var group: String
    var servings: Double
    var carbsGrams: Int?
    var duration: String
    var contexts: [String]
    var drink: String?
    var sugarSpoons: Int
    var feelings: [String]
    var sleepHours: Double
    var stress: String
    var hour: Int
    var rise: Int?

    init(_ meal: MealLog) {
        id = meal.id.uuidString
        date = meal.date
        foodId = meal.foodItem.id
        foodName = meal.displayName
        group = meal.food.rawValue
        servings = meal.servings ?? 1
        carbsGrams = meal.carbsGrams
        duration = meal.duration.rawValue
        contexts = meal.contexts.map(\.rawValue).sorted()
        drink = meal.drink?.rawValue
        sugarSpoons = meal.sugarSpoons
        feelings = meal.feelings.map(\.rawValue).sorted()
        sleepHours = meal.sleepHours
        stress = meal.stress.rawValue
        hour = Calendar.current.component(.hour, from: meal.date)
        rise = meal.rise
    }
}

private struct InsulinDTO: Encodable {
    var id: String
    var date: Date
    var units: Double
    var relation: String
    var mealId: String?

    init(_ log: InsulinLog) {
        id = log.id.uuidString
        date = log.date
        units = log.units
        relation = log.relation.rawValue
        mealId = log.mealID?.uuidString
    }
}

private struct CheckInDTO: Encodable {
    var id: String
    var date: Date
    var did: String
    var feel: String
    var effort: String
    var steps: Int?

    init(_ checkIn: HabitCheckIn) {
        id = checkIn.id.uuidString
        date = checkIn.date
        did = checkIn.did.rawValue
        feel = checkIn.feel.rawValue
        effort = checkIn.effort.rawValue
        steps = checkIn.steps
    }
}

private struct SessionDTO: Encodable {
    var id: String
    var date: Date
    var exercise: String
    var reps: Int

    init(_ session: CoachSession) {
        id = session.id.uuidString
        date = session.date
        exercise = session.exercise.rawValue
        reps = session.reps
    }
}

private struct GlucoseDTO: Encodable {
    var time: Date
    var value: Double
}
