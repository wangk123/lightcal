import XCTest
@testable import LightCal

final class NutritionCompletionTests: XCTestCase {
    private let database = FoodDatabase(foods: [
        FoodRecord(name: "鸡蛋", aliases: [], nutritionPer100g: NutritionFacts(kcal: 144, protein: 13.3, fat: 8.8, carb: 2.8), defaultServingGrams: 50),
        FoodRecord(name: "米饭", aliases: ["白米饭"], nutritionPer100g: NutritionFacts(kcal: 116, protein: 2.6, fat: 0.3, carb: 25.9), defaultServingGrams: 200)
    ])

    func testBuiltinMatchFirst() async {
        let completion = NutritionCompletion(
            database: database,
            customFoodLookup: { _ in nil },
            estimator: { _ in throw DeepSeekError.decodingFailed }
        )
        let items = await completion.complete([ParsedFoodItem(name: "白米饭", grams: 100, count: nil, unit: nil, meal: nil)])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].source, .builtin)
        XCTAssertEqual(items[0].grams, 100)
        XCTAssertEqual(items[0].nutrition.kcal, 116, accuracy: 0.001)
    }

    func testCustomFoodSecond() async {
        let custom = FoodRecord(name: "老妈红烧肉", aliases: [], nutritionPer100g: NutritionFacts(kcal: 350, protein: 15, fat: 30, carb: 5), defaultServingGrams: 100)
        let completion = NutritionCompletion(
            database: database,
            customFoodLookup: { name in name == "老妈红烧肉" ? custom : nil },
            estimator: { _ in throw DeepSeekError.decodingFailed }
        )
        let items = await completion.complete([ParsedFoodItem(name: "老妈红烧肉", grams: 200, count: nil, unit: nil, meal: nil)])
        XCTAssertEqual(items[0].source, .custom)
        XCTAssertEqual(items[0].nutrition.kcal, 700, accuracy: 0.001)
    }

    func testEstimatorThirdWithAIMark() async {
        let completion = NutritionCompletion(
            database: database,
            customFoodLookup: { _ in nil },
            estimator: { name in
                XCTAssertEqual(name, "螺蛳粉")
                return NutritionFacts(kcal: 180, protein: 6, fat: 8, carb: 22)
            }
        )
        let items = await completion.complete([ParsedFoodItem(name: "螺蛳粉", grams: 100, count: nil, unit: nil, meal: nil)])
        XCTAssertEqual(items[0].source, .aiEstimated)
        XCTAssertEqual(items[0].nutrition.kcal, 180, accuracy: 0.001)
    }

    func testEstimatorFailureFallsBackToZeroNutrition() async {
        let completion = NutritionCompletion(
            database: database,
            customFoodLookup: { _ in nil },
            estimator: { _ in throw DeepSeekError.decodingFailed }
        )
        let items = await completion.complete([ParsedFoodItem(name: "神秘食物", grams: nil, count: nil, unit: nil, meal: nil)])
        XCTAssertEqual(items[0].source, .aiEstimated)
        XCTAssertEqual(items[0].nutrition, NutritionFacts())
        XCTAssertEqual(items[0].grams, PortionDefaults.fallbackGrams)
    }

    func testGramsResolution() {
        // 显式克重优先
        XCTAssertEqual(NutritionCompletion.grams(for: ParsedFoodItem(name: "鸡", grams: 80, count: nil, unit: nil, meal: nil), record: nil), 80)
        // 数量 × 单位默认克重
        XCTAssertEqual(NutritionCompletion.grams(for: ParsedFoodItem(name: "鸡蛋", grams: nil, count: 2, unit: "个", meal: nil), record: nil), 120)
        // 数量 × 食物自带每份克重（鸡蛋 50g/个）
        let egg = database.match(exact: "鸡蛋")!
        XCTAssertEqual(NutritionCompletion.grams(for: ParsedFoodItem(name: "鸡蛋", grams: nil, count: 2, unit: "个", meal: nil), record: egg), 100)
        // 只有单位无数量 → 一份
        XCTAssertEqual(NutritionCompletion.grams(for: ParsedFoodItem(name: "牛奶", grams: nil, count: nil, unit: "杯", meal: nil), record: nil), 250)
        // 无任何信息 → 兜底
        XCTAssertEqual(NutritionCompletion.grams(for: ParsedFoodItem(name: "x", grams: nil, count: nil, unit: nil, meal: nil), record: nil), PortionDefaults.fallbackGrams)
    }
}
