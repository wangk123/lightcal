import Foundation

/// 食物模板条目：内置库与自定义食物共用（spec 3.3）
struct FoodRecord: Codable, Equatable, Sendable {
    let name: String
    let aliases: [String]
    let nutritionPer100g: NutritionFacts
    var defaultServingGrams: Double?
}

struct FoodDatabaseFile: Codable {
    let version: Int
    let foods: [FoodRecord]
}
