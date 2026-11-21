import SwiftUI

// MARK: - Today's plan

/// One day's routine: a walk, then a few coached exercises. Deterministic per
/// calendar day, so the plan is stable all day and changes tomorrow.
struct DayPlan {
    struct Item: Identifiable {
        var kind: ExerciseKind
        var sets: Int
        var id: ExerciseKind { kind }
    }

    var walkMinutes: Int
    var items: [Item]

    /// Beginners (60+ or BMI 30+) rotate through the gentler moves only.
    /// Shifting by 3 each day over a pool of 5 or 8 never gives two
    /// consecutive days the same set.
    static func make(for profile: UserProfile, on date: Date = .now, calendar: Calendar = .current) -> DayPlan {
        let beginner = profile.age >= 60 || profile.bmi >= 30
        let pool: [ExerciseKind] = beginner
            ? [.chairStand, .wallPushup, .march, .curl, .lateralRaise]
            : ExerciseKind.allCases
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let items = (0..<3).map { Item(kind: pool[(day * 3 + $0) % pool.count], sets: beginner ? 1 : 2) }
        return DayPlan(walkMinutes: beginner ? 10 : 15, items: items)
    }

    /// The coach screens to run, one per set.
    var queue: [ExerciseKind] {
        items.flatMap { Array(repeating: $0.kind, count: $0.sets) }
    }
}

// MARK: - Train tab

/// The Train tab: today's walk and exercises, nothing else.
struct HabitsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let plan = DayPlan.make(for: state.profile)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(
                    title: "Today's training",
                    subtitle: "Walk first, then your exercises. A new mix every day."
                )
                PrimaryButton(title: "Start today's session", symbol: "play.fill") {
                    state.startDailySession()
                }
                row(
                    symbol: "figure.walk",
                    title: Text("Brisk walk"),
                    detail: Text("\(plan.walkMinutes) minutes"),
                    done: state.walkedToday
                ) {
                    state.walking = true
                }
                ForEach(plan.items) { item in
                    row(
                        symbol: item.kind.symbol,
                        title: Text(item.kind.title),
                        detail: Text("\(item.sets) × \(item.kind.targetReps) reps"),
                        done: state.sessions.contains { $0.exercise == item.kind && Calendar.current.isDateInToday($0.date) }
                    ) {
                        state.openCoach(item.kind)
                    }
                }
                Text("Guided by your front camera. We check your form and count clean reps. Video never leaves your phone.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .fullScreenCover(isPresented: $state.walking, onDismiss: state.nextInSession) {
            WalkScreen(minutes: plan.walkMinutes)
        }
        .onChange(of: state.coach) { old, new in
            if old != nil, new == nil { state.nextInSession() }
        }
    }

    private func row(symbol: String, title: Text, detail: Text, done: Bool, start: @escaping () -> Void) -> some View {
        Button(action: start) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.maroon)
                    .frame(width: 54, height: 54)
                    .background(Color.blush.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .scaledFont(size: 16, weight: .bold)
                        .foregroundStyle(Color.ink)
                    detail
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: done ? "checkmark.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(done ? Color.forest : Color.terracotta)
                    .accessibilityHidden(true)
            }
            .anurjaCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(done ? Text("Done today") : Text(""))
    }
}

// MARK: - Walk

/// A simple walk timer. Steps come from the motion coprocessor when available.
struct WalkScreen: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var motion = MotionService()
    @State private var start = Date()
    var minutes: Int

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    state.endSession()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 44, height: 44)
                        .background(Color.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                Spacer()
            }
            Spacer()
            Image(systemName: "figure.walk")
                .font(.system(size: 64))
                .foregroundStyle(Color.forest)
                .accessibilityHidden(true)
            Text("Brisk walk")
                .scaledFont(size: 28, weight: .bold)
                .foregroundStyle(Color.ink)
            TimelineView(.periodic(from: start, by: 1)) { context in
                let left = max(0, minutes * 60 - Int(context.date.timeIntervalSince(start)))
                Text(String(format: "%d:%02d", left / 60, left % 60))
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
            }
            if motion.liveSteps > 0 {
                Text("\(motion.liveSteps) steps")
                    .scaledFont(size: 15)
                    .foregroundStyle(Color.muted)
            }
            Text("Walk at a pace where you can talk but not sing.")
                .scaledFont(size: 15)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
            Spacer()
            PrimaryButton(title: "Done walking", symbol: "checkmark") {
                state.addCheckIn(HabitCheckIn(did: .yes, feel: .fine, effort: .okay, steps: motion.liveSteps > 0 ? motion.liveSteps : nil))
                dismiss()
            }
        }
        .padding(20)
        .background(Color.cream.ignoresSafeArea())
        .onAppear {
            start = Date()
            motion.startLive(from: start)
        }
        .onDisappear { motion.stop() }
    }
}

#Preview("Train") {
    MainTabView().environmentObject(PreviewData.state(tab: .habits))
}
