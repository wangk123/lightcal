import Foundation

/// 营养快照：核心字段 + 可扩展字典（spec 3.7，微营养素将来加 extras 即可，无迁移）
struct NutritionFacts: Codable, Equatable, Sendable {
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carb: Double = 0
    var extras: [String: Double] = [:]

    init(kcal: Double = 0, protein: Double = 0, fat: Double = 0, carb: Double = 0, extras: [String: Double] = [:]) {
        self.kcal = kcal
        self.protein = protein
        self.fat = fat
        self.carb = carb
        self.extras = extras
    }

    /// 自定义解码：JSON 允许省略 extras（内置食物库只存核心四项，spec 3.7）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kcal = try container.decodeIfPresent(Double.self, forKey: .kcal) ?? 0
        protein = try container.decodeIfPresent(Double.self, forKey: .protein) ?? 0
        fat = try container.decodeIfPresent(Double.self, forKey: .fat) ?? 0
        carb = try container.decodeIfPresent(Double.self, forKey: .carb) ?? 0
        extras = try container.decodeIfPresent([String: Double].self, forKey: .extras) ?? [:]
    }

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
