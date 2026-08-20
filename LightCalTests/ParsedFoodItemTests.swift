import XCTest
@testable import LightCal

final class ParsedFoodItemTests: XCTestCase {
    func testMealKindRawValues() {
        XCTAssertEqual(MealKind.breakfast.rawValue, "早餐")
        XCTAssertEqual(MealKind.lunch.rawValue, "午餐")
        XCTAssertEqual(MealKind.dinner.rawValue, "晚餐")
        XCTAssertEqual(MealKind.snack.rawValue, "加餐")
        XCTAssertEqual(MealKind(rawValue: "午餐"), .lunch)
    }

    func testParsedFoodItemEquatable() {
        let a = ParsedFoodItem(name: "鸡胸肉", grams: 100, count: nil, unit: nil, meal: .lunch)
        let b = ParsedFoodItem(name: "鸡胸肉", grams: 100, count: nil, unit: nil, meal: .lunch)
        XCTAssertEqual(a, b)
    }

    func testParsedFoodItemCodable() throws {
        let item = ParsedFoodItem(name: "鸡蛋", grams: nil, count: 2, unit: "个", meal: nil)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ParsedFoodItem.self, from: data)
        XCTAssertEqual(decoded, item)
    }
}
