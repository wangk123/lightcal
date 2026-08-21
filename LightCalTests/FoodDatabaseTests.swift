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

    func testRefinedMeatEntriesMatchChineseFoodTable() throws {
        let db = try FoodDatabase.loadFromBundle()
        let expected: [(name: String, kcal: Double, protein: Double, fat: Double, carb: Double)] = [
            ("鸡胸肉", 133, 19.4, 5.0, 2.5),
            ("鸡腿肉", 181, 16.0, 13.0, 0.0),
            ("鸡翅", 194, 17.4, 11.8, 4.6),
            ("牛里脊", 107, 22.2, 0.9, 2.4),
            ("牛腩", 332, 17.1, 29.3, 0.0),
            ("肥牛卷", 250, 19.1, 18.7, 0.0),
            ("猪里脊", 155, 20.2, 7.9, 0.7),
            ("猪五花肉", 568, 7.7, 59.0, 0.9),
            ("猪排骨", 278, 16.7, 23.1, 0.7),
            ("全麦面包", 246, 8.6, 2.6, 46.3),
        ]
        for entry in expected {
            guard let record = db.match(exact: entry.name) else {
                XCTFail("缺少条目 \(entry.name)")
                continue
            }
            XCTAssertEqual(record.nutritionPer100g.kcal, entry.kcal, accuracy: 0.001, "\(entry.name) kcal")
            XCTAssertEqual(record.nutritionPer100g.protein, entry.protein, accuracy: 0.001, "\(entry.name) protein")
            XCTAssertEqual(record.nutritionPer100g.fat, entry.fat, accuracy: 0.001, "\(entry.name) fat")
            XCTAssertEqual(record.nutritionPer100g.carb, entry.carb, accuracy: 0.001, "\(entry.name) carb")
        }
    }

    func testAliasOwnershipAfterRefinement() throws {
        let db = try FoodDatabase.loadFromBundle()
        XCTAssertEqual(db.match(exact: "鸡胸")?.name, "鸡胸肉")
        XCTAssertEqual(db.match(exact: "排骨")?.name, "猪排骨")
        XCTAssertEqual(db.match(exact: "五花肉")?.name, "猪五花肉")
        XCTAssertEqual(db.match(exact: "全麦吐司")?.name, "全麦面包")
        XCTAssertEqual(db.match(exact: "鸡肉")?.name, "鸡肉")  // 通用条目保留
        XCTAssertNil(db.match(exact: "里脊"))                  // 裸里脊有歧义，不进别名
    }

    func testFoodCountAfterRefinement() throws {
        let db = try FoodDatabase.loadFromBundle()
        XCTAssertEqual(db.foods.count, 232)
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
