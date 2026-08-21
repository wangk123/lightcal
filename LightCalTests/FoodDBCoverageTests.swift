import XCTest
@testable import LightCal

/// 回归网：内置营养库必须覆盖 Vision 识别器支持的全部食物类别（防止两表脱节）
final class FoodDBCoverageTests: XCTestCase {
    func testEveryVisionFoodLabelHasNutrition() throws {
        let db = try FoodDatabase.loadFromBundle()  // 单测宿主为 App bundle，含 foods.json

        var missing: [String] = []
        var zeroKcal: [String] = []
        for chineseName in VisionFoodRecognizer.labelMap.values {
            if let record = db.match(exact: chineseName) {
                if record.nutritionPer100g.kcal <= 0 && chineseName != "水" && chineseName != "茶" {
                    zeroKcal.append(chineseName)
                }
            } else {
                missing.append(chineseName)
            }
        }
        XCTAssertTrue(missing.isEmpty, "以下识别食物类别缺少营养数据：\(missing)")
        XCTAssertTrue(zeroKcal.isEmpty, "以下食物营养热量为 0（水/茶除外）：\(zeroKcal)")
    }

    func testDatabaseHasOver200Foods() throws {
        let db = try FoodDatabase.loadFromBundle()
        XCTAssertGreaterThanOrEqual(db.foods.count, 200)
    }
}
