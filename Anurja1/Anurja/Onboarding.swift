import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch state.stage {
            case .welcome:
                WelcomeView().transition(.opacity)
            case .connect:
                ConnectView().transition(.opacity)
            case .dashboard:
                DashboardChoiceView().transition(.opacity)
            case .goal:
                GoalView().transition(.opacity)
            case .main:
                Color.clear
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: state.stage)
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CreamBackground()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 18) {
                        Text("Anurja")
                            .font(.system(size: 32, weight: .medium, design: .serif).italic())
                            .foregroundStyle(Color.terracotta)
                            .padding(.top, 8)
                        Spacer(minLength: 12)
                        ZStack {
                            Circle().fill(Color.paleDisc)
                            SunburstMark().padding(28)
                        }
                        .frame(width: min(290, geo.size.width - 48), height: min(290, geo.size.width - 48))
                        Spacer(minLength: 12)
                        Text("Your rhythm, quietly understood")
                            .scaledFont(size: 36, weight: .bold, design: .serif, relativeTo: .largeTitle)
                            .foregroundStyle(Color.maroon)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Anurja learns how your everyday meals shape your energy. No judgment, just your own natural pattern.")
                            .scaledFont(size: 16)
                            .foregroundStyle(Color.forest)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        PrimaryButton(title: "Begin your journey") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                state.stage = .connect
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
    }
}

struct ConnectView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bothConnected: Bool {
        state.watchLink == .connected && state.cgmLink == .connected
    }

    var body: some View {
        ZStack {
            WarmBackground()
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        BackButton {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                state.goBack()
                            }
                        }
                        .padding(.leading, -10)
                        Text("YOUR FIRST TWO WEEKS")
                            .scaledFont(size: 13, weight: .semibold)
                            .tracking(1.1)
                            .foregroundStyle(Color.cream)
                            .padding(.top, 8)
                        Text("Let's learn your pattern,")
                            .scaledFont(size: 38, weight: .bold, design: .serif, relativeTo: .largeTitle)
                            .foregroundStyle(Color.cream)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("For two weeks, simply live your life. We'll quietly calibrate around your natural routine.")
                            .scaledFont(size: 16)
                            .foregroundStyle(Color.cream)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        DeviceCard(
                            symbol: "applewatch",
                            title: state.watchLink == .connected ? String(localized: "Apple Watch Connected") : String(localized: "Apple Watch"),
                            subtitle: subtitle(for: state.watchLink),
                            state: state.watchLink
                        ) {
                            state.connectWatch()
                        }
                        DeviceCard(
                            symbol: "sensor.tag.radiowaves.forward",
                            title: state.cgmLink == .connected ? String(localized: "CGM Device Connected") : String(localized: "CGM Device"),
                            subtitle: subtitle(for: state.cgmLink),
                            state: state.cgmLink
                        ) {
                            state.connectCGM()
                        }
                        Spacer(minLength: 24)
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                state.skipConnect()
                            }
                        } label: {
                            Text("Skip for now, use demo data")
                                .scaledFont(size: 15)
                                .foregroundStyle(Color.cream.opacity(0.9))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        PrimaryButton(title: "Next", enabled: bothConnected) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                state.stage = .dashboard
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
        }
    }

    private func subtitle(for link: LinkState) -> String {
        switch link {
        case .idle: String(localized: "Tap to connect")
        case .connecting: String(localized: "Connecting…")
        case .connected: String(localized: "Calibrating in the background")
        }
    }
}

private struct DeviceCard: View {
    var symbol: String
    var title: String
    var subtitle: String
    var state: LinkState
    var connect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(Color.maroon)
                .frame(width: 60, height: 60)
                .background(Color.blush.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(size: 18, weight: .medium)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.forest)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(14)
        .background(Color.cream, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .idle:
            Button(action: connect) {
                Text("Connect")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.terracotta, in: Capsule())
            }
            .buttonStyle(.plain)
        case .connecting:
            ProgressView()
                .tint(Color.terracotta)
                .frame(width: 44, height: 44)
                .accessibilityLabel(Text("Connecting…"))
        case .connected:
            Circle()
                .fill(Color.terracotta)
                .frame(width: 22, height: 22)
                .accessibilityLabel(Text("Connected"))
        }
    }
}

struct DashboardChoiceView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WarmBackground()
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        BackButton {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { state.goBack() }
                        }
                        .padding(.leading, -10)
                        Text("YOUR DASHBOARD")
                            .scaledFont(size: 13, weight: .semibold)
                            .tracking(1.1)
                            .foregroundStyle(Color.cream)
                            .padding(.top, 8)
                        Text("Wanna switch things up?")
                            .scaledFont(size: 38, weight: .bold, relativeTo: .largeTitle)
                            .foregroundStyle(Color.cream)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Pick the view that feels closest. You can change it anytime.")
                            .scaledFont(size: 15)
                            .foregroundStyle(Color.cream)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 12)
                        OptionRow(
                            symbol: "chart.bar",
                            title: "Simple dashboard",
                            subtitle: "Calm view of meals and energy",
                            selected: !state.gamified
                        ) { state.gamified = false }
                        OptionRow(
                            symbol: "leaf",
                            title: "Gamified dashboard",
                            subtitle: "Small rewards as your habits grow",
                            selected: state.gamified
                        ) { state.gamified = true }
                        Spacer(minLength: 20)
                        PrimaryButton(title: "Continue") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                state.stage = .goal
                            }
                        }
                        Text("Your data stays the same either way.")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.cream)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
        }
    }
}

struct GoalView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WarmBackground()
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        BackButton {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { state.goBack() }
                        }
                        .padding(.leading, -10)
                        HStack(spacing: 28) {
                            Image(systemName: "leaf")
                            Image(systemName: "fork.knife")
                            Image(systemName: "sun.max")
                        }
                        .font(.system(size: 40))
                        .foregroundStyle(Color.maroon)
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .background(
                            LinearGradient(colors: [Color.heroStart, Color.heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
                        .accessibilityHidden(true)
                        .padding(.top, 4)
                        Text("What brings you here today?")
                            .scaledFont(size: 34, weight: .bold, design: .serif, relativeTo: .largeTitle)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                        Text("Pick the one that feels closest. You can change it anytime.")
                            .scaledFont(size: 15)
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        OptionRow(symbol: Goal.meals.symbol, title: Goal.meals.title, subtitle: Goal.meals.subtitle, selected: state.goal == .meals) {
                            state.goal = .meals
                        }
                        OptionRow(symbol: Goal.habits.symbol, title: Goal.habits.title, subtitle: Goal.habits.subtitle, selected: state.goal == .habits) {
                            state.goal = .habits
                        }
                        Spacer(minLength: 16)
                        PrimaryButton(title: "Continue") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                state.finishOnboarding()
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
        }
    }
}

struct BackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.cream)
                .frame(width: 44, height: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Back"))
    }
}

#Preview("Welcome") {
    WelcomeView().environmentObject(PreviewData.state())
}

#Preview("Connect") {
    ConnectView().environmentObject(PreviewData.state())
}

#Preview("Dashboard") {
    DashboardChoiceView().environmentObject(PreviewData.state())
}

#Preview("Goal") {
    GoalView().environmentObject(PreviewData.state())
}
