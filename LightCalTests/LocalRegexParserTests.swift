import XCTest
@testable import LightCal

final class LocalRegexParserTests: XCTestCase {
    func testExplicitGrams() async throws {
        let items = try await LocalRegexParser().parse("100g鸡胸肉")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "鸡胸肉")
        XCTAssertEqual(items[0].grams, 100)
        XCTAssertNil(items[0].count)
    }

    func testChineseCountAndUnit() async throws {
        let items = try await LocalRegexParser().parse("两个鸡蛋和一杯牛奶")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "鸡蛋")
        XCTAssertEqual(items[0].count, 2)
        XCTAssertEqual(items[0].unit, "个")
        XCTAssertEqual(items[1].name, "牛奶")
        XCTAssertEqual(items[1].count, 1)
        XCTAssertEqual(items[1].unit, "杯")
    }

    func testMealDetection() async throws {
        let items = try await LocalRegexParser().parse("晚饭吃了100克牛肉")
        XCTAssertEqual(items[0].meal, .dinner)
    }

    func testBareTextFallsBackToNameItem() async throws {
        let items = try await LocalRegexParser().parse("随便聊聊")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "随便聊聊")
        XCTAssertNil(items[0].grams)
    }

    func testEmptyTextYieldsNoItems() async throws {
        let items = try await LocalRegexParser().parse("   ")
        XCTAssertTrue(items.isEmpty)
    }

    func testParseCountMapping() {
        XCTAssertEqual(LocalRegexParser.parseCount("两"), 2)
        XCTAssertEqual(LocalRegexParser.parseCount("三"), 3)
        XCTAssertEqual(LocalRegexParser.parseCount("10"), 10)
        XCTAssertNil(LocalRegexParser.parseCount("百"))
    }
}
