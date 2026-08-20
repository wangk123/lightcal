import Foundation

/// 营养快照：核心字段 + 可扩展字典（spec 3.7，微营养素将来加 extras 即可，无迁移）
struct NutritionFacts: Codable, Equatable, Sendable {
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carb: Double = 0
    var extras: [String: Double] = [:]

    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            kcal: lhs.kcal + rhs.kcal,
            protein: lhs.protein + rhs.protein,
            fat: lhs.fat + rhs.fat,
            carb: lhs.carb + rhs.carb,
            extras: lhs.extras.merging(rhs.extras) { $0 + $1 }
        )
    }

    /// 每 100g 数值 × 份量(g) 换算
    static func scaled(_ per100g: NutritionFacts, grams: Double) -> NutritionFacts {
        let factor = grams / 100.0
        return NutritionFacts(
            kcal: per100g.kcal * factor,
            protein: per100g.protein * factor,
            fat: per100g.fat * factor,
            carb: per100g.carb * factor,
            extras: per100g.extras.mapValues { $0 * factor }
        )
    }
}
