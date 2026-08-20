import Foundation

enum Sex: String, Codable, Sendable {
    case male, female
}

struct ProfileInput: Equatable, Sendable {
    let sex: Sex
    let ageYears: Int
    let heightCm: Double
    let weightKg: Double
    let activityFactor: Double
}

struct DailyTargets: Codable, Equatable, Sendable {
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carb: Double = 0
}

/// 体重采样点：本地记录与 HealthKit 统一使用
struct WeightSample: Equatable, Sendable {
    let date: Date
    let weightKg: Double
}

enum NutritionCalculator {
    static let defaultDeficitKcal = 500.0
    static let proteinGramsPerKg = 1.8

    /// Mifflin-St Jeor（spec 5.1）
    static func bmr(_ p: ProfileInput) -> Double {
        let base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.ageYears)
        return p.sex == .male ? base + 5 : base - 161
    }

    static func tdee(_ p: ProfileInput) -> Double {
        bmr(p) * p.activityFactor
    }

    /// 每日目标：热量 = max(BMR, TDEE - 500)；蛋白 1.8g/kg；脂肪 max(0.8g/kg, TDEE×25%÷9)；碳水补足剩余热量
    static func defaultTargets(for p: ProfileInput) -> DailyTargets {
        let b = bmr(p)
        let t = tdee(p)
        let kcal = max(b, t - defaultDeficitKcal)
        let protein = proteinGramsPerKg * p.weightKg
        let fat = max(0.8 * p.weightKg, t * 0.25 / 9)
        let carb = max(0, (kcal - protein * 4 - fat * 9) / 4)
        return DailyTargets(kcal: kcal, protein: protein, fat: fat, carb: carb)
    }

    /// 饮水目标：体重 × 30 ml（spec 5.1）
    static func defaultWaterTargetMl(weightKg: Double) -> Double {
        weightKg * 30
    }
}
