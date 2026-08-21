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
    // @Query 响应式查询：建档保存后 SwiftUI 自动重算，无需重启即可进入主页
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingView(store: AppContainer.shared.store)
            } else {
                RootTabView()
            }
        }
        .modelContainer(AppContainer.shared.store.container)
    }
}
