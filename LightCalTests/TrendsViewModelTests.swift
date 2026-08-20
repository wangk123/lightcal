import XCTest
@testable import LightCal

@MainActor
final class TrendsViewModelTests: XCTestCase {
    private func makeSeededStore() throws -> DataStore {
        let store = try DataStore.makeInMemory()
        let targets = DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200)
        try store.appendGoal(Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: targets, systemTargets: targets, waterTargetMl: 2100))
        // 4 个体重点：体重趋势可用，图表达标（spec 7.6 ≥4 点才画图）；29 天前（避开时间漂移边界）
        for (daysAgo, kg) in [(29, 70.0), (20, 69.6), (10, 69.2), (0, 68.9)] {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            try store.addWeight(kg: kg, date: date)
        }
        // 昨天的打卡
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        try store.saveLogItems([CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133), source: .builtin)], date: yesterday, meal: .lunch)
        return store
    }

    func testMonthRangeYields4WeightPointsAndEnoughIntake() async throws {
        let vm = TrendsViewModel(store: try makeSeededStore())
        vm.range = .month
        await vm.refresh()
        XCTAssertEqual(vm.weightPoints.count, 4)
        XCTAssertTrue(vm.hasEnoughWeightData)
        XCTAssertEqual(vm.targetKcal, 1800)
        XCTAssertGreaterThanOrEqual(vm.intakePoints.count, 30)  // 月视图：近 30 天逐日
    }

    func testWeekRangeYields7IntakePoints() async throws {
        let vm = TrendsViewModel(store: try makeSeededStore())
        vm.range = .week
        await vm.refresh()
        XCTAssertEqual(vm.intakePoints.count, 7)
        XCTAssertEqual(vm.weightPoints.count, 1)  // 只有 0 天前的体重在 7 天窗口内
    }

    func testTrendLineFitsFallingWeights() async throws {
        let vm = TrendsViewModel(store: try makeSeededStore())
        vm.range = .month
        await vm.refresh()
        XCTAssertEqual(vm.trendPoints.count, 2)
        // 趋势线两端：起端 ≈ 拟合截距、末端低于起端（体重在降）
        XCTAssertGreaterThan(vm.trendPoints[0].kg, vm.trendPoints[1].kg)
    }

    func testInsufficientWeightDataShowsStatCardNotChart() async throws {
        let store = try DataStore.makeInMemory()
        try store.addWeight(kg: 70, date: .now)
        let vm = TrendsViewModel(store: store)
        vm.range = .week
        await vm.refresh()
        XCTAssertFalse(vm.hasEnoughWeightData)
        XCTAssertTrue(vm.trendPoints.isEmpty)
    }
}
