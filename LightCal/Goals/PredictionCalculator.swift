import Foundation

struct PredictionScenarios: Equatable {
    let trendDays: Double?        // 按当前趋势
    let conservativeDays: Double? // 保守（趋势速率 × 0.7）
    let targetDays: Double?       // 按目标缺口（严格吃满目标热量）
}

enum PredictionCalculator {
    static let weightRateWeight = 0.6
    static let energyRateWeight = 0.4

    /// 综合预测速率（spec 5.4）
    static func predictedRateKgsPerWeek(weightRate: Double?, energyRate: Double?) -> Double? {
        switch (weightRate, energyRate) {
        case let (weight?, energy?): return weight * weightRateWeight + energy * energyRateWeight
        case let (weight?, nil): return weight
        case let (nil, energy?): return energy
        case (nil, nil): return nil
        }
    }

    static func daysToReach(currentWeightKg: Double, targetWeightKg: Double, rateKgsPerWeek: Double) -> Double? {
        let remaining = currentWeightKg - targetWeightKg
        guard remaining > 0, rateKgsPerWeek > 0 else { return nil }
        return remaining / rateKgsPerWeek * 7
    }

    static func scenarios(
        currentWeightKg: Double,
        targetWeightKg: Double,
        weightRate: Double?,
        energyRate: Double?,
        targetKcal: Double,
        avgDailyExpenditureLast7d: Double
    ) -> PredictionScenarios {
        let trendRate = predictedRateKgsPerWeek(weightRate: weightRate, energyRate: energyRate)
        let trendDays = trendRate.flatMap {
            daysToReach(currentWeightKg: currentWeightKg, targetWeightKg: targetWeightKg, rateKgsPerWeek: $0)
        }
        let conservativeDays = trendDays.map { $0 / 0.7 }
        let targetDeficit = avgDailyExpenditureLast7d - targetKcal
        let targetRate = targetDeficit > 0 ? targetDeficit / RateCalculator.kcalPerKgFat * 7 : nil
        let targetDays = targetRate.flatMap {
            daysToReach(currentWeightKg: currentWeightKg, targetWeightKg: targetWeightKg, rateKgsPerWeek: $0)
        }
        return PredictionScenarios(trendDays: trendDays, conservativeDays: conservativeDays, targetDays: targetDays)
    }
}
