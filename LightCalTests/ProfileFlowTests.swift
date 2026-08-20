import XCTest
@testable import LightCal

final class FormattingWeightTests: XCTestCase {
    func testWeightTextKg() {
        XCTAssertEqual(Formatting.weightText(kg: 70, unit: .kg), "70.0 kg")
    }

    func testWeightTextJin() {
        XCTAssertEqual(Formatting.weightText(kg: 70, unit: .jin), "140.0 斤")
    }
}

@MainActor
final class ProfileFlowTests: XCTestCase {
    func testEditGoalAppendsNewVersionKeepingHistory() throws {
        let store = try DataStore.makeInMemory()
        let targets = DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200)
        try store.appendGoal(Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: targets, systemTargets: targets, waterTargetMl: 2100))

        // 模拟 EditGoalSheet 的保存逻辑
        let newTargets = DailyTargets(kcal: 1750, protein: 124, fat: 55, carb: 195)
        try store.appendGoal(Goal(
            targetWeightKg: 64, startDate: .now, startWeightKg: 69,
            targets: newTargets, systemTargets: targets, waterTargetMl: 2070
        ))
        XCTAssertEqual(try store.allGoals().count, 2)
        XCTAssertEqual(try store.currentGoal()?.targetWeightKg, 64)
        // 系统默认值保留旧版，微调值为新版（spec 3.2）
        XCTAssertEqual(try store.currentGoal()?.systemTargets, targets)
    }
}
