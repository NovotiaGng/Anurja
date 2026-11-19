import SwiftUI

struct HabitsView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var motion = MotionService()
    @State private var did: DidIt = .yes
    @State private var feel: HabitFeel = .lighter
    @State private var effort: Effort = .easy
    @State private var saved = false
    @State private var showReview = false
    @State private var showNextStep = false
    @State private var detectedSteps: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(
                    title: "Build gentler habits",
                    subtitle: "One small change at a time, at your pace."
                )
                planCard
                nextStepRow
                checkInCard
                Button {
                    showReview = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fortnightly review")
                            .scaledFont(size: 17, weight: .bold)
                            .foregroundStyle(Color.ink)
                        Text("Keep it, grow it or swap it.")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.sand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Fortnightly review"))
                PrimaryButton(
                    title: saved ? "Saved" : "Save check-in",
                    symbol: saved ? "checkmark" : "chevron.right",
                    action: save
                )
                Text("Strength & movement")
                    .scaledFont(size: 21, weight: .bold)
                    .foregroundStyle(Color.ink)
                    .padding(.top, 8)
                Text("Guided by your front camera. We check your form and count clean reps. Video never leaves your phone.")
                    .scaledFont(size: 15)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(ExerciseKind.allCases) { exercise in
                    Button {
                        state.coach = exercise
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: exercise.symbol)
                                .font(.system(size: 22))
                                .foregroundStyle(Color.maroon)
                                .frame(width: 54, height: 54)
                                .background(Color.blush.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.title)
                                    .scaledFont(size: 16, weight: .bold)
                                    .foregroundStyle(Color.ink)
                                Text(exercise.blurb)
                                    .scaledFont(size: 13)
                                    .foregroundStyle(Color.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.terracotta)
                                .accessibilityHidden(true)
                        }
                        .anurjaCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(exercise.title))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showReview) {
            ReviewSheet()
        }
        .sheet(isPresented: $showNextStep) {
            NextStepSheet()
        }
        .task(id: state.tab) {
            guard state.tab == .habits else { return }
            await detectWalk()
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your change right now")
                .scaledFont(size: 13)
                .foregroundStyle(Color.white.opacity(0.85))
            Text(state.plan.title)
                .scaledFont(size: 23, weight: .bold, relativeTo: .title2)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = state.plan.reason {
                Text(reason)
                    .scaledFont(size: 15)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle()
                .fill(Color.white.opacity(0.4))
                .frame(height: 1)
                .padding(.vertical, 4)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start with")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.white.opacity(0.8))
                    Text(state.plan.startText)
                        .scaledFont(size: 16, weight: .bold)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grow into")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.white.opacity(0.8))
                    Text(state.plan.growText)
                        .scaledFont(size: 16, weight: .bold)
                }
                Spacer()
            }
            Text("\(state.plan.timesThisWeek) times this week · aiming for a couple of times, then most days")
                .scaledFont(size: 13)
                .fixedSize(horizontal: false, vertical: true)
            Text("Done \(state.checkInsThisWeek) times this week")
                .scaledFont(size: 13)
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .foregroundStyle(Color.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.terracotta, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var nextStepRow: some View {
        Button {
            showNextStep = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.maroon)
                    .frame(width: 48, height: 48)
                    .background(Color.blush.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your next step")
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(Color.ink)
                    Text(NextGoal.current(for: state).headline)
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.terracotta)
                    .accessibilityHidden(true)
            }
            .anurjaCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Your next step"))
    }

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Walk after lunch")
                .scaledFont(size: 17, weight: .bold)
            if let detectedSteps {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk.motion")
                        .foregroundStyle(Color.forest)
                        .accessibilityHidden(true)
                    Text("Motion detected: \(detectedSteps.formatted()) steps after your last meal")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.forest)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Did you do it?")
                .scaledFont(size: 13)
                .foregroundStyle(Color.muted)
            FlowLayout {
                ForEach(DidIt.allCases) { item in
                    Chip(title: item.localizedName, selected: did == item) { did = item }
                }
            }
            Text("How did you feel?")
                .scaledFont(size: 16, weight: .bold)
                .padding(.top, 4)
            FlowLayout {
                ForEach(HabitFeel.allCases) { item in
                    Chip(title: item.localizedName, selected: feel == item) { feel = item }
                }
            }
            Text("Was it difficult?")
                .scaledFont(size: 16, weight: .bold)
                .padding(.top, 4)
            FlowLayout {
                ForEach(Effort.allCases) { item in
                    Chip(title: item.difficultyName, selected: effort == item) { effort = item }
                }
            }
        }
        .anurjaCard()
    }

    /// Uses the motion coprocessor to see whether the person walked in the
    /// 90 minutes after their last meal, and pre-fills "Did you do it?".
    private func detectWalk() async {
        let calendar = Calendar.current
        let now = Date()
        let start = state.todayMeals.last?.date
            ?? calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now)
            ?? now
        let end = min(now, start.addingTimeInterval(90 * 60))
        guard let steps = await motion.steps(from: start, to: end) else { return }
        detectedSteps = steps
        if steps >= 1000 {
            did = .yes
        } else if steps >= 400 {
            did = .little
        }
    }

    private func save() {
        guard !saved else { return }
        state.addCheckIn(HabitCheckIn(did: did, feel: feel, effort: effort, steps: detectedSteps))
        saved = true
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            saved = false
        }
    }
}

// MARK: - Your next step

struct NextGoal {
    var label: String
    var headline: String
    var detail: String

    @MainActor
    static func current(for state: AppState) -> NextGoal {
        let riceHeavy = state.learningMeals.filter { [MealFood.riceDal, .biryani, .idliDosa].contains($0.food) }.count
        if riceHeavy * 2 >= state.learningMeals.count {
            return NextGoal(
                label: String(localized: "Dietary focus"),
                headline: String(localized: "Vegetables over rice"),
                detail: String(localized: "Fill half your plate with vegetables or dal and eat them first, then a smaller portion of rice.")
            )
        }
        if !state.walkedToday {
            return NextGoal(
                label: String(localized: "Movement focus"),
                headline: String(localized: "A 10-minute walk after meals"),
                detail: String(localized: "Walking within 30 minutes of eating helps your muscles use the glucose from the meal.")
            )
        }
        return NextGoal(
            label: String(localized: "Dietary focus"),
            headline: String(localized: "Protein with every meal"),
            detail: String(localized: "Dal, curd, paneer, eggs or sprouts with your meal slow down how fast glucose rises.")
        )
    }
}

struct NextStepSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let goal = NextGoal.current(for: state)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        Text("Your next step")
                            .scaledFont(size: 32, weight: .bold, relativeTo: .largeTitle)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.ink)
                                .frame(width: 44, height: 44)
                                .background(Color.white, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Close"))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Right now")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.white.opacity(0.85))
                        Text(state.plan.title)
                            .scaledFont(size: 23, weight: .bold, relativeTo: .title2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Start with \(state.plan.startText), grow into \(state.plan.growText).")
                            .scaledFont(size: 14)
                    }
                    .foregroundStyle(Color.white)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.terracotta, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Next Goal")
                            .scaledFont(size: 17, weight: .bold)
                        Text(goal.label)
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.muted)
                        Text(goal.headline)
                            .scaledFont(size: 20, weight: .bold)
                            .foregroundStyle(Color.forest)
                        Text(goal.detail)
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .anurjaCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Remind me")
                            .scaledFont(size: 17, weight: .bold)
                        FlowLayout {
                            ForEach(ReminderSlot.allCases) { slot in
                                Chip(title: slot.title, selected: state.reminder == slot) {
                                    state.setReminder(slot, goal: "\(goal.label): \(goal.headline)")
                                }
                            }
                        }
                        if state.reminder != .off {
                            Text("We'll send a gentle nudge. You can turn it off any time.")
                                .scaledFont(size: 12)
                                .foregroundStyle(Color.muted)
                        }
                    }
                    .anurjaCard()
                }
                .padding(20)
            }
            .background(Color.cream)
        }
        .presentationDragIndicator(.visible)
    }
}

struct ReviewSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Fortnightly review")
                        .scaledFont(size: 32, weight: .bold, relativeTo: .largeTitle)
                        .foregroundStyle(Color.ink)
                    Text("You checked in \(state.checkIns.count) times and found it hard \(state.hardCheckIns) times. Whatever you pick is the right call.")
                        .scaledFont(size: 16)
                        .foregroundStyle(Color.forest)
                        .fixedSize(horizontal: false, vertical: true)
                    OptionRow(symbol: "checkmark.circle", title: "Keep it", subtitle: "Continue with this same change", selected: false) {
                        dismiss()
                    }
                    OptionRow(symbol: "arrow.up.right", title: "Grow it", subtitle: "Take the next size up", selected: false) {
                        state.growPlan()
                        dismiss()
                    }
                    OptionRow(symbol: "arrow.triangle.2.circlepath", title: "Swap it", subtitle: "Try a different gentle change", selected: false) {
                        state.swapPlan()
                        dismiss()
                    }
                }
                .padding(20)
            }
            .background(Color.cream)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

#Preview("Habits") {
    MainTabView().environmentObject(PreviewData.state(tab: .habits))
}

#Preview("Next step") {
    NextStepSheet().environmentObject(PreviewData.state())
}
