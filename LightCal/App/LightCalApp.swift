import SwiftUI
import SwiftData

@main
struct LightCalApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

struct AppRootView: View {
    private let container = AppContainer.shared

    var body: some View {
        if (try? container.store.profile()) != nil {
            RootTabView()
        } else {
            OnboardingView(store: container.store)
        }
    }
}
