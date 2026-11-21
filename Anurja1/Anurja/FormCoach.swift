import CoreGraphics
import CoreML
import Foundation
import simd
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Body checkpoints

/// One body position an exercise asks for, tested on every camera frame.
struct FormCheck: Identifiable {
    enum Kind {
        /// Must happen at least once during the rep (depth, lockout).
        case reach
        /// Must hold for most of the rep (chest tall, elbows in).
        case hold
    }

    let id: String
    let title: String
    /// Said live when the checkpoint is missed, before the tip: "Knees caving in".
    let fault: String
    let tip: String
    let kind: Kind
    /// Joints this check reads; coloured green or red on the live skeleton.
    let joints: [BodyJoint]
    let test: ([BodyJoint: CGPoint]) -> Bool?

    var correction: String { "\(fault). \(tip)" }
}

private let legs: [BodyJoint] = [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
private let torso: [BodyJoint] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip]
private let arms: [BodyJoint] = [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]

private func knee(_ j: [BodyJoint: CGPoint]) -> Double? {
    averaged(left: jointAngle(j, .leftHip, .leftKnee, .leftAnkle), right: jointAngle(j, .rightHip, .rightKnee, .rightAnkle))
}

private func bentKnee(_ j: [BodyJoint: CGPoint]) -> Double? {
    minimum(jointAngle(j, .leftHip, .leftKnee, .leftAnkle), jointAngle(j, .rightHip, .rightKnee, .rightAnkle))
}

/// Shoulder–hip–knee: about 180 when standing straight.
private func hip(_ j: [BodyJoint: CGPoint]) -> Double? {
    averaged(left: jointAngle(j, .leftShoulder, .leftHip, .leftKnee), right: jointAngle(j, .rightShoulder, .rightHip, .rightKnee))
}

private func raisedKnee(_ j: [BodyJoint: CGPoint]) -> Double? {
    minimum(jointAngle(j, .leftShoulder, .leftHip, .leftKnee), jointAngle(j, .rightShoulder, .rightHip, .rightKnee))
}

private func elbow(_ j: [BodyJoint: CGPoint]) -> Double? {
    averaged(left: jointAngle(j, .leftShoulder, .leftElbow, .leftWrist), right: jointAngle(j, .rightShoulder, .rightElbow, .rightWrist))
}

/// Hip–shoulder–elbow: about 0 with arms by the sides, 90 at shoulder height.
private func upperArm(_ j: [BodyJoint: CGPoint]) -> Double? {
    averaged(left: jointAngle(j, .leftHip, .leftShoulder, .leftElbow), right: jointAngle(j, .rightHip, .rightShoulder, .rightElbow))
}

/// Shoulder–hip–ankle: 180 is a straight plank line.
private func bodyLine(_ j: [BodyJoint: CGPoint]) -> Double? {
    averaged(left: jointAngle(j, .leftShoulder, .leftHip, .leftAnkle), right: jointAngle(j, .rightShoulder, .rightHip, .rightAnkle))
}

/// Degrees a segment leans away from vertical (0 = straight up and down).
private func lean(_ top: CGPoint?, _ bottom: CGPoint?) -> Double? {
    guard let top, let bottom else { return nil }
    let dx = abs(top.x - bottom.x) * 0.75
    let dy = bottom.y - top.y
    guard dy > 0 else { return 90 }
    return atan(dx / dy) * 180 / .pi
}

private func torsoLean(_ j: [BodyJoint: CGPoint]) -> Double? {
    averaged(left: lean(j[.leftShoulder], j[.leftHip]), right: lean(j[.rightShoulder], j[.rightHip]))
}

/// Shin lean of whichever leg is bent more (the front leg in a split squat).
private func frontShinLean(_ j: [BodyJoint: CGPoint]) -> Double? {
    let left = jointAngle(j, .leftHip, .leftKnee, .leftAnkle)
    let right = jointAngle(j, .rightHip, .rightKnee, .rightAnkle)
    switch (left, right) {
    case let (l?, r?): return l <= r ? lean(j[.leftKnee], j[.leftAnkle]) : lean(j[.rightKnee], j[.rightAnkle])
    case (_?, nil): return lean(j[.leftKnee], j[.leftAnkle])
    case (nil, _?): return lean(j[.rightKnee], j[.rightAnkle])
    default: return nil
    }
}

/// Knees at least 80% as far apart as the ankles while the legs are bent.
/// Same numbers the model sees (feature 35 is the knee/ankle gap ratio).
private func kneesTrack(_ j: [BodyJoint: CGPoint]) -> Bool? {
    guard let f = FormFeatures.vector(j) else { return nil }
    return min(f[24], f[25]) * 180 >= 150 || f[35] * 3 >= 0.8
}

private func below(_ value: Double?, _ limit: Double) -> Bool? { value.map { $0 <= limit } }
private func above(_ value: Double?, _ limit: Double) -> Bool? { value.map { $0 >= limit } }

extension ExerciseKind {
    // ponytail: thresholds are first guesses from the cue sheet. This is the
    // calibration table: tune them against recorded sets from real users.
    var formChecks: [FormCheck] {
        switch self {
        case .squat:
            [
                FormCheck(id: "range", title: String(localized: "Hips down to knee level"), fault: String(localized: "Not low enough"), tip: furtherCue, kind: .reach, joints: legs) { below(knee($0), depthAngle) },
                FormCheck(id: "knees", title: String(localized: "Knees over your toes"), fault: String(localized: "Knees caving in"), tip: String(localized: "Push your knees out over your toes"), kind: .hold, joints: legs) { kneesTrack($0) },
                FormCheck(id: "chest", title: String(localized: "Chest stays tall"), fault: String(localized: "Chest dropping"), tip: String(localized: "Keep your chest up and eyes forward as you sit back"), kind: .hold, joints: torso) { below(torsoLean($0), 45) },
                FormCheck(id: "stand", title: String(localized: "Stand up fully at the top"), fault: String(localized: "Not standing fully"), tip: String(localized: "Squeeze your glutes and straighten your hips at the top"), kind: .reach, joints: torso + legs) { above(hip($0), 155) }
            ]
        case .chairStand:
            [
                FormCheck(id: "range", title: String(localized: "Sit all the way down"), fault: String(localized: "Not sitting all the way"), tip: String(localized: "Lower slowly until you touch the chair"), kind: .reach, joints: legs) { below(knee($0), depthAngle) },
                FormCheck(id: "knees", title: String(localized: "Knees over your toes"), fault: String(localized: "Knees caving in"), tip: String(localized: "Push your knees out over your toes"), kind: .hold, joints: legs) { kneesTrack($0) },
                FormCheck(id: "chest", title: String(localized: "Chest up as you rise"), fault: String(localized: "Back rounding"), tip: String(localized: "Lean forward from the hips, not by rounding your back"), kind: .hold, joints: torso) { below(torsoLean($0), 55) },
                FormCheck(id: "stand", title: String(localized: "Stand up tall"), fault: String(localized: "Not standing tall"), tip: furtherCue, kind: .reach, joints: torso + legs) { above(hip($0), 155) }
            ]
        case .lunge:
            [
                FormCheck(id: "range", title: String(localized: "Front knee bends to about 90°"), fault: String(localized: "Not low enough"), tip: furtherCue, kind: .reach, joints: legs) { below(bentKnee($0), depthAngle) },
                FormCheck(id: "upright", title: String(localized: "Body stays upright"), fault: String(localized: "Leaning forward"), tip: String(localized: "Keep your shoulders stacked over your hips"), kind: .hold, joints: torso) { below(torsoLean($0), 25) },
                FormCheck(id: "knee", title: String(localized: "Front knee over the ankle"), fault: String(localized: "Front knee too far forward"), tip: String(localized: "Take a slightly longer step so the knee stays over the ankle"), kind: .hold, joints: legs) { below(frontShinLean($0), 25) }
            ]
        case .march:
            [
                FormCheck(id: "range", title: String(localized: "Knee up to hip height"), fault: String(localized: "Knee not high enough"), tip: furtherCue, kind: .reach, joints: torso + legs) { below(raisedKnee($0), depthAngle) },
                FormCheck(id: "tall", title: String(localized: "Stand tall, no leaning back"), fault: String(localized: "Leaning back"), tip: String(localized: "Brace your stomach and keep your shoulders over your hips"), kind: .hold, joints: torso) { below(torsoLean($0), 15) }
            ]
        case .wallPushup:
            [
                FormCheck(id: "range", title: String(localized: "Chest close to the wall"), fault: String(localized: "Not close enough to the wall"), tip: furtherCue, kind: .reach, joints: arms) { below(elbow($0), depthAngle) },
                FormCheck(id: "line", title: String(localized: "Body in a straight line"), fault: String(localized: "Hips sagging or sticking out"), tip: String(localized: "Tighten your stomach and glutes so your hips don't sag or stick out"), kind: .hold, joints: torso + legs) { above(bodyLine($0), 160) },
                FormCheck(id: "lockout", title: String(localized: "Arms straight at the top"), fault: String(localized: "Arms not straight"), tip: String(localized: "Push all the way back until your arms are straight"), kind: .reach, joints: arms) { above(elbow($0), 155) }
            ]
        case .curl:
            [
                FormCheck(id: "range", title: String(localized: "Curl all the way up"), fault: String(localized: "Not curling all the way"), tip: furtherCue, kind: .reach, joints: arms) { below(elbow($0), depthAngle) },
                FormCheck(id: "elbows", title: String(localized: "Elbows stay by your sides"), fault: String(localized: "Elbows drifting forward"), tip: String(localized: "Pin your elbows to your ribs so only your forearms move"), kind: .hold, joints: arms + torso) { below(upperArm($0), 30) },
                FormCheck(id: "lower", title: String(localized: "Lower all the way down"), fault: String(localized: "Not lowering all the way"), tip: String(localized: "Straighten your arms fully before the next curl"), kind: .reach, joints: arms) { above(elbow($0), 145) }
            ]
        case .press:
            [
                FormCheck(id: "range", title: String(localized: "Hands down to shoulder level"), fault: String(localized: "Not lowering to shoulders"), tip: furtherCue, kind: .reach, joints: arms) { below(elbow($0), depthAngle) },
                FormCheck(id: "lockout", title: String(localized: "Arms fully straight overhead"), fault: String(localized: "Arms not fully straight"), tip: String(localized: "Press until your elbows are straight, biceps by your ears"), kind: .reach, joints: arms) { above(elbow($0), 160) },
                FormCheck(id: "still", title: String(localized: "Body stays still"), fault: String(localized: "Leaning back"), tip: String(localized: "Avoid leaning back; squeeze your glutes and stomach"), kind: .hold, joints: torso) { below(torsoLean($0), 12) }
            ]
        case .lateralRaise:
            [
                FormCheck(id: "range", title: String(localized: "Arms up to shoulder height"), fault: String(localized: "Arms below shoulder height"), tip: furtherCue, kind: .reach, joints: arms + torso) { above(upperArm($0), 180 - depthAngle) },
                FormCheck(id: "elbows", title: String(localized: "Arms long, elbows soft"), fault: String(localized: "Elbows bending"), tip: String(localized: "Keep a slight bend but don't fold your elbows"), kind: .hold, joints: arms) { above(elbow($0), 140) },
                FormCheck(id: "still", title: String(localized: "No swinging"), fault: String(localized: "Swinging"), tip: String(localized: "Lift with your shoulders, not by rocking your body"), kind: .hold, joints: torso) { below(torsoLean($0), 12) }
            ]
        }
    }

    /// Strength moves get protein-forward meal ideas; the march is light cardio.
    var isStrength: Bool { self != .march }
}

// MARK: - Learned checkpoint model

extension FormFeatures {
    static let joints: [BodyJoint] = [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist,
                                      .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]

    /// Vision joints (0...1 of the frame, y down) to features; nil unless all 12 are visible.
    static func vector(_ joints: [BodyJoint: CGPoint]) -> [Double]? {
        var points: [SIMD2<Double>] = []
        for joint in Self.joints {
            guard let p = joints[joint] else { return nil }
            // Same 3:4 frame aspect as jointAngle().
            points.append(SIMD2(p.x * 0.75, p.y))
        }
        return vector(points)
    }
}

/// One camera frame the coach scored, kept for the set so the user can correct it.
struct FormSample {
    var features: [Double]
    var scores: [Double]
}

/// A Core ML form model (Anurja/FormModels/Form<Exercise>.mlmodel, trained on
/// UI-PRMD by tools/formcoach). Output order and which checkpoints it reads
/// come from the model's metadata.
final class FormModel: @unchecked Sendable {
    let model: MLModel
    /// "form_ok" followed by FormCheck ids.
    let outputs: [String]
    /// Outputs that beat the plain 2D rule on validation; the rest use the rule.
    let useModel: [String]

    init(model: MLModel) {
        self.model = model
        let meta = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String] ?? [:]
        outputs = (meta["outputs"] ?? "").split(separator: ",").map(String.init)
        useModel = (meta["useModel"] ?? "").split(separator: ",").map(String.init)
    }

    static func array(_ values: [Double]) -> MLMultiArray? {
        guard let a = try? MLMultiArray(shape: [NSNumber(value: values.count)], dataType: .double) else { return nil }
        for (i, v) in values.enumerated() { a[i] = NSNumber(value: v) }
        return a
    }

    func predict(_ features: [Double]) -> [Double]? {
        guard let input = Self.array(features),
              let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["features": input])),
              let checks = out.featureValue(for: "checks")?.multiArrayValue else { return nil }
        return (0..<checks.count).map { checks[$0].doubleValue }
    }
}

/// Loads each exercise's model: the user's personalised copy if they've
/// corrected the coach, else the bundled one. Corrections retrain the model's
/// last layer on this device with MLUpdateTask; nothing leaves the phone.
enum FormModels {
    private static var cache: [ExerciseKind: FormModel] = [:]
    private static let lock = NSLock()

    private static var config: MLModelConfiguration {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly  // tiny network; CPU is fastest and the only option for updates
        return config
    }

    private static func name(_ exercise: ExerciseKind) -> String {
        "Form" + exercise.rawValue.prefix(1).uppercased() + exercise.rawValue.dropFirst()
    }

    private static func personalURL(_ exercise: ExerciseKind) -> URL {
        URL.applicationSupportDirectory.appending(path: "FormModels/\(name(exercise)).mlmodelc", directoryHint: .isDirectory)
    }

    /// Compiled model to start from: personalised if present, else bundled.
    private static func sourceURL(_ exercise: ExerciseKind) -> URL? {
        let personal = personalURL(exercise)
        if FileManager.default.fileExists(atPath: personal.path) { return personal }
        return Bundle.main.url(forResource: name(exercise), withExtension: "mlmodelc")
    }

    static func model(for exercise: ExerciseKind) -> FormModel? {
        lock.withLock {
            if let cached = cache[exercise] { return cached }
            guard let url = sourceURL(exercise), let model = try? MLModel(contentsOf: url, configuration: config) else { return nil }
            let wrapped = FormModel(model: model)
            cache[exercise] = wrapped
            return wrapped
        }
    }

    /// Retrains the last layer on this set's frames. Outputs the user didn't
    /// correct keep the model's own score as the target, so only the corrected
    /// checkpoints move.
    /// - corrections: check id -> what the user says really happened over the set.
    static func personalise(_ exercise: ExerciseKind, samples: [FormSample], corrections: [String: Bool],
                            kinds: [String: FormCheck.Kind]) async {
        guard let current = model(for: exercise), let source = sourceURL(exercise),
              !samples.isEmpty, !corrections.isEmpty else { return }
        var targets = samples.map(\.scores)
        for (id, didHit) in corrections {
            guard let k = current.outputs.firstIndex(of: id) else { continue }
            if didHit, kinds[id] == .reach {
                // "I did reach it": the frames closest to it were the hits.
                let cut = samples.map { $0.scores[k] }.sorted(by: >)[max(0, samples.count / 7 - 1)]
                for n in samples.indices where samples[n].scores[k] >= cut { targets[n][k] = 1 }
            } else {
                for n in samples.indices { targets[n][k] = didHit ? 1 : 0 }
            }
        }
        let rows: [MLFeatureProvider] = zip(samples, targets).compactMap { sample, target in
            guard let x = FormModel.array(sample.features), let y = FormModel.array(target) else { return nil }
            return try? MLDictionaryFeatureProvider(dictionary: ["features": x, "checks_true": y])
        }
        let updated: MLModel? = await withCheckedContinuation { done in
            do {
                let task = try MLUpdateTask(forModelAt: source, trainingData: MLArrayBatchProvider(array: rows),
                                            configuration: config) { context in
                    let personal = personalURL(exercise)
                    let staging = personal.deletingLastPathComponent().appending(path: UUID().uuidString + ".mlmodelc")
                    do {
                        try FileManager.default.createDirectory(at: personal.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try context.model.write(to: staging)
                        if FileManager.default.fileExists(atPath: personal.path) {
                            _ = try FileManager.default.replaceItemAt(personal, withItemAt: staging)
                        } else {
                            try FileManager.default.moveItem(at: staging, to: personal)
                        }
                        done.resume(returning: try MLModel(contentsOf: personal, configuration: config))
                    } catch {
                        try? FileManager.default.removeItem(at: staging)
                        done.resume(returning: nil)
                    }
                }
                task.resume()
            } catch {
                done.resume(returning: nil)
            }
        }
        guard let updated else { return }
        lock.withLock { cache[exercise] = FormModel(model: updated) }
    }

    // ponytail: no "reset my coach" button yet; deleting the app resets it. Add one to Me if users ask.
}

// MARK: - Meal ideas after a workout

struct MealIdea: Identifiable, Hashable {
    let item: FoodItem
    var reason: String
    var id: String { item.id }
}

enum MealIdeas {
    private static let skipped: Set<String> = ["Sweets", "Drinks"]

    /// Ranks the food library for this person: allergy-safe only, favouring
    /// foods they've eaten with a gentle rise, protein after strength work,
    /// fiber and lower GI always.
    static func pick(profile: UserProfile, meals: [MealLog], exercise: ExerciseKind, count: Int = 3) -> [MealIdea] {
        var rises: [String: [Int]] = [:]
        var eatenCategories: Set<String> = []
        for meal in meals {
            rises[meal.foodItem.id, default: []].append(meal.rise)
            eatenCategories.insert(meal.foodItem.category)
        }
        let proteinWeight = exercise.isStrength ? 0.8 : 0.4
        let scored = FoodLibrary.all
            .filter { $0.isSafe(for: profile) && !skipped.contains($0.category) }
            .map { item -> (MealIdea, Double) in
                let past = rises[item.id].map { Double($0.reduce(0, +)) / Double($0.count) }
                // Carbs and GI weigh most: this is for people managing blood sugar.
                var score = item.protein * proteinWeight + item.fiber * 0.8
                    - item.carbs * 0.2 - max(0, item.gi - 55) * 0.3
                if eatenCategories.contains(item.category) { score += 3 }
                if let past {
                    score += past < 40 ? 6 : (past > 55 ? -8 : 2)
                }
                return (MealIdea(item: item, reason: reason(for: item, pastRise: past, exercise: exercise)), score)
            }
            .sorted { $0.1 > $1.1 }
        // One idea per category so the list isn't three kinds of dal.
        var seen: Set<String> = []
        var picks: [MealIdea] = []
        for (idea, _) in scored where !seen.contains(idea.item.category) {
            seen.insert(idea.item.category)
            picks.append(idea)
            if picks.count == count { break }
        }
        return picks
    }

    static func pastRise(of item: FoodItem, in meals: [MealLog]) -> Int? {
        let rises = meals.filter { $0.foodItem.id == item.id }.map(\.rise)
        return rises.isEmpty ? nil : rises.reduce(0, +) / rises.count
    }

    private static func reason(for item: FoodItem, pastRise: Double?, exercise: ExerciseKind) -> String {
        if let pastRise, pastRise < 40 {
            return String(localized: "You've had this before with a gentle rise of about \(Int(pastRise)) mg/dL")
        }
        if exercise.isStrength, item.protein >= 10 {
            return String(localized: "\(Int(item.protein)) g protein to help your muscles recover")
        }
        return String(localized: "\(Int(item.fiber)) g fiber for a steadier glucose level")
    }
}

// MARK: - On-device language model (Apple Foundation Models)

/// Writes coaching text with Apple's on-device model. Every call returns nil
/// when the model isn't available, and callers keep their rule-based text.
enum CoachAI {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    private static var language: String {
        Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"
    }

    private static let rules = """
    You are a warm, encouraging exercise coach inside a wellness app for people managing blood sugar. \
    Use plain, simple words. Never give medical advice, never mention medicine or insulin doses, \
    and never promise health outcomes. Reply in \(language).
    """

    /// Two-sentence note on the set: one strength, the one fix that matters most.
    static func setNote(exercise: ExerciseKind, reps: Int, report: FormReport) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isAvailable else { return nil }
        let session = LanguageModelSession(instructions: rules)
        let prompt = """
        The person just did a set of \(exercise.englishName) with \(reps) clean reps.
        What they did well: \(report.good.joined(separator: "; ")).
        What to improve: \(report.improve.joined(separator: "; ")).
        Write exactly two short sentences: praise one specific thing, then give the single most useful form tip for next time.
        """
        return try? await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }

    /// Rewrites the reason under each meal idea for this workout. The foods
    /// themselves are already picked and allergy-checked, so the model only
    /// explains them; it can't add or swap a food.
    static func personalise(_ ideas: [MealIdea], exercise: ExerciseKind, reps: Int, meals: [MealLog]) async -> [MealIdea]? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isAvailable, !ideas.isEmpty else { return nil }
        let session = LanguageModelSession(instructions: rules)
        let list = ideas.enumerated().map { index, idea in
            let item = idea.item
            let past = MealIdeas.pastRise(of: item, in: meals).map { "their glucose rose about \($0) mg/dL last time" } ?? "not eaten before"
            return "\(index + 1). \(item.name) (\(item.serving)): \(Int(item.protein)) g protein, \(Int(item.fiber)) g fiber, \(Int(item.carbs)) g carbs, GI \(Int(item.gi)); \(past)"
        }.joined(separator: "\n")
        let prompt = """
        The person just finished \(reps) reps of \(exercise.englishName) (\(exercise.isStrength ? "strength" : "light cardio")).
        These meals were picked for them:
        \(list)
        For each meal, in the same order, write one short sentence on why it suits them after this workout.
        """
        guard let reasons = try? await session.respond(to: prompt, generating: MealReasons.self).content.reasons,
              reasons.count == ideas.count else { return nil }
        return zip(ideas, reasons).map { idea, reason in
            var idea = idea
            idea.reason = reason
            return idea
        }
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct MealReasons {
    @Guide(description: "One short sentence per meal, in the same order as the meals were listed")
    var reasons: [String]
}
#endif

extension ExerciseKind {
    /// Plain English name for model prompts (the UI uses the localised title).
    var englishName: String {
        switch self {
        case .squat: "bodyweight squats"
        case .chairStand: "chair sit-to-stands"
        case .lunge: "split squats"
        case .march: "knee-raise marching"
        case .wallPushup: "wall push-ups"
        case .curl: "arm curls"
        case .press: "overhead presses"
        case .lateralRaise: "side arm raises"
        }
    }
}
