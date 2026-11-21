import AVFoundation
import SwiftUI
import UIKit
import Vision

enum BodyJoint: String, CaseIterable, Hashable {
    case nose, neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle

    var visionName: VNHumanBodyPoseObservation.JointName? {
        switch self {
        case .nose: .nose
        case .neck: .neck
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftElbow: .leftElbow
        case .rightElbow: .rightElbow
        case .leftWrist: .leftWrist
        case .rightWrist: .rightWrist
        case .leftHip: .leftHip
        case .rightHip: .rightHip
        case .leftKnee: .leftKnee
        case .rightKnee: .rightKnee
        case .leftAnkle: .leftAnkle
        case .rightAnkle: .rightAnkle
        }
    }
}

struct PoseReading: Sendable {
    var joints: [BodyJoint: CGPoint]
    var angle: Double?
}

protocol PoseFrameHandling: AnyObject {
    func reading(from sampleBuffer: CMSampleBuffer, exercise: ExerciseKind) -> PoseReading
}

final class VisionPoseHandler: PoseFrameHandling {
    func reading(from sampleBuffer: CMSampleBuffer, exercise: ExerciseKind) -> PoseReading {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return PoseReading(joints: [:], angle: nil)
        }
        guard let observation = request.results?.first else {
            return PoseReading(joints: [:], angle: nil)
        }
        var joints: [BodyJoint: CGPoint] = [:]
        for joint in BodyJoint.allCases {
            guard let name = joint.visionName,
                  let point = try? observation.recognizedPoint(name),
                  point.confidence > 0.3 else { continue }
            joints[joint] = CGPoint(x: point.location.x, y: 1 - point.location.y)
        }
        let visible = exercise.requiredJoints.filter { joints[$0] != nil }.count
        let angle = visible * 2 >= exercise.requiredJoints.count ? exercise.angle(in: joints) : nil
        return PoseReading(joints: joints, angle: angle)
    }
}

extension ExerciseKind {
    /// The single joint angle each exercise is counted on. Higher = extended
    /// / resting position, lower = the working end of the movement.
    func angle(in joints: [BodyJoint: CGPoint]) -> Double? {
        switch self {
        case .squat, .chairStand:
            return averaged(
                left: jointAngle(joints, .leftHip, .leftKnee, .leftAnkle),
                right: jointAngle(joints, .rightHip, .rightKnee, .rightAnkle)
            )
        case .lunge:
            // The front knee does the work; track whichever knee bends more.
            return minimum(
                jointAngle(joints, .leftHip, .leftKnee, .leftAnkle),
                jointAngle(joints, .rightHip, .rightKnee, .rightAnkle)
            )
        case .march:
            // Hip flexion: shoulder-hip-knee closes as the knee lifts.
            return minimum(
                jointAngle(joints, .leftShoulder, .leftHip, .leftKnee),
                jointAngle(joints, .rightShoulder, .rightHip, .rightKnee)
            )
        case .curl, .press, .wallPushup:
            return averaged(
                left: jointAngle(joints, .leftShoulder, .leftElbow, .leftWrist),
                right: jointAngle(joints, .rightShoulder, .rightElbow, .rightWrist)
            )
        case .lateralRaise:
            // Shoulder abduction (hip-shoulder-elbow) grows as arms lift, so
            // flip it to fit the same "extended high, working low" counter.
            return averaged(
                left: jointAngle(joints, .leftHip, .leftShoulder, .leftElbow),
                right: jointAngle(joints, .rightHip, .rightShoulder, .rightElbow)
            ).map { 180 - $0 }
        }
    }

    /// Joints that must be visible for a fair reading.
    var requiredJoints: [BodyJoint] {
        switch self {
        case .squat, .chairStand, .lunge:
            [.leftHip, .rightHip, .leftKnee, .rightKnee]
        case .march:
            [.leftShoulder, .rightShoulder, .leftHip, .rightHip]
        case .curl, .press, .wallPushup:
            [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow]
        case .lateralRaise:
            [.leftShoulder, .rightShoulder, .leftHip, .rightHip]
        }
    }
}

func minimum(_ first: Double?, _ second: Double?) -> Double? {
    switch (first, second) {
    case let (lhs?, rhs?): min(lhs, rhs)
    case let (lhs?, nil): lhs
    case let (nil, rhs?): rhs
    default: nil
    }
}

func jointAngle(_ joints: [BodyJoint: CGPoint], _ first: BodyJoint, _ middle: BodyJoint, _ last: BodyJoint) -> Double? {
    guard let a = joints[first], let b = joints[middle], let c = joints[last] else { return nil }
    let ax = (a.x - b.x) * 0.75
    let ay = a.y - b.y
    let cx = (c.x - b.x) * 0.75
    let cy = c.y - b.y
    let dot = ax * cx + ay * cy
    let cross = ax * cy - ay * cx
    return abs(atan2(cross, dot)) * 180 / .pi
}

func averaged(left: Double?, right: Double?) -> Double? {
    switch (left, right) {
    case let (lhs?, rhs?): (lhs + rhs) / 2
    case let (lhs?, nil): lhs
    case let (nil, rhs?): rhs
    default: nil
    }
}

private final class LockedExercise: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ExerciseKind
    init(_ value: ExerciseKind) { self.value = value }
    func set(_ value: ExerciseKind) {
        lock.lock()
        self.value = value
        lock.unlock()
    }
    func get() -> ExerciseKind {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class PoseCameraController: NSObject, ObservableObject {
    @Published var joints: [BodyJoint: CGPoint] = [:]
    @Published var angle: Double?
    @Published var simulated = false
    @Published var permissionDenied = false
    let session = AVCaptureSession()
    /// Swap this for a MediaPipe Pose Landmarker handler later. It only needs to fill joints and angle.
    var frameHandler: PoseFrameHandling = VisionPoseHandler()
    private let queue = DispatchQueue(label: "com.anurja.pose")
    private let frames = DispatchQueue(label: "com.anurja.pose.frames")
    private let exerciseBox = LockedExercise(.squat)
    private var configured = false

    func start(exercise: ExerciseKind) {
        exerciseBox.set(exercise)
        permissionDenied = false
        #if targetEnvironment(simulator)
        simulated = true
        return
        #else
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil else {
            simulated = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            simulated = false
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.simulated = false
                        self.configureAndStart()
                    } else {
                        self.permissionDenied = true
                        self.simulated = true
                    }
                }
            }
        default:
            permissionDenied = true
            simulated = true
        }
        #endif
    }

    func stop() {
        let session = session
        queue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureAndStart() {
        let frames = frames
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.configured else {
                if !self.session.isRunning { self.session.startRunning() }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .vga640x480
            var ready = false
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                ready = true
            }
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: frames)
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
            } else {
                ready = false
            }
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
            self.session.commitConfiguration()
            if ready {
                self.configured = true
                self.session.startRunning()
            } else {
                DispatchQueue.main.async { self.simulated = true }
            }
        }
    }
}

extension PoseCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let reading = frameHandler.reading(from: sampleBuffer, exercise: exerciseBox.get())
        DispatchQueue.main.async { [weak self] in
            self?.joints = reading.joints
            self?.angle = reading.angle
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    var session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewHost {
        let view = PreviewHost()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        apply(connection: view.previewLayer.connection)
        return view
    }

    func updateUIView(_ uiView: PreviewHost, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        apply(connection: uiView.previewLayer.connection)
    }

    private func apply(connection: AVCaptureConnection?) {
        guard let connection else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

final class PreviewHost: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// Counts reps from a joint angle stream: smooths the signal, requires the
/// full range of motion and a controlled tempo, and reports live motion.
struct RepCounter {
    var count = 0
    var feedback: String
    var moving = false
    let target: Int
    private var hi: Double
    private var lo: Double
    private var further: String
    private var good: String
    private var inRep = false
    private var reached = false
    private var smoothed: Double?
    private var repStart: Date?
    private var lastSample: Date?
    // Set stats for the end-of-set form report.
    private(set) var shallowReps = 0
    private(set) var rushedReps = 0
    private(set) var repDurations: [Double] = []
    private(set) var framesSeen = 0
    private(set) var framesLost = 0
    // Body checkpoints: live result for the current frame, and per-rep tally.
    let checks: [FormCheck]
    private(set) var live: [String: Bool] = [:]
    private(set) var checkTally: [String: (hit: Int, reps: Int)] = [:]
    private var repChecks: [String: (pass: Int, seen: Int)] = [:]
    /// Checkpoints the last finished rep missed, for the live correction text.
    private(set) var lastRepMissed: Set<String> = []
    // Learned model (FormFeatures.swift): replaces the rule for checkpoints it
    // beat on validation, and scores the whole rep where it's reliable.
    let network: FormModel?
    private(set) var samples: [FormSample] = []
    private(set) var formTally: (good: Int, reps: Int) = (0, 0)
    private var repForm: [Double] = []

    /// Checkpoints read by the learned model instead of the 2D rule.
    var modelled: Set<String> { Set(network?.useModel ?? []) }

    init(exercise: ExerciseKind) {
        checks = exercise.formChecks
        network = FormModels.model(for: exercise)
        hi = exercise.extendedAngle
        lo = exercise.depthAngle
        further = exercise.furtherCue
        good = exercise.goodCue
        target = exercise.targetReps
        feedback = String(localized: "Step into frame")
    }

    mutating func reset(exercise: ExerciseKind) {
        self = RepCounter(exercise: exercise)
    }

    /// Green/red per joint from the current frame: red if any check using it fails.
    var jointStatus: [BodyJoint: Bool] {
        var status: [BodyJoint: Bool] = [:]
        for check in checks {
            guard let passed = live[check.id] else { continue }
            for joint in check.joints {
                status[joint] = (status[joint] ?? true) && passed
            }
        }
        return status
    }

    mutating func ingest(_ raw: Double?, joints: [BodyJoint: CGPoint]? = nil, at now: Date = Date()) {
        if let joints {
            live = [:]
            let features = network == nil ? nil : FormFeatures.vector(joints)
            let scores = features.flatMap { network?.predict($0) }
            let named = scores.map { Dictionary(uniqueKeysWithValues: zip(network?.outputs ?? [], $0)) } ?? [:]
            for check in checks {
                if modelled.contains(check.id), let score = named[check.id] {
                    live[check.id] = score >= 0.5
                } else {
                    live[check.id] = check.test(joints)
                }
            }
            if let features, let scores, repStart != nil, samples.count < 2000 {
                samples.append(FormSample(features: features, scores: scores))
            }
            if inRep, modelled.contains("form_ok"), let ok = named["form_ok"] {
                repForm.append(ok)
            }
        }
        // Only count tracking once the set has started.
        if repStart != nil {
            if raw == nil { framesLost += 1 } else { framesSeen += 1 }
        }
        guard let raw else {
            feedback = String(localized: "Step into frame")
            smoothed = nil
            moving = false
            return
        }
        // Exponential smoothing removes pose-estimation jitter.
        let previous = smoothed ?? raw
        let angle = previous + 0.45 * (raw - previous)
        let seconds = lastSample.map { max(0.016, now.timeIntervalSince($0)) } ?? 0.1
        moving = abs(angle - previous) / seconds > 12
        smoothed = angle
        lastSample = now

        if !inRep, angle < hi - 15 {
            inRep = true
            reached = false
            repStart = now
            feedback = String(localized: "Keep going…")
        }
        if inRep {
            for (id, passed) in live {
                var tally = repChecks[id] ?? (0, 0)
                tally.seen += 1
                if passed { tally.pass += 1 }
                repChecks[id] = tally
            }
        }
        if inRep, angle < lo {
            reached = true
            feedback = good
        }
        // Say the missed hold checkpoint and how to fix it, while it happens.
        if inRep, let missed = checks.first(where: { $0.kind == .hold && live[$0.id] == false }) {
            feedback = missed.correction
        }
        if inRep, angle > hi {
            let duration = repStart.map { now.timeIntervalSince($0) } ?? 1
            if reached && duration < 0.7 {
                rushedReps += 1
                feedback = String(localized: "Too quick. Slow and steady counts")
            } else if reached {
                count += 1
                repDurations.append(duration)
                feedback = count >= target
                    ? String(localized: "Set complete! \(count) reps")
                    : String(localized: "Rep \(count)!")
            } else {
                shallowReps += 1
                feedback = further
            }
            closeRepChecks()
            inRep = false
            reached = false
        }
    }

    private mutating func closeRepChecks() {
        lastRepMissed = []
        if !repForm.isEmpty {
            formTally.reps += 1
            if repForm.reduce(0, +) / Double(repForm.count) >= 0.5 { formTally.good += 1 }
            repForm = []
        }
        for check in checks {
            guard let frames = repChecks[check.id], frames.seen > 0 else { continue }
            let hit = check.kind == .reach
                ? frames.pass > 0
                : Double(frames.pass) / Double(frames.seen) >= 0.7
            var tally = checkTally[check.id] ?? (0, 0)
            tally.reps += 1
            if hit { tally.hit += 1 }
            if !hit { lastRepMissed.insert(check.id) }
            checkTally[check.id] = tally
        }
        repChecks = [:]
    }
}

struct FormReport {
    var good: [String] = []
    var improve: [String] = []
}

extension RepCounter {
    // ponytail: left/right symmetry isn't checked yet; add it as a FormCheck
    // comparing both sides once real-device thresholds are tuned.
    func report(for exercise: ExerciseKind) -> FormReport {
        var report = FormReport()
        let attempts = count + shallowReps + rushedReps
        let tracked = framesSeen + framesLost
        let lostShare = tracked > 0 ? Double(framesLost) / Double(tracked) : 0
        let pace = repDurations.isEmpty ? nil : repDurations.reduce(0, +) / Double(repDurations.count)
        // With camera checkpoints, "range" is reported per checkpoint below.
        let rangeChecked = checkTally["range"] != nil

        if count >= target {
            report.good.append(String(localized: "You hit your target of \(target) reps"))
        } else if count > 0 {
            report.good.append(String(localized: "\(count) clean reps with full range of motion"))
        }
        if count > 0, shallowReps == 0, !rangeChecked {
            report.good.append(String(localized: "You reached full range on every rep"))
        }
        if count > 0, rushedReps == 0 {
            report.good.append(String(localized: "Controlled tempo, no rushed reps"))
        }
        if let pace, pace >= 1.2 {
            report.good.append(String(localized: "Steady, controlled pace through each rep"))
        }
        if attempts > 0, lostShare < 0.1 {
            report.good.append(String(localized: "You stayed in view of the camera the whole set"))
        }
        for check in checks {
            guard let tally = checkTally[check.id], tally.reps > 0 else { continue }
            let share = Double(tally.hit) / Double(tally.reps)
            if share >= 0.8 {
                report.good.append(String(localized: "\(check.title): \(tally.hit) of \(tally.reps) reps"))
            } else if share < 0.6 {
                report.improve.append(String(localized: "\(check.title): only \(tally.hit) of \(tally.reps) reps. \(check.tip)"))
            }
        }

        if formTally.reps > 0 {
            if Double(formTally.good) / Double(formTally.reps) >= 0.8 {
                report.good.append(String(localized: "Form model: \(formTally.good) of \(formTally.reps) reps looked like good form"))
            } else {
                report.improve.append(String(localized: "Form model: only \(formTally.good) of \(formTally.reps) reps looked like good form. Slow down and follow the checkpoints"))
            }
        }
        if shallowReps > 0, !rangeChecked {
            report.improve.append(String(localized: "\(shallowReps) of \(attempts) reps were short of full range. \(exercise.furtherCue)"))
        }
        if rushedReps > 0 {
            report.improve.append(String(localized: "\(rushedReps) of \(attempts) reps were too quick to count. Take about 2 seconds down and 2 seconds up"))
        } else if let pace, pace < 1.2 {
            report.improve.append(String(localized: "Slow down a little. Control both the way down and the way up"))
        }
        if lostShare >= 0.1 {
            report.improve.append(exercise.sideOn
                ? String(localized: "The camera lost you at times. Stand side-on with your whole body in the frame")
                : String(localized: "The camera lost you at times. Face the camera with your whole body in the frame"))
        }
        if attempts == 0 {
            report.improve.append(String(localized: "No reps were picked up. Step back until your whole body is in the frame, then start moving"))
        } else if count < target {
            report.improve.append(String(localized: "Build up to \(target) clean reps"))
        }
        if report.improve.isEmpty {
            report.improve.append(String(localized: "Great set. Next time, try 2 more reps or a slower lowering"))
        }
        return report
    }
}

struct FormSummaryView: View {
    var exercise: ExerciseKind
    var reps: Int
    var report: FormReport
    var profile: UserProfile
    var meals: [MealLog]
    /// The finished set, so the user can correct the coach and retrain it.
    var counter: RepCounter? = nil
    var done: () -> Void
    @State private var wrong: Set<String> = []
    @State private var note: String?
    @State private var ideas: [MealIdea] = []

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Nice work!")
                        .scaledFont(size: 26, weight: .bold)
                    Text("\(reps) clean reps. Muscles that just worked help your body use glucose.")
                        .scaledFont(size: 15)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Coach's note", systemImage: "sparkles")
                                .scaledFont(size: 13, weight: .semibold)
                                .foregroundStyle(Color.white.opacity(0.85))
                            Text(note)
                                .scaledFont(size: 16)
                                .foregroundStyle(Color.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.forest, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    section("What you did well", items: report.good, symbol: "checkmark.circle.fill", tint: .forest)
                    section("How to improve your form", items: report.improve, symbol: "arrow.up.right.circle.fill", tint: .terracotta)
                    if !ideas.isEmpty {
                        refuel
                    }
                    if !teachable.isEmpty {
                        teach
                    }
                    PrimaryButton(title: "Done", symbol: "checkmark", action: finish)
                }
                .padding(20)
            }
        }
        .task {
            ideas = MealIdeas.pick(profile: profile, meals: meals, exercise: exercise)
            async let written = CoachAI.setNote(exercise: exercise, reps: reps, report: report)
            async let personal = CoachAI.personalise(ideas, exercise: exercise, reps: reps, meals: meals)
            note = await written
            if let personal = await personal {
                ideas = personal
            }
        }
    }

    /// Model-read checkpoints the coach scored this set.
    private var teachable: [(check: FormCheck, coachHit: Bool, tally: (hit: Int, reps: Int))] {
        guard let counter, !counter.samples.isEmpty else { return [] }
        return counter.checks.compactMap { check in
            guard counter.modelled.contains(check.id), let tally = counter.checkTally[check.id], tally.reps > 0 else { return nil }
            return (check, tally.hit * 2 >= tally.reps, tally)
        }
    }

    private var teach: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Did the coach read you right?")
                .scaledFont(size: 17, weight: .bold)
            Text("Tap any checkpoint it got wrong. Your answers retrain the coach on this phone only. No video is kept.")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(teachable, id: \.check.id) { item in
                let flipped = wrong.contains(item.check.id)
                let hit = item.coachHit != flipped
                Button {
                    if flipped { wrong.remove(item.check.id) } else { wrong.insert(item.check.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: hit ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(hit ? Color.forest : Color.terracotta)
                            .font(.system(size: 18, weight: .semibold))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.check.title)
                                .scaledFont(size: 15)
                                .foregroundStyle(Color.ink)
                            Text(flipped
                                 ? (hit ? String(localized: "You say you did this") : String(localized: "You say you missed this"))
                                 : String(localized: "Coach: \(item.tally.hit) of \(item.tally.reps) reps"))
                                .scaledFont(size: 13)
                                .foregroundStyle(Color.muted)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(flipped ? "Fixed" : "Wrong?")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(flipped ? Color.forest : Color.terracotta)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .anurjaCard()
    }

    private func finish() {
        if let counter, !wrong.isEmpty {
            let corrections = Dictionary(uniqueKeysWithValues: teachable
                .filter { wrong.contains($0.check.id) }
                .map { ($0.check.id, !$0.coachHit) })
            let kinds = Dictionary(uniqueKeysWithValues: counter.checks.map { ($0.id, $0.kind) })
            let samples = counter.samples
            Task { await FormModels.personalise(exercise, samples: samples, corrections: corrections, kinds: kinds) }
        }
        done()
    }

    private var refuel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Refuel ideas")
                .scaledFont(size: 17, weight: .bold)
            Text("Picked from your food library, without your allergens")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
            ForEach(ideas) { idea in
                VStack(alignment: .leading, spacing: 3) {
                    Text(idea.item.name)
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Color.ink)
                    Text("\(idea.item.serving) · \(Int(idea.item.carbs)) g carbs · \(Int(idea.item.protein)) g protein")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                    Text(idea.reason)
                        .scaledFont(size: 14)
                        .foregroundStyle(Color.forest)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .anurjaCard()
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, items: [String], symbol: String, tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .scaledFont(size: 17, weight: .bold)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: symbol)
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)
                        Text(item)
                            .scaledFont(size: 15)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .anurjaCard()
        }
    }
}

final class SimulatedPoseClock: ObservableObject {
    @Published var angle: Double?
    private var timer: Timer?
    private var start = Date()
    private var exercise: ExerciseKind = .squat

    func start(exercise: ExerciseKind) {
        stop()
        self.exercise = exercise
        start = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(self.start)
            self.angle = self.exercise.simulatedAngle(elapsed: elapsed)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

private enum CoachMode: String, CaseIterable, Identifiable {
    case demo, live
    var id: String { rawValue }
    var title: String {
        switch self {
        case .demo: String(localized: "Watch demo")
        case .live: String(localized: "Check my form")
        }
    }
}

struct CoachScreen: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = PoseCameraController()
    @StateObject private var clock = SimulatedPoseClock()
    @State private var mode: CoachMode = .demo
    @State private var counter: RepCounter
    @State private var showFinish = false
    @State private var awarded = false
    @State private var awardedReps = 0
    @State private var report = FormReport()
    private let exercise: ExerciseKind

    init(exercise: ExerciseKind) {
        self.exercise = exercise
        _counter = State(initialValue: RepCounter(exercise: exercise))
    }

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 44, height: 44)
                            .background(Color.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close"))
                    Spacer()
                    Text(exercise.title)
                        .scaledFont(size: 19, weight: .bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                SegmentedTabs(options: CoachMode.allCases, title: { $0.title }, selection: $mode)
                ScrollView {
                    if mode == .demo {
                        demo
                    } else {
                        live
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .onChange(of: mode) { _, newMode in
            counter.reset(exercise: exercise)
            if newMode == .live {
                camera.start(exercise: exercise)
            } else {
                camera.stop()
                clock.stop()
            }
        }
        .onChange(of: camera.simulated) { _, simulated in
            guard mode == .live else { return }
            if simulated {
                clock.start(exercise: exercise)
            } else {
                clock.stop()
            }
        }
        .onChange(of: camera.angle) { _, angle in
            guard mode == .live, !camera.simulated else { return }
            counter.ingest(angle, joints: camera.joints)
        }
        .onChange(of: clock.angle) { _, angle in
            guard mode == .live, camera.simulated else { return }
            counter.ingest(angle)
        }
        .onDisappear {
            camera.stop()
            clock.stop()
        }
        .sheet(isPresented: $showFinish, onDismiss: { dismiss() }) {
            FormSummaryView(exercise: exercise, reps: awardedReps, report: report, profile: state.profile, meals: state.meals, counter: counter) { showFinish = false }
        }
    }

    private var demo: some View {
        VStack(alignment: .leading, spacing: 12) {
            StickFigure(exercise: exercise)
                .frame(maxWidth: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.sand, lineWidth: 1))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(exercise.cues.enumerated()), id: \.offset) { index, cue in
                    HStack(spacing: 10) {
                        Text(index + 1, format: .number)
                            .scaledFont(size: 12, weight: .bold)
                            .foregroundStyle(Color.white)
                            .frame(width: 28, height: 28)
                            .background(Color.terracotta, in: Circle())
                        Text(cue)
                            .scaledFont(size: 15)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                }
            }
            .anurjaCard()
            PrimaryButton(title: "Try it with the camera", symbol: "camera") {
                mode = .live
            }
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(hex: 0x2E3A33))
                if camera.simulated {
                    StickFigure(exercise: exercise, stroke: .cream)
                        .padding(.bottom, 36)
                } else {
                    CameraPreview(session: camera.session)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    SkeletonOverlay(joints: camera.joints, status: counter.jointStatus)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .allowsHitTesting(false)
                }
                if !camera.simulated {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(counter.moving ? Color.green : Color.sand)
                            .frame(width: 8, height: 8)
                        Text(counter.moving ? "Movement detected" : "Hold still to start")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(Color.black.opacity(0.35), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
                }
                Text(counter.feedback)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(Color.terracotta, in: Capsule())
                    .padding(.bottom, 12)
                    .padding(.horizontal, 12)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Form check"))
            checkpoints
            if camera.simulated {
                Text("Camera unavailable here, running a simulated session")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if camera.permissionDenied {
                Text("Camera access is off. You can turn it on in Settings. Video stays on your device.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.forest)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(counter.count) / \(counter.target)")
                            .scaledFont(size: 28, weight: .bold)
                        Text("clean reps")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.muted)
                    }
                    Spacer()
                    Button(action: finish) {
                        HStack(spacing: 8) {
                            Text("Finish set")
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 46)
                        .background(Color.terracotta, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.sand)
                        Capsule()
                            .fill(Color.terracotta)
                            .frame(width: geo.size.width * min(1, CGFloat(counter.count) / CGFloat(counter.target)))
                    }
                }
                .frame(height: 8)
            }
            .anurjaCard()
        }
    }

    private var checkpoints: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Form checkpoints")
                .scaledFont(size: 15, weight: .bold)
            ForEach(counter.checks) { check in
                let live = counter.live[check.id]
                let tally = counter.checkTally[check.id]
                // Hold checks are corrected as they slip; reach checks once a rep misses them.
                let missed = check.kind == .hold ? live == false : counter.lastRepMissed.contains(check.id)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        Image(systemName: live == true ? "checkmark.circle.fill" : live == false ? "xmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(live == true ? Color.forest : live == false ? Color.terracotta : Color.muted)
                            .font(.system(size: 18, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(check.title)
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if counter.modelled.contains(check.id) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.muted)
                                .accessibilityLabel(Text("Read by the form model"))
                        }
                        Spacer(minLength: 8)
                        if let tally {
                            Text("\(tally.hit)/\(tally.reps)")
                                .scaledFont(size: 13, weight: .semibold)
                                .foregroundStyle(Color.muted)
                                .monospacedDigit()
                        }
                    }
                    if missed {
                        Text(check.correction)
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 28)
                    }
                }
                .frame(minHeight: 28)
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(live == true ? "Hit" : live == false ? "Missed" : "Not visible"))
            }
            if camera.simulated {
                Text("Checkpoints light up when the camera can see you")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .anurjaCard()
    }

    private func finish() {
        award(force: true)
        camera.stop()
        clock.stop()
        report = counter.report(for: exercise)
        showFinish = true
    }

    private func close() {
        award(force: false)
        camera.stop()
        clock.stop()
        dismiss()
    }

    private func award(force: Bool) {
        guard !awarded, mode == .live else { return }
        if !force, counter.count == 0 { return }
        awarded = true
        awardedReps = counter.count
        state.addSession(exercise: exercise, reps: counter.count)
    }
}

struct StickFigure: View {
    var exercise: ExerciseKind
    var stroke: Color = .forest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let progress = reduceMotion ? 0.5 : (1 - cos(2 * Double.pi * elapsed / 3.2)) / 2
            Canvas { context, size in
                drawStick(exercise: exercise, progress: progress, color: stroke, context: context, size: size)
            }
        }
        .frame(height: 260)
        .accessibilityLabel(Text("Exercise demonstration"))
    }
}

struct SkeletonOverlay: View {
    var joints: [BodyJoint: CGPoint]
    /// Checkpoint result per joint: green when hit, red when missed.
    var status: [BodyJoint: Bool] = [:]
    private let links: [(BodyJoint, BodyJoint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.neck, .nose), (.neck, .leftShoulder), (.neck, .rightShoulder)
    ]

    var body: some View {
        Canvas { context, size in
            for link in links {
                guard let start = joints[link.0], let end = joints[link.1] else { continue }
                var path = Path()
                path.move(to: CGPoint(x: start.x * size.width, y: start.y * size.height))
                path.addLine(to: CGPoint(x: end.x * size.width, y: end.y * size.height))
                context.stroke(path, with: .color(.cream), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            for (joint, point) in joints {
                let color: Color = switch status[joint] {
                case true?: .green
                case false?: .red
                case nil: .terracotta
                }
                let radius: CGFloat = status[joint] == nil ? 4 : 6
                let rect = CGRect(x: point.x * size.width - radius, y: point.y * size.height - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }
}

private func drawStick(exercise: ExerciseKind, progress: Double, color: Color, context: GraphicsContext, size: CGSize) {
    let model = figure(for: exercise, progress: progress)
    func map(_ point: CGPoint) -> CGPoint {
        let scaleX = size.width / 200
        let scaleY = size.height / 250
        return CGPoint(x: (100 + point.x * 50) * scaleX, y: (230 - point.y * 50) * scaleY)
    }
    var ground = Path()
    ground.move(to: CGPoint(x: 16, y: map(.zero).y))
    ground.addLine(to: CGPoint(x: size.width - 16, y: map(.zero).y))
    context.stroke(ground, with: .color(.sand), lineWidth: 3)
    for prop in model.props {
        var path = Path()
        path.move(to: map(prop.0))
        path.addLine(to: map(prop.1))
        context.stroke(path, with: .color(.sand), style: StrokeStyle(lineWidth: 6, lineCap: .round))
    }
    for segment in model.segments {
        var path = Path()
        path.move(to: map(segment.0))
        path.addLine(to: map(segment.1))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 8, lineCap: .round))
        let end = map(segment.1)
        context.fill(Path(ellipseIn: CGRect(x: end.x - 4.5, y: end.y - 4.5, width: 9, height: 9)), with: .color(.terracotta))
    }
    let head = map(model.head)
    let radius = min(size.width, size.height) * 0.055
    context.stroke(
        Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)),
        with: .color(color),
        lineWidth: 6
    )
}

private typealias Figure = (segments: [(CGPoint, CGPoint)], head: CGPoint, props: [(CGPoint, CGPoint)])

private func figure(for exercise: ExerciseKind, progress: Double) -> Figure {
    switch exercise {
    case .squat:
        let model = squatFigure(progress)
        return (model.segments, model.head, [])
    case .chairStand:
        let model = squatFigure(progress * 0.8)
        let chair: [(CGPoint, CGPoint)] = [
            (CGPoint(x: -1.25, y: 1.1), CGPoint(x: -0.4, y: 1.1)),
            (CGPoint(x: -1.25, y: 1.1), CGPoint(x: -1.25, y: 0)),
            (CGPoint(x: -0.45, y: 1.1), CGPoint(x: -0.45, y: 0)),
            (CGPoint(x: -1.25, y: 1.1), CGPoint(x: -1.25, y: 2.3))
        ]
        return (model.segments, model.head, chair)
    case .lunge:
        return lungeFigure(progress)
    case .wallPushup:
        return wallPushupFigure(progress)
    case .march:
        return marchFigure(progress)
    case .lateralRaise:
        return lateralRaiseFigure(progress)
    case .curl, .press:
        let model = frontFigure(progress, press: exercise == .press)
        return (model.segments, model.head, [])
    }
}

private func lerpPoint(_ start: CGPoint, _ end: CGPoint, _ progress: Double) -> CGPoint {
    CGPoint(x: lerp(start.x, end.x, progress), y: lerp(start.y, end.y, progress))
}

private func lungeFigure(_ progress: Double) -> Figure {
    let frontFoot = CGPoint(x: 0.75, y: 0)
    let backFoot = CGPoint(x: -0.85, y: 0)
    let hip = lerpPoint(CGPoint(x: 0, y: 1.95), CGPoint(x: 0, y: 1.4), progress)
    let frontKnee = lerpPoint(CGPoint(x: 0.4, y: 1.0), CGPoint(x: 0.78, y: 0.8), progress)
    let backKnee = lerpPoint(CGPoint(x: -0.42, y: 1.0), CGPoint(x: -0.6, y: 0.4), progress)
    let shoulder = CGPoint(x: hip.x + 0.05, y: hip.y + 1.1)
    let hand = CGPoint(x: shoulder.x + 0.1, y: shoulder.y - 0.85)
    return (
        [(frontFoot, frontKnee), (frontKnee, hip), (backFoot, backKnee), (backKnee, hip), (hip, shoulder), (shoulder, hand)],
        CGPoint(x: shoulder.x + 0.05, y: shoulder.y + 0.4),
        []
    )
}

private func wallPushupFigure(_ progress: Double) -> Figure {
    let feet = CGPoint(x: -0.9, y: 0)
    let hands = CGPoint(x: 1.35, y: 2.6)
    let shoulder = lerpPoint(CGPoint(x: 0.45, y: 2.75), CGPoint(x: 0.9, y: 2.55), progress)
    let hip = CGPoint(x: (feet.x + shoulder.x) / 2, y: (feet.y + shoulder.y) / 2)
    let elbow = lerpPoint(CGPoint(x: 0.9, y: 2.68), CGPoint(x: 1.05, y: 2.15), progress)
    let dx = shoulder.x - feet.x
    let dy = shoulder.y - feet.y
    let length = sqrt(dx * dx + dy * dy)
    let head = CGPoint(x: shoulder.x + dx / length * 0.4, y: shoulder.y + dy / length * 0.4)
    return (
        [(feet, hip), (hip, shoulder), (shoulder, elbow), (elbow, hands)],
        head,
        [(CGPoint(x: 1.5, y: 0), CGPoint(x: 1.5, y: 4.2))]
    )
}

private func marchFigure(_ progress: Double) -> Figure {
    let hipLeft = CGPoint(x: -0.25, y: 1.7)
    let hipRight = CGPoint(x: 0.25, y: 1.7)
    let kneeLeft = lerpPoint(CGPoint(x: -0.28, y: 0.85), CGPoint(x: -0.3, y: 1.75), progress)
    let footLeft = lerpPoint(CGPoint(x: -0.3, y: 0), CGPoint(x: -0.35, y: 0.9), progress)
    let segments: [(CGPoint, CGPoint)] = [
        (CGPoint(x: -0.5, y: 3), CGPoint(x: 0.5, y: 3)),
        (CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 1.7)),
        (hipLeft, hipRight),
        (hipLeft, kneeLeft), (kneeLeft, footLeft),
        (hipRight, CGPoint(x: 0.28, y: 0.85)), (CGPoint(x: 0.28, y: 0.85), CGPoint(x: 0.3, y: 0)),
        (CGPoint(x: -0.5, y: 3), CGPoint(x: -0.7, y: 2.2)), (CGPoint(x: 0.5, y: 3), CGPoint(x: 0.7, y: 2.2))
    ]
    return (segments, CGPoint(x: 0, y: 3.5), [])
}

private func lateralRaiseFigure(_ progress: Double) -> Figure {
    var segments: [(CGPoint, CGPoint)] = [
        (CGPoint(x: -0.5, y: 3), CGPoint(x: 0.5, y: 3)),
        (CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 1.6)),
        (CGPoint(x: 0, y: 1.6), CGPoint(x: -0.3, y: 0)),
        (CGPoint(x: 0, y: 1.6), CGPoint(x: 0.3, y: 0))
    ]
    let raise = lerp(12, 88, progress) * Double.pi / 180
    for side in [-1.0, 1.0] {
        let shoulder = CGPoint(x: 0.5 * side, y: 3)
        let elbow = CGPoint(x: shoulder.x + side * 0.7 * sin(raise), y: shoulder.y - 0.7 * cos(raise))
        let wrist = CGPoint(x: shoulder.x + side * 1.35 * sin(raise), y: shoulder.y - 1.35 * cos(raise))
        segments.append((shoulder, elbow))
        segments.append((elbow, wrist))
    }
    return (segments, CGPoint(x: 0, y: 3.5), [])
}

private func squatFigure(_ progress: Double) -> (segments: [(CGPoint, CGPoint)], head: CGPoint) {
    let shin = 35 * progress * .pi / 180
    let thigh = 75 * progress * .pi / 180
    let torso = 40 * progress * .pi / 180
    let arm = 85 * progress * .pi / 180
    let ankle = CGPoint(x: -0.1, y: 0)
    let knee = CGPoint(x: ankle.x + sin(shin), y: cos(shin))
    let hip = CGPoint(x: knee.x - sin(thigh), y: knee.y + cos(thigh))
    let shoulder = CGPoint(x: hip.x + 1.1 * sin(torso), y: hip.y + 1.1 * cos(torso))
    let hand = CGPoint(x: shoulder.x + 0.8 * sin(arm), y: shoulder.y - 0.8 * cos(arm))
    let head = CGPoint(x: shoulder.x + 0.4 * sin(torso), y: shoulder.y + 0.4 * cos(torso))
    return ([(ankle, knee), (knee, hip), (hip, shoulder), (shoulder, hand)], head)
}

private func frontFigure(_ progress: Double, press: Bool) -> (segments: [(CGPoint, CGPoint)], head: CGPoint) {
    var segments: [(CGPoint, CGPoint)] = [
        (CGPoint(x: -0.5, y: 3), CGPoint(x: 0.5, y: 3)),
        (CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 1.6)),
        (CGPoint(x: 0, y: 1.6), CGPoint(x: -0.3, y: 0)),
        (CGPoint(x: 0, y: 1.6), CGPoint(x: 0.3, y: 0))
    ]
    for side in [-1.0, 1.0] {
        let shoulder = CGPoint(x: 0.5 * side, y: 3)
        if press {
            let elbow = CGPoint(
                x: lerp(shoulder.x + 0.6 * side, shoulder.x + 0.25 * side, progress),
                y: lerp(2.7, 4, progress)
            )
            let wrist = CGPoint(
                x: lerp(shoulder.x + 0.6 * side, shoulder.x + 0.15 * side, progress),
                y: lerp(3.7, 5, progress)
            )
            segments.append((shoulder, elbow))
            segments.append((elbow, wrist))
        } else {
            let curl = 140 * progress * .pi / 180
            let elbow = CGPoint(x: shoulder.x + 0.1 * side, y: 2)
            let wrist = CGPoint(x: elbow.x - side * 0.3 * sin(curl), y: elbow.y - cos(curl))
            segments.append((shoulder, elbow))
            segments.append((elbow, wrist))
        }
    }
    return (segments, CGPoint(x: 0, y: 3.5))
}

private func lerp(_ start: Double, _ end: Double, _ progress: Double) -> Double {
    start + (end - start) * progress
}

#Preview("Coach") {
    CoachScreen(exercise: .squat)
        .environmentObject(PreviewData.state())
}

#Preview("Form summary") {
    var counter = RepCounter(exercise: .squat)
    let start = Date()
    // 3 slow clean reps, 1 shallow, 1 rushed.
    let reps: [(depth: Double, seconds: Double)] = [(90, 2.5), (90, 2.5), (90, 2.5), (130, 2.5), (90, 0.4)]
    var t = start
    for rep in reps {
        for angle in [170.0, 140, rep.depth, 140, 170] {
            for _ in 0..<6 { counter.ingest(angle, at: t); t += rep.seconds / 30 }
        }
    }
    return FormSummaryView(exercise: .squat, reps: counter.count, report: counter.report(for: .squat), profile: UserProfile(), meals: MealLog.samples) {}
}
