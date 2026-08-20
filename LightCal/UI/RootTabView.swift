import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayDashboardView(viewModel: TodayViewModel(
                store: AppContainer.shared.store,
                database: AppContainer.shared.database,
                healthKit: AppContainer.shared.healthKit,
                pipeline: AppContainer.shared.pipeline
            ))
            .tabItem { Label("今日", systemImage: "sun.max.fill") }

            TrendsView(viewModel: TrendsViewModel(store: AppContainer.shared.store))
                .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }

            Text("我的页（Task 19）")
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}
