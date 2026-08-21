import XCTest
@testable import LightCal

@MainActor
final class DataStoreTests: XCTestCase {
    private func makeStore() throws -> DataStore {
        try DataStore.makeInMemory()
    }

    private func day(_ daysFromNow: Int = 0) -> Date {
        Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: daysFromNow, to: .now)!)
    }

    func testSaveAndQueryLogItems() throws {
        let store = try makeStore()
        let item = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        try store.saveLogItems([item], date: day(), meal: .lunch)
        let items = try store.logItems(on: day())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "鸡胸肉")
        XCTAssertEqual(items[0].meal, "午餐")
        XCTAssertEqual(items[0].source, "builtin")
        // 营养快照冗余落库（spec 3.4）
        XCTAssertEqual(items[0].nutrition.kcal, 133, accuracy: 0.001)
    }

    func testDaySummaryAggregatesNutritionAndWater() throws {
        let store = try makeStore()
        let chicken = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        let rice = CompletedFoodItem(name: "米饭", grams: 100, nutrition: NutritionFacts(kcal: 116, protein: 2.6, fat: 0.3, carb: 25.9), source: .builtin)
        try store.saveLogItems([chicken, rice], date: day(), meal: .dinner)
        try store.addWater(ml: 250, date: day())
        try store.addWater(ml: 500, date: day())
        let summary = try store.daySummary(day())
        XCTAssertEqual(summary.totalNutrition.kcal, 249, accuracy: 0.001)
        XCTAssertEqual(summary.totalNutrition.protein, 27.2, accuracy: 0.001)
        XCTAssertEqual(summary.waterMl, 750, accuracy: 0.001)
    }

    func testWaterItemsSortedByCreatedAt() throws {
        let store = try makeStore()
        try store.addWater(ml: 250, date: day())
        try store.addWater(ml: 500, date: day())
        let items = try store.waterItems(on: day())
        XCTAssertEqual(items.map(\.amountMl), [250, 500])
    }

    func testDeleteWaterItem() throws {
        let store = try makeStore()
        try store.addWater(ml: 250, date: day())
        let items = try store.waterItems(on: day())
        XCTAssertEqual(items.count, 1)
        try store.deleteWaterItem(items[0])
        XCTAssertTrue(try store.waterItems(on: day()).isEmpty)
        // 删除后日汇总联动归零
        XCTAssertEqual(try store.daySummary(day()).waterMl, 0, accuracy: 0.001)
    }

    func testGoalVersioningKeepsHistory() throws {
        let store = try makeStore()
        let g1 = Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200), systemTargets: DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200), waterTargetMl: 2100)
        let g2 = Goal(targetWeightKg: 64, startDate: .now, startWeightKg: 69, targets: DailyTargets(kcal: 1750, protein: 124, fat: 55, carb: 195), systemTargets: DailyTargets(kcal: 1750, protein: 124, fat: 55, carb: 195), waterTargetMl: 2070)
        try store.appendGoal(g1)
        try store.appendGoal(g2)
        XCTAssertEqual(try store.allGoals().count, 2)
        XCTAssertEqual(try store.currentGoal()?.targetWeightKg, 64)
    }

    func testCustomFoodCRUDAndLookup() throws {
        let store = try makeStore()
        let food = CustomFood(name: "老妈红烧肉", nutritionPer100g: NutritionFacts(kcal: 350, protein: 15, fat: 30, carb: 5))
        try store.saveCustomFood(food)
        XCTAssertEqual(try store.allCustomFoods().count, 1)
        try store.deleteCustomFood(food)
        XCTAssertTrue(try store.allCustomFoods().isEmpty)
    }

    func testWeightSamplesSortedDescending() throws {
        let store = try makeStore()
        try store.addWeight(kg: 70, date: day(-3))
        try store.addWeight(kg: 69.5, date: day(-1))
        try store.addWeight(kg: 69, date: day())
        let samples = try store.weightSamples(limit: 10)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples[0].weightKg, 69)  // 最新在前
        XCTAssertEqual(samples[2].weightKg, 70)
    }

    func testPresetFoodCRUD() throws {
        let store = try makeStore()
        let preset = PresetFood(name: "鸡蛋", nutritionPer100g: NutritionFacts(kcal: 144, protein: 13.3, fat: 8.8, carb: 2.8))
        try store.savePresetFood(preset)
        XCTAssertEqual(try store.allPresetFoods().count, 1)
        XCTAssertEqual(try store.allPresetFoods().first?.name, "鸡蛋")
        try store.deletePresetFood(preset)
        XCTAssertTrue(try store.allPresetFoods().isEmpty)
    }

    func testSaveLogItemsPersistsVolumeMl() throws {
        let store = try makeStore()
        let item = CompletedFoodItem(
            name: "美式咖啡", grams: 500,
            nutrition: NutritionFacts(kcal: 10, protein: 0.5, fat: 0, carb: 2),
            source: .builtin, volumeMl: 500
        )
        try store.saveLogItems([item], date: day(), meal: .breakfast)
        let items = try store.logItems(on: day())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].volumeMl, 500)
    }

    func testExportJSONRoundTrip() throws {
        let store = try makeStore()
        let item = CompletedFoodItem(name: "鸡蛋", grams: 100, nutrition: NutritionFacts(kcal: 144, protein: 13.3, fat: 8.8, carb: 2.8), source: .builtin)
        try store.saveLogItems([item], date: day(), meal: .breakfast)
        let json = try store.exportJSON()
        XCTAssertTrue(json.count > 10)
        // 合法 JSON 即可（Task 19 会做完整导入导出格式校验）
        _ = try JSONSerialization.jsonObject(with: json)
    }
}
