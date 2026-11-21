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
        .onAppear { KeyboardDismisser.shared.install() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                state.refreshClock()
            }
        }
        // Re-read glucose and re-run the activity model every five minutes.
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
            state.refreshClock()
        }
    }
}

/// Tap anywhere outside a text field to close the keyboard. Installed once on
/// the window, so it covers every screen, sheet and full-screen cover.
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()

    func install() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === self }) {
                let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
                tap.cancelsTouchesInView = false
                tap.delegate = self
                window.addGestureRecognizer(tap)
            }
        }
    }

    @objc private func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Ignore taps that land in a text field, so tapping one still focuses it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
