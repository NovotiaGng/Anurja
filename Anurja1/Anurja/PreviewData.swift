import SwiftUI

enum PreviewData {
    @MainActor static func state(tab: AppTab = .home) -> AppState {
        let state = AppState(preview: true)
        state.tab = tab
        return state
    }
}
