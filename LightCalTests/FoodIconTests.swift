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

    func testCompoundWordsBeatSingleCharKeywords() {
        XCTAssertEqual(FoodIcon.symbol(for: "鸡蛋"), "circle.hexagongrid.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "牛奶"), "cup.and.saucer.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "牛油果"), "carrot.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "牛油果酱"), "carrot.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "牛角包"), "takeoutbag.and.cup.and.straw.fill")
    }

    func testRemovedBareKeywords() {
        // 裸「甜」已删：甜菜根/甜瓜 归蔬菜而非甜品
        XCTAssertEqual(FoodIcon.symbol(for: "甜菜根"), "leaf.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "甜瓜"), "leaf.fill")
        // 裸「水」已删：水果 归水果而非饮品
        XCTAssertEqual(FoodIcon.symbol(for: "水果"), "carrot.fill")
        // 裸「卷」已删：肥牛卷 归肉而非主食
        XCTAssertEqual(FoodIcon.symbol(for: "肥牛卷"), "fork.knife")
        // 裸「排」已删：牛排/猪排骨 仍按具体词归肉
        XCTAssertEqual(FoodIcon.symbol(for: "牛排"), "fork.knife")
        XCTAssertEqual(FoodIcon.symbol(for: "猪排骨"), "fork.knife")
    }

    func testExpandedCoverage() {
        XCTAssertEqual(FoodIcon.symbol(for: "吐司"), "takeoutbag.and.cup.and.straw.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "蛤蜊"), "fish.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "生蚝"), "fish.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "辣椒"), "leaf.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "洋葱"), "leaf.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "椰子"), "carrot.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "石榴"), "carrot.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "卡布奇诺"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "拿铁"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "全麦面包"), "takeoutbag.and.cup.and.straw.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "鸡胸肉"), "fork.knife")
        XCTAssertEqual(FoodIcon.symbol(for: "鸡腿肉"), "fork.knife")
        XCTAssertEqual(FoodIcon.symbol(for: "炒饭"), "takeoutbag.and.cup.and.straw.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "麦片"), "takeoutbag.and.cup.and.straw.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "番茄"), "leaf.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "海鲜"), "fish.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "栗子"), "circle.grid.cross.fill")
    }

    func testWaterExactName() {
        XCTAssertEqual(FoodIcon.symbol(for: "水"), "drop.fill")
    }

    func testNewDrinkSymbols() {
        XCTAssertEqual(FoodIcon.symbol(for: "美式咖啡"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "黑咖啡"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "豆浆"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "奶茶"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "柠檬水"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "气泡水"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "椰子水"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "椰奶"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "奶昔"), "wineglass.fill")
        XCTAssertEqual(FoodIcon.symbol(for: "果昔"), "wineglass.fill")
    }
}
