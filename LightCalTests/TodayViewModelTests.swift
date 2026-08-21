import XCTest
@testable import LightCal

final class FormattingTests: XCTestCase {
    func testKcalText() {
        XCTAssertEqual(Formatting.kcalText(1800), "1800")
        XCTAssertEqual(Formatting.kcalText(1800.5), "1801")
        XCTAssertEqual(Formatting.kcalText(-320), "-320")
    }

    func testGramsText() {
        XCTAssertEqual(Formatting.gramsText(28.4), "28g")
    }

    func testDaysText() {
        XCTAssertEqual(Formatting.daysText(49), "49 天")
        XCTAssertEqual(Formatting.daysText(nil), "--")
    }

    func testMlText() {
        XCTAssertEqual(Formatting.mlText(2100), "2100")
    }

    func testTimeText() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 14, minute: 30))!
        XCTAssertEqual(Formatting.timeText(date), "14:30")
    }
}

final class MockPipeline: LoggingPipelining, @unchecked Sendable {
    func process(text: String) async throws -> LogDraft { LogDraft(items: [], originalText: text) }
    func process(photoData: Data) async throws -> LogDraft { LogDraft(items: [], originalText: nil) }
}

@MainActor
final class TodayViewModelTests: XCTestCase {
    private func makeViewModel() async throws -> TodayViewModel {
        let store = try DataStore.makeInMemory()
        let targets = DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200)
        try store.appendGoal(Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: targets, systemTargets: targets, waterTargetMl: 2100))
        let database = FoodDatabase(foods: [FoodRecord(name: "鸡胸肉", aliases: [], nutritionPer100g: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), defaultServingGrams: 100)])
        let vm = TodayViewModel(store: store, database: database, healthKit: MockHealthKit(), pipeline: MockPipeline())
        await vm.refresh()
        return vm
    }

    func testGapAfterSavingChicken() async throws {
        let vm = try await makeViewModel()
        let item = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()
        await vm.refresh()
        XCTAssertEqual(vm.summary.totalNutrition.kcal, 133, accuracy: 0.001)
        XCTAssertEqual(vm.gap.remainingKcal, 1800 - 133, accuracy: 0.001)
        XCTAssertEqual(vm.gap.proteinGap, 126 - 24.6, accuracy: 0.001)
    }

    func testWaterQuickAdd() async throws {
        let vm = try await makeViewModel()
        vm.addWater(ml: 500)
        await vm.refresh()
        XCTAssertEqual(vm.summary.waterMl, 500)
        XCTAssertEqual(vm.waterText, "500 / 2100 ml")
    }

    func testSuggestionsAppearWhenProteinGap() async throws {
        let vm = try await makeViewModel()
        let item = CompletedFoodItem(name: "米饭", grams: 300, nutrition: NutritionFacts(kcal: 348, protein: 7.8, fat: 0.9, carb: 77.7), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()
        await vm.refresh()
        XCTAssertFalse(vm.suggestions.isEmpty)
        XCTAssertEqual(vm.suggestions.first?.name, "鸡胸肉")
    }

    func testSuggestionsConstrainedToPresetFoods() async throws {
        // 设置预设后：建议只来自预设（牛奶），不再推荐内置库里的鸡胸肉
        let store = try DataStore.makeInMemory()
        let targets = DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200)
        try store.appendGoal(Goal(targetWeightKg: 65, startDate: .now, startWeightKg: 70, targets: targets, systemTargets: targets, waterTargetMl: 2100))
        try store.savePresetFood(PresetFood(name: "牛奶", nutritionPer100g: NutritionFacts(kcal: 65, protein: 3.3, fat: 3.6, carb: 4.9)))
        let database = FoodDatabase(foods: [FoodRecord(name: "鸡胸肉", aliases: [], nutritionPer100g: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), defaultServingGrams: 100)])
        let vm = TodayViewModel(store: store, database: database, healthKit: MockHealthKit(), pipeline: MockPipeline())
        // 造成蛋白缺口
        let item = CompletedFoodItem(name: "米饭", grams: 300, nutrition: NutritionFacts(kcal: 348, protein: 7.8, fat: 0.9, carb: 77.7), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()
        await vm.refresh()
        XCTAssertTrue(vm.hasPresets)
        XCTAssertFalse(vm.suggestions.isEmpty)
        XCTAssertTrue(vm.suggestions.allSatisfy { $0.name == "牛奶" })
    }
}
