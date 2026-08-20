import Foundation

/// 当日实时缺口（spec 6.1）
struct GapAnalysis: Equatable {
    var remainingKcal: Double
    var proteinGap: Double
    var carbGap: Double
    var fatGap: Double

    enum PrimaryNeed: Equatable {
        case protein             // 蛋白不足且热量充足
        case carb                // 碳水不足
        case lowFatProtein       // 蛋白+碳水不足且脂肪已超 → 低脂高蛋白
        case highProteinDensity  // 热量额度紧张但蛋白不足 → 蛋白质密度优先
    }

    var primaryNeed: PrimaryNeed {
        // 判定顺序（spec 6.1）：热量额度紧张（<200 kcal）且蛋白不足 → 蛋白密度优先；
        // 否则蛋白不足时看脂肪是否已超 → 低脂高蛋白 / 普通蛋白补充；最后看碳水
        if proteinGap > 0 {
            if remainingKcal < RecommendationEngine.nearLimitKcal { return .highProteinDensity }
            return fatGap > 0 ? .lowFatProtein : .protein
        }
        if carbGap > 0 { return .carb }
        return .protein
    }
}

struct FoodSuggestion: Equatable {
    let name: String
    let grams: Double
    let nutrition: NutritionFacts
    let reason: String
}

enum RecommendationEngine {
    static let maxSuggestions = 3
    static let maxSuggestionGrams = 500.0
    static let gramStep = 10.0
    static let lowFatThresholdPer100g = 5.0   // 每100g脂肪 > 5g 不算低脂（鸡胸肉 3.3、瘦牛肉 2.3 通过；三文鱼 13.4、花生 49.2 排除）
    static let nearLimitKcal = 200.0          // 剩余热量 < 200 kcal 视为额度紧张

    /// 建议清单（spec 6.2/6.3）：候选池 = 内置库 + 自定义食物（AI 估算不进池）
    static func suggestions(gap: GapAnalysis, candidates: [FoodRecord], eatenToday: Set<String>) -> [FoodSuggestion] {
        let need = gap.primaryNeed
        let isCarbNeed = (need == .carb)

        var scored: [(record: FoodRecord, score: Double, grams: Double)] = []
        for record in candidates {
            // 排除当日已吃的
            guard !eatenToday.contains(record.name),
                  record.aliases.allSatisfy({ !eatenToday.contains($0) }) else { continue }

            let per100 = record.nutritionPer100g
            let nutrientPer100 = isCarbNeed ? per100.carb : per100.protein
            guard nutrientPer100 > 0 else { continue }

            // 场景过滤：低脂场景排除高脂食物
            if need == .lowFatProtein && per100.fat > lowFatThresholdPer100g { continue }

            // 打分：营养素密度（每 kcal 克数 × 100）
            let score = nutrientPer100 / max(per100.kcal, 1) * 100

            // 满足缺口所需克重；再受剩余热量额度约束取较小值（spec 6.3），
            // 向下取整到 10g（热量预算因此天然不超）
            let gapToMeet = isCarbNeed ? gap.carbGap : gap.proteinGap
            let neededGrams = gapToMeet / nutrientPer100 * 100
            guard neededGrams > 0 else { continue }
            let kcalPerGram = per100.kcal / 100
            let maxGramsByKcal = kcalPerGram > 0 ? gap.remainingKcal / kcalPerGram : maxSuggestionGrams
            let grams = min(min(neededGrams, maxGramsByKcal), maxSuggestionGrams)
            let rounded = max(floor(grams / gramStep) * gramStep, gramStep)
            scored.append((record, score, rounded))
        }
        scored.sort { $0.score > $1.score }
        let top = scored.count > Self.maxSuggestions ? Array(scored[0..<Self.maxSuggestions]) : scored

        return top.map { entry in
            FoodSuggestion(
                name: entry.record.name,
                grams: entry.grams,
                nutrition: .scaled(entry.record.nutritionPer100g, grams: entry.grams),
                reason: isCarbNeed ? "补充碳水缺口" : "补充蛋白质缺口"
            )
        }
    }
}
