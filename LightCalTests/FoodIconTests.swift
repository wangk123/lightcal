import XCTest
@testable import LightCal

final class FoodIconTests: XCTestCase {
    func testMeatSymbol() {
        XCTAssertEqual(FoodIcon.symbol(for: "鸡胸肉"), "fork.knife")
        XCTAssertEqual(FoodIcon.symbol(for: "牛肉"), "fork.knife")
    }

    func testSeafoodSymbol() {
        XCTAssertEqual(FoodIcon.symbol(for: "三文鱼"), "fish.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "虾"), "fish.fill")
    }

    func testVegetableSymbol() {
        XCTAssertEqual(FoodIcon.symbol(for: "西兰花"), "leaf.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "豆腐"), "leaf.fill")
    }

    func testStapleSymbol() {
        XCTAssertEqual(FoodIcon.symbol(for: "米饭"), "takeoutbag.and.cup.and.straw.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "面条"), "takeoutbag.and.cup.and.straw.fill")
    }

    func testFruitSymbol() {
        XCTAssertEqual(FoodIcon.symbol(for: "苹果"), "carrot.fill")
    }

    func testUnknownFallsBackToForkKnife() {
        XCTAssertEqual(FoodIcon.symbol(for: "神秘食物"), "fork.knife")
    }
}
