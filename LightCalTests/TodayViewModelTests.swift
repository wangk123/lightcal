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

    func testTimelineMergesFoodAndWaterByCreatedAt() async throws {
        let vm = try await makeViewModel()
        vm.addWater(ml: 250)                       // 第一条：饮水
        let item = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()                             // 第二条：食物
        vm.addWater(ml: 500)                       // 第三条：饮水
        await vm.refresh()

        XCTAssertEqual(vm.timeline.count, 3)
        guard case .water(let w1) = vm.timeline[0],
              case .food(let food) = vm.timeline[1],
              case .water(let w2) = vm.timeline[2] else {
            return XCTFail("时间线顺序应为：水250 → 食物 → 水500")
        }
        XCTAssertEqual(w1.amountMl, 250)
        XCTAssertEqual(w2.amountMl, 500)
        XCTAssertEqual(food.name, "鸡胸肉")
    }

    func testTimelineEntryDisplayProperties() async throws {
        let vm = try await makeViewModel()
        vm.addWater(ml: 250)
        let item = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()
        await vm.refresh()

        guard let waterEntry = vm.timeline.first, case .water = waterEntry else { return XCTFail("第一条应为饮水") }
        XCTAssertEqual(waterEntry.titleText, "250 ml")
        XCTAssertEqual(waterEntry.meal, "饮水")
        XCTAssertEqual(waterEntry.icon, "drop.fill")
        XCTAssertNil(waterEntry.kcalText)

        guard let foodEntry = vm.timeline.last, case .food = foodEntry else { return XCTFail("最后一条应为食物") }
        XCTAssertEqual(foodEntry.titleText, "鸡胸肉 100g")
        XCTAssertEqual(foodEntry.kcalText, "133")
        XCTAssertFalse(foodEntry.isAIEstimated)
        XCTAssertEqual(foodEntry.icon, "fork.knife")
    }

    func testDeleteFoodAndWaterEntries() async throws {
        let vm = try await makeViewModel()
        let item = CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin)
        vm.draft = LogDraft(items: [item], originalText: nil)
        vm.saveDraft()
        vm.addWater(ml: 250)
        await vm.refresh()
        XCTAssertEqual(vm.timeline.count, 2)

        // 删饮水：时间线只剩食物，饮水汇总归零
        if case .water = vm.timeline[1] {} else { return XCTFail("第二条应为饮水") }
        await vm.delete(entry: vm.timeline[1])
        XCTAssertEqual(vm.timeline.count, 1)
        XCTAssertEqual(vm.summary.waterMl, 0, accuracy: 0.001)

        // 删食物：时间线空，营养汇总归零
        await vm.delete(entry: vm.timeline[0])
        XCTAssertTrue(vm.timeline.isEmpty)
        XCTAssertEqual(vm.summary.totalNutrition.kcal, 0, accuracy: 0.001)
    }

    func testEmptyTimeline() async throws {
        let vm = try await makeViewModel()
        XCTAssertTrue(vm.timeline.isEmpty)
    }
}
