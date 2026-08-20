import XCTest
@testable import LightCal

final class FoodDatabaseTests: XCTestCase {
    private let fixtureJSON = """
    {"version":1,"foods":[
      {"name":"米饭","aliases":["白米饭","大米饭"],"nutritionPer100g":{"kcal":116,"protein":2.6,"fat":0.3,"carb":25.9},"defaultServingGrams":200},
      {"name":"鸡胸肉","aliases":["鸡胸"],"nutritionPer100g":{"kcal":133,"protein":24.6,"fat":3.3,"carb":0.6}},
      {"name":"鸡蛋","aliases":[],"nutritionPer100g":{"kcal":144,"protein":13.3,"fat":8.8,"carb":2.8},"defaultServingGrams":50}
    ]}
    """

    private func makeDB() throws -> FoodDatabase {
        try FoodDatabase.load(from: Data(fixtureJSON.utf8))
    }

    func testExactNameMatch() throws {
        let db = try makeDB()
        let record = db.match(exact: "米饭")
        XCTAssertEqual(record?.nutritionPer100g.kcal, 116)
        XCTAssertEqual(record?.defaultServingGrams, 200)
    }

    func testAliasMatch() throws {
        let db = try makeDB()
        XCTAssertEqual(db.match(exact: "白米饭")?.name, "米饭")
    }

    func testNoMatchReturnsNil() throws {
        let db = try makeDB()
        XCTAssertNil(db.match(exact: "火锅"))
    }

    func testSearchByKeyword() throws {
        let db = try makeDB()
        let results = db.search("鸡")
        XCTAssertEqual(Set(results.map(\.name)), ["鸡胸肉", "鸡蛋"])
    }

    func testLoadFromBundleMissingResourceThrows() {
        let bundle = Bundle(for: BundleToken.self)  // 测试宿主 bundle，无 foods.json
        XCTAssertThrowsError(try FoodDatabase.loadFromBundle(bundle)) { error in
            XCTAssertEqual(error as? FoodDatabaseError, .resourceMissing)
        }
    }

    func testDecodeInvalidJSONThrows() {
        XCTAssertThrowsError(try FoodDatabase.load(from: Data("{\"bad\":1}".utf8)))
    }
}

private final class BundleToken {}
