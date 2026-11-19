import SwiftUI

@main
struct AnurjaApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.light)
                .tint(Color.terracotta)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if state.stage == .main {
                MainTabView().transition(.opacity)
            } else {
                OnboardingFlow().transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: state.stage)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                state.refreshClock()
            }
        }
    }
}
