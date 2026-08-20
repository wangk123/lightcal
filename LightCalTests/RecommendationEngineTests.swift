import XCTest
@testable import LightCal

final class RecommendationEngineTests: XCTestCase {
    private let candidates = [
        FoodRecord(name: "鸡胸肉", aliases: [], nutritionPer100g: NutritionFacts(kcal: 133, protein: 24.6, fat: 3.3, carb: 0.6), defaultServingGrams: 100),
        FoodRecord(name: "鸡蛋", aliases: [], nutritionPer100g: NutritionFacts(kcal: 144, protein: 13.3, fat: 8.8, carb: 2.8), defaultServingGrams: 50),
        FoodRecord(name: "三文鱼", aliases: [], nutritionPer100g: NutritionFacts(kcal: 208, protein: 20.4, fat: 13.4, carb: 0), defaultServingGrams: 100),
        FoodRecord(name: "米饭", aliases: [], nutritionPer100g: NutritionFacts(kcal: 116, protein: 2.6, fat: 0.3, carb: 25.9), defaultServingGrams: 200),
        FoodRecord(name: "花生", aliases: [], nutritionPer100g: NutritionFacts(kcal: 567, protein: 25.8, fat: 49.2, carb: 16.1), defaultServingGrams: 30)
    ]

    func testProteinGapRanksByProteinDensity() {
        let gap = GapAnalysis(remainingKcal: 400, proteinGap: 28, carbGap: 0, fatGap: 0)
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: [])
        // 蛋白密度: 鸡胸肉 24.6/1.33=18.5 > 鸡蛋 13.3/1.44=9.2
        XCTAssertEqual(suggestions.first?.name, "鸡胸肉")
        XCTAssertLessThanOrEqual(suggestions.count, RecommendationEngine.maxSuggestions)
    }

    func testSuggestionCaloriesWithinRemainingBudget() {
        let gap = GapAnalysis(remainingKcal: 200, proteinGap: 100, carbGap: 0, fatGap: 0)
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: [])
        for s in suggestions {
            XCTAssertLessThanOrEqual(s.nutrition.kcal, 200 + 0.001)
        }
    }

    func testEatenTodayExcluded() {
        let gap = GapAnalysis(remainingKcal: 400, proteinGap: 28, carbGap: 0, fatGap: 0)
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: ["鸡胸肉"])
        XCTAssertFalse(suggestions.contains { $0.name == "鸡胸肉" })
    }

    func testLowFatProteinNeedExcludesFattyFoods() {
        let gap = GapAnalysis(remainingKcal: 400, proteinGap: 28, carbGap: 20, fatGap: 10)
        // carb 与 fat 都有缺口 → lowFatProtein
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: [])
        XCTAssertFalse(suggestions.contains { $0.name == "三文鱼" })  // 脂肪 13.4 > 5
        XCTAssertFalse(suggestions.contains { $0.name == "花生" })
    }

    func testHighProteinDensityWhenKcalNearlyUsed() {
        let gap = GapAnalysis(remainingKcal: 150, proteinGap: 28, carbGap: 30, fatGap: 10)
        XCTAssertEqual(gap.primaryNeed, .highProteinDensity)
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: [])
        // 150 kcal 内蛋白质最多的应是鸡胸肉（133kcal/100g → 24.6g）
        XCTAssertEqual(suggestions.first?.name, "鸡胸肉")
    }

    func testCarbGapSelectsCarbs() {
        let gap = GapAnalysis(remainingKcal: 300, proteinGap: 0, carbGap: 60, fatGap: 0)
        let suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: [])
        XCTAssertEqual(suggestions.first?.name, "米饭")
    }

    func testGapAnalysisPrimaryNeedCases() {
        XCTAssertEqual(GapAnalysis(remainingKcal: 300, proteinGap: 10, carbGap: 0, fatGap: 0).primaryNeed, .protein)
        XCTAssertEqual(GapAnalysis(remainingKcal: 300, proteinGap: 10, carbGap: 0, fatGap: 5).primaryNeed, .lowFatProtein)
        XCTAssertEqual(GapAnalysis(remainingKcal: 100, proteinGap: 10, carbGap: 20, fatGap: 0).primaryNeed, .highProteinDensity)
        XCTAssertEqual(GapAnalysis(remainingKcal: 300, proteinGap: 0, carbGap: 20, fatGap: 0).primaryNeed, .carb)
        XCTAssertEqual(GapAnalysis(remainingKcal: 0, proteinGap: 0, carbGap: 0, fatGap: 0).primaryNeed, .protein)
    }
}
