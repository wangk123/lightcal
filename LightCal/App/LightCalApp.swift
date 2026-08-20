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
            Text("主页占位（Task 16 替换为 RootTabView）")
                .font(.title)
                .foregroundStyle(DesignTokens.primary)
        } else {
            OnboardingView(store: container.store)
        }
    }
}
