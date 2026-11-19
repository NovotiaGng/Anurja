import SwiftUI

struct HabitsView: View {
    @EnvironmentObject private var state: AppState
    @State private var did: DidIt = .yes
    @State private var feel: HabitFeel = .lighter
    @State private var effort: Effort = .easy
    @State private var saved = false
    @State private var showReview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(
                    title: "Build gentler habits",
                    subtitle: "One small change at a time, at your pace."
                )
                planCard
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
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your change right now")
                .scaledFont(size: 13)
                .foregroundStyle(Color.white.opacity(0.85))
            Text(state.plan.title)
                .scaledFont(size: 23, weight: .bold, relativeTo: .title2)
                .fixedSize(horizontal: false, vertical: true)
            Text(state.plan.reason)
                .scaledFont(size: 15)
                .fixedSize(horizontal: false, vertical: true)
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

    private var checkInCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("After lunch today")
                .scaledFont(size: 17, weight: .bold)
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
            Text("How hard was it?")
                .scaledFont(size: 16, weight: .bold)
                .padding(.top, 4)
            FlowLayout {
                ForEach(Effort.allCases) { item in
                    Chip(title: item.localizedName, selected: effort == item) { effort = item }
                }
            }
        }
        .anurjaCard()
    }

    private func save() {
        guard !saved else { return }
        state.addCheckIn(HabitCheckIn(did: did, feel: feel, effort: effort))
        saved = true
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            saved = false
        }
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

struct MeView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text("Me")
                            .scaledFont(size: 34, weight: .bold, relativeTo: .largeTitle)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Button {
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
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Devices")
                            .scaledFont(size: 17, weight: .bold)
                        deviceRow(symbol: "applewatch", name: "Apple Watch", connected: state.watchLink == .connected)
                        deviceRow(symbol: "sensor.tag.radiowaves.forward", name: "CGM Device", connected: state.cgmLink == .connected)
                        if state.stepsToday > 0 {
                            Text("Steps today \(state.stepsToday)")
                                .scaledFont(size: 14)
                                .foregroundStyle(Color.muted)
                        }
                    }
                    .anurjaCard()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dashboard")
                            .scaledFont(size: 17, weight: .bold)
                        Toggle("Gamified view", isOn: $state.gamified)
                            .tint(Color.terracotta)
                        Text("Your data stays the same either way.")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.muted)
                    }
                    .anurjaCard()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What brings me here")
                            .scaledFont(size: 17, weight: .bold)
                        SegmentedTabs(
                            options: Goal.allCases,
                            title: { goal in
                                switch goal {
                                case .meals: String(localized: "Meals")
                                case .habits: String(localized: "Habits")
                                }
                            },
                            selection: $state.goal
                        )
                    }
                    .anurjaCard()
                    Text("Language follows your iPhone settings")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.muted)
                        .padding(.horizontal, 4)
                    DisclaimerText()
                        .padding(.horizontal, 4)
                    Button("Restart demo") {
                        state.restart()
                        dismiss()
                    }
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.terracotta)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(20)
            }
            .background(Color.cream)
        }
        .presentationDragIndicator(.visible)
    }

    private func deviceRow(symbol: String, name: LocalizedStringKey, connected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.maroon)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(name)
                .scaledFont(size: 15)
            Spacer()
            Text(connected ? "Connected" : "Not connected")
                .scaledFont(size: 14)
                .foregroundStyle(connected ? Color.forest : Color.muted)
        }
        .frame(minHeight: 44)
    }
}

#Preview("Habits") {
    MainTabView().environmentObject(PreviewData.state(tab: .habits))
}

#Preview("Me") {
    MeView().environmentObject(PreviewData.state())
}
