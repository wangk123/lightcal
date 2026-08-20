import XCTest
@testable import LightCal

final class NutritionFactsTests: XCTestCase {
    func testDefaultsAreZero() {
        let n = NutritionFacts()
        XCTAssertEqual(n.kcal, 0)
        XCTAssertEqual(n.protein, 0)
        XCTAssertTrue(n.extras.isEmpty)
    }

    func testAdditionMergesExtrasBySumming() {
        let a = NutritionFacts(kcal: 100, protein: 10, fat: 5, carb: 4, extras: ["fiber": 3])
        let b = NutritionFacts(kcal: 50, protein: 2, fat: 1, carb: 8, extras: ["fiber": 1, "sodium": 200])
        let sum = a + b
        XCTAssertEqual(sum.kcal, 150)
        XCTAssertEqual(sum.protein, 12)
        XCTAssertEqual(sum.extras["fiber"], 4)
        XCTAssertEqual(sum.extras["sodium"], 200)
    }

    func testScaledByGrams() {
        let per100 = NutritionFacts(kcal: 116, protein: 2.6, fat: 0.3, carb: 25.9, extras: ["fiber": 1])
        let scaled = NutritionFacts.scaled(per100, grams: 50)
        XCTAssertEqual(scaled.kcal, 58, accuracy: 0.001)
        XCTAssertEqual(scaled.protein, 1.3, accuracy: 0.001)
        XCTAssertEqual(scaled.extras["fiber"] ?? 0, 0.5, accuracy: 0.001)
    }

    func testCodableRoundTripWithExtras() throws {
        let n = NutritionFacts(kcal: 144, protein: 13.3, fat: 8.8, carb: 2.8, extras: ["sodium": 130])
        let data = try JSONEncoder().encode(n)
        let decoded = try JSONDecoder().decode(NutritionFacts.self, from: data)
        XCTAssertEqual(decoded, n)
    }
}
