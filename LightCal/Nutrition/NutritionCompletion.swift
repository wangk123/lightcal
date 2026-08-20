import Foundation

enum NutritionSource: String, Codable, Sendable {
    case builtin
    case custom
    case aiEstimated
}

/// 补全后的食物条目：确认卡片与落库使用的结构（spec 4.3）
struct CompletedFoodItem: Equatable, Sendable {
    var name: String
    var grams: Double
    var nutrition: NutritionFacts
    var source: NutritionSource
}

protocol NutritionCompleting: Sendable {
    func complete(_ items: [ParsedFoodItem]) async -> [CompletedFoodItem]
}

/// 单位默认克重（食物无自带份量时的兜底）
enum PortionDefaults {
    static let unitGrams: [String: Double] = [
        "个": 60, "只": 60, "碗": 200, "杯": 250, "瓶": 500, "盒": 250, "袋": 100
    ]
    static let fallbackGrams: Double = 100
}

/// 三层兜底：内置库 → 自定义食物 → AI 估算（spec 4.3）
final class NutritionCompletion: NutritionCompleting {
    private let database: FoodDatabase
    private let customFoodLookup: @Sendable (String) -> FoodRecord?
    private let estimator: @Sendable (String) async throws -> NutritionFacts  // 返回每 100g 营养

    init(
        database: FoodDatabase,
        customFoodLookup: @escaping @Sendable (String) -> FoodRecord?,
        estimator: @escaping @Sendable (String) async throws -> NutritionFacts
    ) {
        self.database = database
        self.customFoodLookup = customFoodLookup
        self.estimator = estimator
    }

    func complete(_ items: [ParsedFoodItem]) async -> [CompletedFoodItem] {
        var result: [CompletedFoodItem] = []
        for item in items {
            if let record = database.match(exact: item.name) {
                result.append(make(item: item, record: record, source: .builtin))
            } else if let record = customFoodLookup(item.name) {
                result.append(make(item: item, record: record, source: .custom))
            } else {
                let grams = Self.grams(for: item, record: nil)
                let nutrition: NutritionFacts
                if let per100 = try? await estimator(item.name) {
                    nutrition = .scaled(per100, grams: grams)
                } else {
                    nutrition = NutritionFacts()  // 估算失败：零营养占位，UI 必须让用户补全
                }
                result.append(CompletedFoodItem(name: item.name, grams: grams, nutrition: nutrition, source: .aiEstimated))
            }
        }
        return result
    }

    private func make(item: ParsedFoodItem, record: FoodRecord, source: NutritionSource) -> CompletedFoodItem {
        let grams = Self.grams(for: item, record: record)
        return CompletedFoodItem(
            name: item.name,
            grams: grams,
            nutrition: .scaled(record.nutritionPer100g, grams: grams),
            source: source
        )
    }

    /// 份量换算优先级：显式克重 → 数量×每份克重 → 单位默认 → 食物默认份量 → 100g 兜底
    static func grams(for item: ParsedFoodItem, record: FoodRecord?) -> Double {
        if let grams = item.grams { return grams }
        if let count = item.count, let unit = item.unit {
            let perUnit = record?.defaultServingGrams ?? PortionDefaults.unitGrams[unit] ?? PortionDefaults.fallbackGrams
            return count * perUnit
        }
        if let unit = item.unit {
            return PortionDefaults.unitGrams[unit] ?? PortionDefaults.fallbackGrams
        }
        return record?.defaultServingGrams ?? PortionDefaults.fallbackGrams
    }
}
