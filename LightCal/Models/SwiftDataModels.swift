import Foundation
import SwiftData

@Model
final class UserProfile {
    var sex: String
    var birthDate: Date
    var heightCm: Double
    var initialWeightKg: Double
    var activityFactor: Double

    init(sex: String, birthDate: Date, heightCm: Double, initialWeightKg: Double, activityFactor: Double) {
        self.sex = sex
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.initialWeightKg = initialWeightKg
        self.activityFactor = activityFactor
    }
}

@Model
final class Goal {
    var targetWeightKg: Double
    var startDate: Date
    var startWeightKg: Double
    var targets: DailyTargets          // 当前生效目标（可微调）
    var systemTargets: DailyTargets    // 系统计算默认值（spec 3.2 分开存）
    var waterTargetMl: Double
    var createdAt: Date

    init(targetWeightKg: Double, startDate: Date, startWeightKg: Double,
         targets: DailyTargets, systemTargets: DailyTargets, waterTargetMl: Double) {
        self.targetWeightKg = targetWeightKg
        self.startDate = startDate
        self.startWeightKg = startWeightKg
        self.targets = targets
        self.systemTargets = systemTargets
        self.waterTargetMl = waterTargetMl
        self.createdAt = .now
    }
}

@Model
final class CustomFood {
    var name: String
    var nutritionPer100g: NutritionFacts
    var createdAt: Date

    init(name: String, nutritionPer100g: NutritionFacts) {
        self.name = name
        self.nutritionPer100g = nutritionPer100g
        self.createdAt = .now
    }
}

@Model
final class FoodLogItem {
    var date: Date               // 当日 0 点（startOfDay）
    var meal: String             // MealKind.rawValue
    var name: String
    var grams: Double
    var nutrition: NutritionFacts  // 快照冗余（spec 3.4）
    var source: String           // NutritionSource.rawValue
    var createdAt: Date

    init(date: Date, meal: String, name: String, grams: Double, nutrition: NutritionFacts, source: String) {
        self.date = date
        self.meal = meal
        self.name = name
        self.grams = grams
        self.nutrition = nutrition
        self.source = source
        self.createdAt = .now
    }
}

@Model
final class WaterLogItem {
    var date: Date
    var amountMl: Double
    var createdAt: Date

    init(date: Date, amountMl: Double) {
        self.date = date
        self.amountMl = amountMl
        self.createdAt = .now
    }
}

@Model
final class WeightRecord {
    var date: Date
    var weightKg: Double
    var createdAt: Date

    init(date: Date, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
        self.createdAt = .now
    }
}
