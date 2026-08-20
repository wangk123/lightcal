import XCTest
@testable import LightCal

final class PredictionTests: XCTestCase {
    private let calendar = Calendar.current

    private func sample(_ daysAgo: Int, _ kg: Double) -> WeightSample {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
        return WeightSample(date: date, weightKg: kg)
    }

    func testLinearRegressionKnownSlope() {
        let fit = LinearRegression.fit(points: [(0, 70), (10, 69), (20, 68)])
        XCTAssertNotNil(fit)
        XCTAssertEqual(fit!.slope, -0.1, accuracy: 0.0001)
        XCTAssertEqual(fit!.intercept, 70, accuracy: 0.0001)
    }

    func testLinearRegressionTwoPoints() {
        let fit = LinearRegression.fit(points: [(0, 1), (1, 3)])
        XCTAssertEqual(fit?.slope ?? 0, 2, accuracy: 0.0001)
    }

    func testLinearRegressionDegenerateReturnsNil() {
        XCTAssertNil(LinearRegression.fit(points: [(0, 5)]))
    }

    func testWeightTrendRateNeedsThreePoints() {
        XCTAssertNil(RateCalculator.weightTrendRateKgsPerWeek(samples: [sample(0, 70), sample(1, 69.9)], now: .now, calendar: calendar))
    }

    func testWeightTrendRateSlopePerWeek() {
        // 0.1 kg/天下降 = -0.7 kg/周（3 个点都在 14 天窗口内）
        let samples = [sample(0, 70), sample(5, 70.5), sample(10, 71)]
        let rate = RateCalculator.weightTrendRateKgsPerWeek(samples: samples, now: .now, calendar: calendar)
        XCTAssertEqual(rate ?? 0, -0.7, accuracy: 0.001)
    }

    func testWeightTrendWindowIs14Days() {
        // 30 天前的老数据不参与；若参与，回归会因 100kg 严重偏移
        let old = calendar.date(byAdding: .day, value: -30, to: .now)!
        let samples = [sample(0, 70), sample(5, 70.5), sample(10, 71), WeightSample(date: old, weightKg: 100)]
        let rate = RateCalculator.weightTrendRateKgsPerWeek(samples: samples, now: .now, calendar: calendar)
        XCTAssertEqual(rate ?? 0, -0.7, accuracy: 0.001)
    }

    func testEnergyTrendRate() {
        // 日均缺口 770 kcal → 0.7 kg/周
        let rate = RateCalculator.energyTrendRateKgsPerWeek(dailyDeficits: [770, 770, 770])
        XCTAssertEqual(rate ?? 0, 0.7, accuracy: 0.001)
        XCTAssertNil(RateCalculator.energyTrendRateKgsPerWeek(dailyDeficits: []))
    }

    func testPredictedRateWeighting() {
        let rate = PredictionCalculator.predictedRateKgsPerWeek(weightRate: 0.5, energyRate: 1.0)
        XCTAssertEqual(rate ?? 0, 0.5 * 0.6 + 1.0 * 0.4, accuracy: 0.001)
        XCTAssertEqual(PredictionCalculator.predictedRateKgsPerWeek(weightRate: 0.5, energyRate: nil), 0.5)
        XCTAssertEqual(PredictionCalculator.predictedRateKgsPerWeek(weightRate: nil, energyRate: 0.4), 0.4)
        XCTAssertNil(PredictionCalculator.predictedRateKgsPerWeek(weightRate: nil, energyRate: nil))
    }

    func testDaysToReach() {
        XCTAssertEqual(PredictionCalculator.daysToReach(currentWeightKg: 70, targetWeightKg: 66.5, rateKgsPerWeek: 0.5) ?? 0, 49, accuracy: 0.001)
        XCTAssertNil(PredictionCalculator.daysToReach(currentWeightKg: 66, targetWeightKg: 66.5, rateKgsPerWeek: 0.5))  // 已达标
        XCTAssertNil(PredictionCalculator.daysToReach(currentWeightKg: 70, targetWeightKg: 65, rateKgsPerWeek: 0))      // 速率 0
    }

    func testScenarios() {
        let s = PredictionCalculator.scenarios(
            currentWeightKg: 70, targetWeightKg: 66.5,
            weightRate: 0.5, energyRate: 1.0,
            targetKcal: 1800, avgDailyExpenditureLast7d: 2300
        )
        // 趋势: 0.5*0.6+1.0*0.4=0.7 → 3.5/0.7*7 = 35 天
        XCTAssertEqual(s.trendDays ?? 0, 35, accuracy: 0.001)
        // 保守: 35/0.7 = 50 天
        XCTAssertEqual(s.conservativeDays ?? 0, 50, accuracy: 0.001)
        // 目标缺口: 2300-1800=500 → 500/7700*7=0.4545 → 3.5/0.4545*7 ≈ 53.9 天
        XCTAssertEqual(s.targetDays ?? 0, 3.5 / (500.0 / 7700 * 7) * 7, accuracy: 0.001)
    }

    func testScenariosWithoutTargetDeficit() {
        let s = PredictionCalculator.scenarios(
            currentWeightKg: 70, targetWeightKg: 66.5,
            weightRate: 0.5, energyRate: nil,
            targetKcal: 2500, avgDailyExpenditureLast7d: 2300  // 支出 < 目标 → 无目标缺口
        )
        XCTAssertNotNil(s.trendDays)
        XCTAssertNil(s.targetDays)
    }
}
