// Trains Anurja's form-checkpoint networks on real recordings (UI-PRMD).
//
//   cd Anurja1
//   swiftc -O -parse-as-library -o /tmp/train-form tools/formcoach/*.swift Anurja/FormFeatures.swift
//   /tmp/train-form tools/formcoach/data/uiprmd        # downloads the data first if it's missing
//
// Data: UI-PRMD, Vakanski, Jun, Paul, Baker, "A data set of human body movements
// for physical rehabilitation exercises", Data 3(1):2, 2018, doi:10.3390/data3010002.
// License: Open Data Commons PDDL v1.0 (public domain). Official page:
// https://webpages.uidaho.edu/ui-prmd/ . That host blocks scripted downloads in
// some regions, so this pulls the same Kinect files from a public GitHub mirror.
// Each of 10 healthy subjects did 10 reps of each movement correctly and 10
// reps deliberately "non-optimally".
//
// What the network learns
// - Input: what the phone sees. Each Kinect frame (3D, a real person) is
//   projected to a 2D camera view (side-on or front-on, as the app asks, over a
//   range of camera angles) and turned into FormFeatures.vector, the same
//   function the app runs on Vision body-pose joints.
// - Targets per frame: form_ok = UI-PRMD's correct/incorrect label; each
//   checkpoint (depth, knees caving, trunk lean...) measured on the true 3D
//   skeleton. A 2D camera at an angle can't measure these directly; learning to
//   undo that is the point.
// - Subjects 9-10 are held out (test). Subject 8 is validation: an output is
//   used by the app only if it beats the app's plain 2D rule there and training
//   has >= 3% misses to learn from.
//
// Writes Anurja/FormModels/Form<Exercise>.mlmodel (updatable Core ML, see
// CoreMLExport.swift) and tools/formcoach/report.json, scored through Core ML.

import CoreML
import Foundation
import simd

typealias V3 = SIMD3<Double>
typealias V2 = SIMD2<Double>

// MARK: - UI-PRMD Kinect forward kinematics

/// Kinect joint index for the app's 12 joints: lS rS lE rE lW rW lH rH lK rK lA rA.
let kinectJoints = [7, 11, 8, 12, 9, 13, 14, 18, 15, 19, 16, 20]
let (LS, RS, LE, RE, LW, RW, LH, RH, LK, RK, LA, RA) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
/// (joint, parent) chains; arms hang off the chest (2), legs off the waist (0).
let chains: [[(Int, Int)]] = [
    [(1, 0), (2, 1), (3, 2), (4, 3), (5, 4)],
    [(6, 2), (7, 6), (8, 7), (9, 8)],
    [(10, 2), (11, 10), (12, 11), (13, 12)],
    [(14, 0), (15, 14), (16, 15), (17, 16)],
    [(18, 0), (19, 18), (20, 19), (21, 20)],
]

/// MATLAB smooth(): moving average, windows shrink at the ends.
func smooth(_ a: [Double], _ w: Int) -> [Double] {
    guard a.count > w else { return a }
    return a.indices.map { i in
        let r = min(i, a.count - 1 - i, w / 2)
        return a[(i - r)...(i + r)].reduce(0, +) / Double(2 * r + 1)
    }
}

/// Euler degrees (g, b, a) -> Rz(a) Ry(b) Rx(g), as in the authors' code.
func rotation(_ e: V3) -> simd_double3x3 {
    let (g, b, a) = (e.x * .pi / 180, e.y * .pi / 180, e.z * .pi / 180)
    let rx = simd_double3x3(rows: [V3(1, 0, 0), V3(0, cos(g), -sin(g)), V3(0, sin(g), cos(g))])
    let ry = simd_double3x3(rows: [V3(cos(b), 0, sin(b)), V3(0, 1, 0), V3(-sin(b), 0, cos(b))])
    let rz = simd_double3x3(rows: [V3(cos(a), -sin(a), 0), V3(sin(a), cos(a), 0), V3(0, 0, 1)])
    return rz * ry * rx
}

func readTable(_ url: URL) throws -> [[Double]] {
    try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
        .map { $0.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces))! } }
}

/// (frames)[12] world positions in cm, y up.
func loadEpisode(positions: URL, angles: URL) throws -> [[V3]] {
    var pos = try readTable(positions), ang = try readTable(angles)
    let n = min(pos.count, ang.count)
    pos = Array(pos[..<n]); ang = Array(ang[..<n])
    let ps = (0..<66).map { c in smooth(pos.map { $0[c] }, 5) }
    let as_ = (0..<66).map { c in smooth(ang.map { $0[c] }, 23) }
    return (0..<n).map { f in
        let p = (0..<22).map { j in V3(ps[3 * j][f], ps[3 * j + 1][f], ps[3 * j + 2][f]) }
        let a = (0..<22).map { j in V3(as_[3 * j][f], as_[3 * j + 1][f], as_[3 * j + 2][f]) }
        var out = p
        for chain in chains {
            var rot = rotation(a[chain[0].1])
            for (k, (joint, parent)) in chain.enumerated() {
                if k > 0 { rot = rot * rotation(a[parent]) }
                out[joint] = rot * p[joint] + out[parent]
            }
        }
        return kinectJoints.map { out[$0] }
    }
}

// MARK: - 3D truth

func angle3(_ a: V3, _ b: V3, _ c: V3) -> Double {
    let u = a - b, v = c - b
    return acos(max(-1, min(1, simd_dot(u, v) / (simd_length(u) * simd_length(v) + 1e-9)))) * 180 / .pi
}

func fromVertical(_ v: V3) -> Double { acos(max(-1, min(1, v.y / (simd_length(v) + 1e-9)))) * 180 / .pi }

struct Truth {
    var knee, bentKnee, hip, raisedKnee, arm, raisedElbow, trunk, shin: Double
    var caving: Bool

    init(_ s: [V3]) {
        let kneeL = angle3(s[LH], s[LK], s[LA]), kneeR = angle3(s[RH], s[RK], s[RA])
        let hipL = angle3(s[LS], s[LH], s[LK]), hipR = angle3(s[RS], s[RH], s[RK])
        let armL = angle3(s[LH], s[LS], s[LE]), armR = angle3(s[RH], s[RS], s[RE])
        let elbowL = angle3(s[LS], s[LE], s[LW]), elbowR = angle3(s[RS], s[RE], s[RW])
        knee = (kneeL + kneeR) / 2
        bentKnee = min(kneeL, kneeR)
        hip = (hipL + hipR) / 2
        raisedKnee = min(hipL, hipR)
        arm = max(armL, armR)
        raisedElbow = armL >= armR ? elbowL : elbowR
        trunk = fromVertical((s[LS] + s[RS]) / 2 - (s[LH] + s[RH]) / 2)
        shin = kneeL <= kneeR ? fromVertical(s[LK] - s[LA]) : fromVertical(s[RK] - s[RA])
        // Knees caving: in the body's frontal plane, knees closer together than
        // the ankles while the legs are bent.
        var axis = s[RH] - s[LH]
        axis.y = 0
        axis = simd_normalize(axis)
        let kneeGap = simd_dot(s[RK] - s[LK], axis), ankleGap = simd_dot(s[RA] - s[LA], axis)
        caving = bentKnee < 150 && kneeGap < 0.8 * ankleGap
    }
}

// MARK: - 2D rules (the app's baseline), read back from the feature vector

struct Rule2D {
    let a: [Double], lean: [Double], ratio: Double
    init(_ f: [Double]) {
        a = f[24..<32].map { $0 * 180 }
        lean = f[32..<35].map { $0 * 90 }
        ratio = f[35] * 3
    }
    var knee: Double { (a[0] + a[1]) / 2 }
    var bentKnee: Double { min(a[0], a[1]) }
    var hip: Double { (a[2] + a[3]) / 2 }
    var raisedKnee: Double { min(a[2], a[3]) }
    var elbow: Double { (a[4] + a[5]) / 2 }
    var arm: Double { (a[6] + a[7]) / 2 }
    var shin: Double { a[0] <= a[1] ? lean[1] : lean[2] }
    var caving: Bool { bentKnee < 150 && ratio < 0.8 }
}

// MARK: - Exercises

struct Check {
    let id: String
    let truth: (Truth) -> Bool
    let rule: (Rule2D) -> Bool
}

struct Exercise {
    let name: String, movement: String, sideOn: Bool
    let checks: [Check]
}

// Ids match FormCheck ids in FormCoach.swift; thresholds match its rules,
// measured here in true 3D.
let exercises = [
    Exercise(name: "squat", movement: "01", sideOn: true, checks: [
        Check(id: "range", truth: { $0.knee <= 100 }, rule: { $0.knee <= 100 }),
        Check(id: "knees", truth: { !$0.caving }, rule: { !$0.caving }),
        Check(id: "chest", truth: { $0.trunk <= 45 }, rule: { $0.lean[0] <= 45 }),
        Check(id: "stand", truth: { $0.hip >= 155 }, rule: { $0.hip >= 155 })]),
    Exercise(name: "chairStand", movement: "05", sideOn: true, checks: [
        Check(id: "range", truth: { $0.knee <= 110 }, rule: { $0.knee <= 110 }),
        Check(id: "knees", truth: { !$0.caving }, rule: { !$0.caving }),
        Check(id: "chest", truth: { $0.trunk <= 55 }, rule: { $0.lean[0] <= 55 }),
        Check(id: "stand", truth: { $0.hip >= 155 }, rule: { $0.hip >= 155 })]),
    Exercise(name: "lunge", movement: "03", sideOn: true, checks: [  // UI-PRMD inline lunge
        Check(id: "range", truth: { $0.bentKnee <= 105 }, rule: { $0.bentKnee <= 105 }),
        Check(id: "upright", truth: { $0.trunk <= 25 }, rule: { $0.lean[0] <= 25 }),
        Check(id: "knee", truth: { $0.shin <= 25 }, rule: { $0.shin <= 25 })]),
    Exercise(name: "march", movement: "02", sideOn: false, checks: [  // UI-PRMD hurdle step
        Check(id: "range", truth: { $0.raisedKnee <= 115 }, rule: { $0.raisedKnee <= 115 }),
        Check(id: "tall", truth: { $0.trunk <= 15 }, rule: { $0.lean[0] <= 15 })]),
    Exercise(name: "lateralRaise", movement: "07", sideOn: false, checks: [  // UI-PRMD shoulder abduction
        Check(id: "range", truth: { $0.arm >= 75 }, rule: { $0.arm >= 75 }),
        Check(id: "elbows", truth: { $0.raisedElbow >= 140 }, rule: { $0.elbow >= 140 }),
        Check(id: "still", truth: { $0.trunk <= 12 }, rule: { $0.lean[0] <= 12 })]),
]

// MARK: - Projection and samples

struct RNG {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func uniform(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
    mutating func normal() -> Double { (-2 * log(max(next(), 1e-12))).squareRoot() * cos(2 * .pi * next()) }
}

/// Orthographic camera at `yaw` around the person, tilted by `pitch`: image x right, y down.
func project(_ s: [V3], yaw: Double, pitch: Double, mirror: Bool) -> [V2] {
    let y = yaw * .pi / 180, p = pitch * .pi / 180
    return s.map { v in
        let x = v.x * cos(y) + v.z * sin(y)
        let z = -v.x * sin(y) + v.z * cos(y)
        let up = v.y * cos(p) - z * sin(p)
        return V2(mirror ? -x : x, -up)
    }
}

struct Episode {
    let name: String
    let correct: Bool
    var x: [[Double]] = []
    var y: [[Double]] = []
}

let testSubjects: Set<Int> = [9, 10], valSubjects: Set<Int> = [8]

func samples(_ ex: Exercise, data: URL, rng: inout RNG) throws -> (train: [Episode], val: [Episode], test: [Episode]) {
    let yaws: [Double] = ex.sideOn ? [45, 60, 75, 90, -45, -60, -75, -90] : [0, 15, 30, -15, -30]
    var split: (train: [Episode], val: [Episode], test: [Episode]) = ([], [], [])
    for (correct, folder) in [(true, "correct"), (false, "incorrect")] {
        for subject in 1...10 {
            for rep in 1...10 {
                let stem = String(format: "m%@_s%02d_e%02d", ex.movement, subject, rep)
                let dir = data.appendingPathComponent(folder)
                let frames = try loadEpisode(positions: dir.appendingPathComponent("\(stem)_positions.txt"),
                                             angles: dir.appendingPathComponent("\(stem)_angles.txt"))
                    .enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
                let targets = frames.map { s -> [Double] in
                    let t = Truth(s)
                    return [correct ? 1 : 0] + ex.checks.map { $0.truth(t) ? 1 : 0 }
                }
                for yaw in yaws {
                    var episode = Episode(name: "\(folder)/\(stem)@\(Int(yaw))", correct: correct)
                    let pitch = rng.uniform(-10, 10), turn = yaw + rng.uniform(-7, 7), mirror = rng.next() < 0.5
                    let noisy = !testSubjects.contains(subject) && !valSubjects.contains(subject)
                    for (f, s) in frames.enumerated() {
                        var p = project(s, yaw: turn, pitch: pitch, mirror: mirror)
                        // Vision keypoints jitter ~2 cm on a ~170 cm person.
                        if noisy { p = p.map { $0 + V2(rng.normal(), rng.normal()) * 2 } }
                        episode.x.append(FormFeatures.vector(p))
                        episode.y.append(targets[f])
                    }
                    if testSubjects.contains(subject) { split.test.append(episode) }
                    else if valSubjects.contains(subject) { split.val.append(episode) }
                    else { split.train.append(episode) }
                }
            }
        }
    }
    return split
}

// MARK: - Metrics

func balancedAccuracy(_ truth: [Bool], _ pred: [Bool]) -> Double {
    var tp = 0.0, fn = 0.0, tn = 0.0, fp = 0.0
    for (t, p) in zip(truth, pred) {
        switch (t, p) {
        case (true, true): tp += 1
        case (true, false): fn += 1
        case (false, false): tn += 1
        case (false, true): fp += 1
        }
    }
    let rates = [tp + fn > 0 ? tp / (tp + fn) : nil, tn + fp > 0 ? tn / (tn + fp) : nil].compactMap { $0 }
    return rates.reduce(0, +) / Double(rates.count)
}

func accuracy(_ truth: [Bool], _ pred: [Bool]) -> Double {
    Double(zip(truth, pred).filter { $0 == $1 }.count) / Double(truth.count)
}

func r3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

// MARK: - Download

func download(to data: URL) async throws {
    let base = "https://raw.githubusercontent.com/jkaethee/UI-PRMD_Exercise_Model/main/"
    var jobs: [(URL, URL)] = []
    for ex in exercises { for s in 1...10 { for e in 1...10 { for kind in ["Positions", "Angles"] {
        let stem = String(format: "m%@_s%02d_e%02d_%@", ex.movement, s, e, kind.lowercased())
        jobs.append((URL(string: base + "Segmented%20Movements/Kinect/\(kind)/\(stem).txt")!,
                     data.appendingPathComponent("correct/\(stem).txt")))
        jobs.append((URL(string: base + "Incorrect%20Segmented%20Movements/Kinect/\(kind)/\(stem)_inc.txt")!,
                     data.appendingPathComponent("incorrect/\(stem).txt")))
    } } } }
    for dir in ["correct", "incorrect"] {
        try FileManager.default.createDirectory(at: data.appendingPathComponent(dir), withIntermediateDirectories: true)
    }
    let missing = jobs.filter { !FileManager.default.fileExists(atPath: $0.1.path) }
    guard !missing.isEmpty else { return }
    print("Downloading \(missing.count) UI-PRMD files…")
    try await withThrowingTaskGroup(of: Void.self) { group in
        for (n, (url, dest)) in missing.enumerated() {
            if n >= 16 { try await group.next() }
            group.addTask {
                let (tmp, response) = try await URLSession.shared.download(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLErrorKey: url]) }
                try FileManager.default.moveItem(at: tmp, to: dest)
            }
        }
        try await group.waitForAll()
    }
}

// MARK: - Self-check

/// On-device personalisation works end to end: MLUpdateTask on the exported
/// model, fed one held-out episode where the user says the coach got "knees"
/// wrong (same targets the app builds), moves "knees" toward the user's answer.
func updateCheck(_ model: MLModel, folder: URL, exercise: String, sample: Episode) async throws {
    let k = 2  // squat outputs: form_ok, range, knees, ...
    let scores = try sample.x.map { try CoreMLExport.predict(model, $0) }
    let before = scores.map { $0[k] }.reduce(0, +) / Double(scores.count)
    let target = before >= 0.5 ? 0.0 : 1.0
    func array(_ v: [Double]) throws -> MLMultiArray {
        let a = try MLMultiArray(shape: [NSNumber(value: v.count)], dataType: .double)
        for (i, x) in v.enumerated() { a[i] = NSNumber(value: x) }
        return a
    }
    let batch = MLArrayBatchProvider(array: try zip(sample.x, scores).map { x, s in
        var t = s
        t[k] = target
        return try MLDictionaryFeatureProvider(dictionary: ["features": array(x), "checks_true": array(t)])
    })
    let compiled = try await MLModel.compileModel(at: folder.appendingPathComponent("\(CoreMLExport.modelName(exercise)).mlmodel"))
    let config = MLModelConfiguration()
    config.computeUnits = .cpuOnly
    let updated: MLModel = try await withCheckedThrowingContinuation { done in
        do {
            let task = try MLUpdateTask(forModelAt: compiled, trainingData: batch, configuration: config) { context in
                if let error = context.task.error { done.resume(throwing: error) } else { done.resume(returning: context.model) }
            }
            task.resume()
        } catch { done.resume(throwing: error) }
    }
    let after = try sample.x.map { try CoreMLExport.predict(updated, $0)[k] }.reduce(0, +) / Double(sample.x.count)
    precondition(abs(after - target) < abs(before - target) - 0.2, "MLUpdateTask did not learn the correction: \(before) -> \(after)")
    print(String(format: "Self-check ok: MLUpdateTask moved squat 'knees' %.2f -> %.2f (user said %.0f)", before, after, target))
}

// MARK: - Main

@main
struct TrainFormModel {
    static func main() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1])
            : repo.appendingPathComponent("tools/formcoach/data/uiprmd")
        try await download(to: data)
        var rng = RNG(state: 7)
        let models = repo.appendingPathComponent("Anurja/FormModels")
        var report: [String: Any] = [:]
        for ex in exercises {
            let split = try samples(ex, data: data, rng: &rng)
            let x = split.train.flatMap(\.x), y = split.train.flatMap(\.y)
            let ids = ["form_ok"] + ex.checks.map(\.id)
            let mean = (0..<FormFeatures.count).map { i in x.reduce(0) { $0 + $1[i] } / Double(x.count) }
            let scale = (0..<FormFeatures.count).map { i in
                max((x.reduce(0) { $0 + pow($1[i] - mean[i], 2) } / Double(x.count)).squareRoot(), 1e-6)
            }
            var seed: UInt64 = 42
            var net = FormNetwork(outputs: ids, mean: mean, scale: scale, hidden: 32, seed: &seed)
            net.fit(x, y, epochs: 40, rate: 0.02)

            func column(_ eps: [Episode], _ k: Int) -> [Bool] { eps.flatMap { $0.y.map { $0[k] >= 0.5 } } }
            func predicted(_ eps: [Episode], _ k: Int) -> [Bool] { eps.flatMap { $0.x.map { net.predict($0)[k] >= 0.5 } } }
            func ruled(_ eps: [Episode], _ k: Int) -> [Bool] { eps.flatMap { $0.x.map { ex.checks[k - 1].rule(Rule2D($0)) } } }
            /// Whole-episode verdict: mean form_ok over the episode's frames.
            func episodeAccuracy(_ eps: [Episode]) -> Double {
                Double(eps.filter { e in (e.x.map { net.predict($0)[0] }.reduce(0, +) / Double(e.x.count) >= 0.5) == e.correct }.count) / Double(eps.count)
            }

            // Choose model vs rule per output on validation only.
            var use: [String] = episodeAccuracy(split.val) >= 0.75 ? ["form_ok"] : []
            for k in 1..<ids.count {
                let share = y.reduce(0) { $0 + $1[k] } / Double(y.count)
                let truth = column(split.val, k)
                if min(share, 1 - share) >= 0.03, Set(truth).count == 2,
                   balancedAccuracy(truth, predicted(split.val, k)) > balancedAccuracy(truth, ruled(split.val, k)) {
                    use.append(ids[k])
                }
            }
            net.useModel = use

            // Export to Core ML and score the held-out subjects through Core ML,
            // the exact path the app runs.
            let coreml = try await CoreMLExport.write(net, exercise: ex.name, metadata: [
                "outputs": ids.joined(separator: ","), "useModel": use.joined(separator: ","),
            ], to: models)
            var maxDiff = 0.0
            let testScores = try split.test.map { e in
                try e.x.map { f -> [Double] in
                    let p = try CoreMLExport.predict(coreml, f)
                    maxDiff = max(maxDiff, zip(p, net.predict(f)).map { abs($0 - $1) }.max()!)
                    return p
                }
            }
            precondition(maxDiff < 1e-3, "Core ML disagrees with the trained network by \(maxDiff)")
            if ex.name == "squat" { try await updateCheck(coreml, folder: models, exercise: ex.name, sample: split.test[0]) }

            var model: [String: Any] = [:], rule: [String: Any] = [:], hit: [String: Any] = [:], app: [String: Any] = [:]
            var line = "\(ex.name.padding(toLength: 13, withPad: " ", startingAt: 0))"
            for k in ids.indices {
                let truth = column(split.test, k), pred = testScores.flatMap { $0.map { $0[k] >= 0.5 } }
                hit[ids[k]] = r3(Double(truth.filter { $0 }.count) / Double(truth.count))
                model[ids[k]] = ["acc": r3(accuracy(truth, pred)), "balanced": r3(balancedAccuracy(truth, pred))]
                var ruleBalanced = Double.nan
                if k > 0 {
                    let r = ruled(split.test, k)
                    ruleBalanced = balancedAccuracy(truth, r)
                    rule[ids[k]] = ["acc": r3(accuracy(truth, r)), "balanced": r3(ruleBalanced)]
                }
                if use.contains(ids[k]) { app[ids[k]] = model[ids[k]] } else if k > 0 { app[ids[k]] = rule[ids[k]] }
                line += String(format: "  %@ %.2f/%.2f%@", ids[k], balancedAccuracy(truth, pred), ruleBalanced, use.contains(ids[k]) ? "*" : "")
            }
            let episodes = Double(zip(split.test, testScores).filter { e, s in
                (s.map { $0[0] }.reduce(0, +) / Double(s.count) >= 0.5) == e.correct
            }.count) / Double(split.test.count)
            print(line + String(format: "   rep verdict %.2f   (Core ML vs Swift max diff %.1e)", episodes, maxDiff))
            report[ex.name] = [
                "frames_train": x.count, "frames_test": split.test.reduce(0) { $0 + $1.x.count },
                "episodes_test": split.test.count, "episode_form_ok_acc": r3(episodes),
                "hit_rate_test": hit, "model": model, "rules_2d": rule, "use_model": use, "app": app,
                "evaluated_with": "Core ML (\(CoreMLExport.modelName(ex.name)).mlmodel, CPU)",
            ]
        }

        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try reportData.write(to: repo.appendingPathComponent("tools/formcoach/report.json"))
        print("Wrote Anurja/FormModels/*.mlmodel and tools/formcoach/report.json")
    }
}
