import SwiftUI
import WidgetKit

@MainActor
final class WatchModel: ObservableObject {
    @Published var snapshot: GlucoseSnapshot?
    private let link = WatchConnectivityManager()
    private let preview: Bool

    init(preview: Bool = false) {
        self.preview = preview
        if preview {
            snapshot = .demo
            return
        }
        snapshot = SharedStore.load()
        link.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                self?.snapshot = snapshot
                SharedStore.save(snapshot)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        link.activate()
    }

    func sendMeal(_ food: MealFood) {
        guard !preview else { return }
        link.sendMeal(food: food.rawValue, id: UUID().uuidString)
    }
}

@main
struct AnurjaWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(model)
        }
    }
}

#Preview {
    WatchHomeView()
        .environmentObject(WatchModel(preview: true))
}
