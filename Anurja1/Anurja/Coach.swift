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

private func minimum(_ first: Double?, _ second: Double?) -> Double? {
    switch (first, second) {
    case let (lhs?, rhs?): min(lhs, rhs)
    case let (lhs?, nil): lhs
    case let (nil, rhs?): rhs
    default: nil
    }
}

private func jointAngle(_ joints: [BodyJoint: CGPoint], _ first: BodyJoint, _ middle: BodyJoint, _ last: BodyJoint) -> Double? {
    guard let a = joints[first], let b = joints[middle], let c = joints[last] else { return nil }
    let ax = (a.x - b.x) * 0.75
    let ay = a.y - b.y
    let cx = (c.x - b.x) * 0.75
    let cy = c.y - b.y
    let dot = ax * cx + ay * cy
    let cross = ax * cy - ay * cx
    return abs(atan2(cross, dot)) * 180 / .pi
}

private func averaged(left: Double?, right: Double?) -> Double? {
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

    init(exercise: ExerciseKind) {
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

    mutating func ingest(_ raw: Double?, at now: Date = Date()) {
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
        if inRep, angle < lo {
            reached = true
            feedback = good
        }
        if inRep, angle > hi {
            let duration = repStart.map { now.timeIntervalSince($0) } ?? 1
            if reached && duration < 0.7 {
                feedback = String(localized: "Too quick. Slow and steady counts")
            } else if reached {
                count += 1
                feedback = count >= target
                    ? String(localized: "Set complete! \(count) reps")
                    : String(localized: "Rep \(count)!")
            } else {
                feedback = further
            }
            inRep = false
            reached = false
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
            counter.ingest(angle)
        }
        .onChange(of: clock.angle) { _, angle in
            guard mode == .live, camera.simulated else { return }
            counter.ingest(angle)
        }
        .onDisappear {
            camera.stop()
            clock.stop()
        }
        .alert("Nice work!", isPresented: $showFinish) {
            Button("Done") { dismiss() }
        } message: {
            Text("\(awardedReps) clean reps. Muscles that just worked help your body use glucose.")
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
                    SkeletonOverlay(joints: camera.joints)
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

    private func finish() {
        award(force: true)
        camera.stop()
        clock.stop()
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
            for point in joints.values {
                let rect = CGRect(x: point.x * size.width - 4, y: point.y * size.height - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(.terracotta))
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
