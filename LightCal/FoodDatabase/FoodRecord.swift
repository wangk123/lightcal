import Foundation

/// 食物模板条目：内置库与自定义食物共用（spec 3.3）
struct FoodRecord: Codable, Equatable, Sendable {
    let name: String
    let aliases: [String]
    let nutritionPer100g: NutritionFacts
    var defaultServingGrams: Double?
    /// 饮品标记（foods.json 里 "isLiquid": true）：份量自适应按 ml 显示，如咖啡/牛奶/水
    var isLiquid: Bool? = nil

    var isDrink: Bool { isLiquid == true }
}

struct FoodDatabaseFile: Codable {
    let version: Int
    let foods: [FoodRecord]
}
