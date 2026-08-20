import Foundation

/// 离线兜底解析器（spec 4.2）：DeepSeek 不可用时解析常见中文句式
struct LocalRegexParser: FoodTextParsing {

    static let chineseNumbers: [String: Double] = [
        "两": 2, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
        "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
    ]

    private static let mealKeywords: [(MealKind, [String])] = [
        (.breakfast, ["早饭", "早餐"]),
        (.lunch, ["午饭", "午餐", "中餐"]),
        (.dinner, ["晚饭", "晚餐"]),
        (.snack, ["夜宵", "加餐", "宵夜"])
    ]

    static func detectMeal(in text: String) -> MealKind? {
        for (meal, words) in mealKeywords where words.contains(where: { text.contains($0) }) {
            return meal
        }
        return nil
    }

    static func parseCount(_ raw: String) -> Double? {
        if let n = Double(raw) { return n }
        guard raw.count == 1, let v = chineseNumbers[raw] else { return nil }
        return v
    }

    func parse(_ text: String) async throws -> [ParsedFoodItem] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let meal = Self.detectMeal(in: trimmed)

        // 模式1: "100g鸡胸肉" / "100克鸡胸肉"（名称非贪婪 + 分隔符/结尾前瞻，防止吞掉后续条目）
        let gramsPattern = #/(\d+(?:\.\d+)?)\s*(?:g|克)\s*([\p{Han}A-Za-z]+?)(?=$|[\s，,、。;；和与])/#
        var consumed: [Range<String.Index>] = []
        var items: [ParsedFoodItem] = []
        for match in trimmed.matches(of: gramsPattern) {
            if let grams = Double(match.1) {
                consumed.append(match.range)
                items.append(ParsedFoodItem(name: String(match.2), grams: grams, count: nil, unit: nil, meal: meal))
            }
        }

        // 模式2: "两个鸡蛋" / "2个鸡蛋" / "一碗米饭"
        let countPattern = #/([两一二三四五六七八九十\d]+(?:\.\d+)?)\s*(个|只|碗|杯|瓶|盒|袋)\s*([\p{Han}A-Za-z]+?)(?=$|[\s，,、。;；和与])/#
        for match in trimmed.matches(of: countPattern) {
            guard !consumed.contains(where: { $0.overlaps(match.range) }),
                  let count = Self.parseCount(String(match.1)) else { continue }
            consumed.append(match.range)
            items.append(ParsedFoodItem(name: String(match.3), grams: nil, count: count, unit: String(match.2), meal: meal))
        }

        // 模式3: 剩余文本按分隔符切成纯名称条目（无任何结构化信息时的兜底）
        // 注意：不同 String 实例的 Range 不通用，按匹配间隙重建 remainder
        var remainderParts: [Substring] = []
        var cursor = trimmed.startIndex
        for range in consumed.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            remainderParts.append(trimmed[cursor..<range.lowerBound])
            cursor = range.upperBound
        }
        remainderParts.append(trimmed[cursor...])
        let remainder = remainderParts.joined()
        let separators = CharacterSet(charactersIn: "，,、。;；和 　")
        let parts = remainder.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for part in parts where !part.isEmpty {
            items.append(ParsedFoodItem(name: part, grams: nil, count: nil, unit: nil, meal: meal))
        }
        return items
    }
}
