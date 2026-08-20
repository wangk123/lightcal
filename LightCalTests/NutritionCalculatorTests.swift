import XCTest
@testable import LightCal

final class NutritionCalculatorTests: XCTestCase {
    private let male = ProfileInput(sex: .male, ageYears: 30, heightCm: 175, weightKg: 70, activityFactor: 1.375)

    func testBMRMale() {
        // Mifflin-St Jeor: 10*70 + 6.25*175 - 5*30 + 5 = 1648.75
        XCTAssertEqual(NutritionCalculator.bmr(male), 1648.75, accuracy: 0.001)
    }

    func testBMRFemale() {
        let female = ProfileInput(sex: .female, ageYears: 30, heightCm: 165, weightKg: 60, activityFactor: 1.375)
        // 10*60 + 6.25*165 - 5*30 - 161 = 1320.25
        XCTAssertEqual(NutritionCalculator.bmr(female), 1320.25, accuracy: 0.001)
    }

    func testTDEEAppliesActivityFactor() {
        XCTAssertEqual(NutritionCalculator.tdee(male), 1648.75 * 1.375, accuracy: 0.001)
    }

    func testDefaultTargetsStandardCase() {
        let targets = NutritionCalculator.defaultTargets(for: male)
        XCTAssertEqual(targets.kcal, 1648.75 * 1.375 - 500, accuracy: 0.001)
        XCTAssertEqual(targets.protein, 1.8 * 70, accuracy: 0.001)
        XCTAssertGreaterThan(targets.fat, 0)
        XCTAssertGreaterThan(targets.carb, 0)
        // 三大营养素热量之和 ≈ 总热量
        let sumKcal = targets.protein * 4 + targets.fat * 9 + targets.carb * 4
        XCTAssertEqual(sumKcal, targets.kcal, accuracy: 0.001)
    }

    func testKcalFloorAtBMR() {
        // 高体重低活动：TDEE-500 可能低于 BMR → 下限保护（spec 5.1）
        let heavy = ProfileInput(sex: .male, ageYears: 50, heightCm: 170, weightKg: 60, activityFactor: 1.2)
        let targets = NutritionCalculator.defaultTargets(for: heavy)
        XCTAssertEqual(targets.kcal, NutritionCalculator.bmr(heavy), accuracy: 0.001)
    }

    func testWaterTarget() {
        XCTAssertEqual(NutritionCalculator.defaultWaterTargetMl(weightKg: 70), 2100)
    }

    func testDailyTargetsCodable() throws {
        let t = DailyTargets(kcal: 1800, protein: 126, fat: 56, carb: 200)
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(DailyTargets.self, from: data), t)
    }
}
