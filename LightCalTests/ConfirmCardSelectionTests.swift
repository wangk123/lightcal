import XCTest
@testable import LightCal

final class ConfirmCardSelectionTests: XCTestCase {
    private let items = [
        CompletedFoodItem(name: "米饭", grams: 100, nutrition: NutritionFacts(kcal: 116, protein: 2.6, fat: 0.3, carb: 25.9), source: .builtin),
        CompletedFoodItem(name: "鸡胸肉", grams: 100, nutrition: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), source: .builtin),
        CompletedFoodItem(name: "汽水", grams: 100, nutrition: NutritionFacts(kcal: 41, protein: 0, fat: 0, carb: 10.6), source: .builtin)
    ]

    func testAllSelectedByDefault() {
        let result = ConfirmCardView.rescaledItems(items, grams: [100, 100, 100], selected: [0, 1, 2])
        XCTAssertEqual(result.count, 3)
    }

    func testOnlySelectedItemsSaved() {
        let result = ConfirmCardView.rescaledItems(items, grams: [100, 100, 100], selected: [1])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "鸡胸肉")
    }

    func testNoneSelectedSavesNothing() {
        let result = ConfirmCardView.rescaledItems(items, grams: [100, 100, 100], selected: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testRescaleStillAppliesToSelected() {
        // 鸡胸肉 100g→200g：kcal 133→266
        let result = ConfirmCardView.rescaledItems(items, grams: [100, 200, 100], selected: [1])
        XCTAssertEqual(result.first?.grams, 200)
        XCTAssertEqual(result.first?.nutrition.kcal ?? 0, 266, accuracy: 0.001)
    }
}
