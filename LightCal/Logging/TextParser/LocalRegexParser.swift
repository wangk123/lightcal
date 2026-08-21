import Foundation

/// 离线兜底解析器（spec 4.2）：DeepSeek 不可用时解析常见中文句式
struct LocalRegexParser: FoodTextParsing {

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
        return parseChineseNumber(raw)
    }

    /// 多字中文数字（语音输入常见）：五百→500、一百五十→150、二十→20；百/千/万 开头视为非法
    static func parseChineseNumber(_ raw: String) -> Double? {
        let digits: [Character: Double] = [
            "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        let units: [Character: Double] = ["十": 10, "百": 100, "千": 1000, "万": 10000]
        guard !raw.isEmpty else { return nil }
        if let first = raw.first, units[first] != nil, first != "十" { return nil }
        var total = 0.0
        var section = 0.0
        var current = 0.0
        for ch in raw {
            if let digit = digits[ch] {
                current = digit
            } else if let unit = units[ch] {
                if unit == 10000 {
                    section = (section + current) * unit
                    total += section
                    section = 0
                    current = 0
                } else {
                    section += (current == 0 ? 1 : current) * unit
                    current = 0
                }
            } else {
                return nil
            }
        }
        return total + section + current
    }

    /// 数量+单位 → 结构化份量（升/公斤 ×1000 换算）
    private enum ParsedAmount {
        case grams(Double)
        case ml(Double)
        case count(Double, String)
    }

    private static func amount(_ rawNum: String, unit: String) -> ParsedAmount? {
        guard let number = parseCount(rawNum) else { return nil }
        switch unit {
        case "g", "克": return .grams(number)
        case "kg", "公斤": return .grams(number * 1000)
        case "ml", "毫升": return .ml(number)
        case "l", "L", "升": return .ml(number * 1000)
        default: return .count(number, unit)
        }
    }

    private static func item(name: String, amount: ParsedAmount, meal: MealKind?) -> ParsedFoodItem {
        switch amount {
        case .grams(let grams):
            return ParsedFoodItem(name: name, grams: grams, count: nil, unit: nil, meal: meal)
        case .ml(let ml):
            return ParsedFoodItem(name: name, grams: nil, count: nil, unit: nil, meal: meal, ml: ml)
        case .count(let count, let unit):
            return ParsedFoodItem(name: name, grams: nil, count: count, unit: unit, meal: meal)
        }
    }

    func parse(_ text: String) async throws -> [ParsedFoodItem] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let meal = Self.detectMeal(in: trimmed)

        // 模式1: 数量在前 "500ml牛奶" / "100g鸡胸肉" / "两个鸡蛋"
        let amountFirstPattern = #/((?:[零一二三四五六七八九十百千万两]+|\d+(?:\.\d+)?))\s*(g|克|kg|公斤|ml|毫升|l|L|升|个|只|碗|杯|瓶|盒|袋)\s*([\p{Han}A-Za-z]+?)(?=$|[\s，,、。;；和与])/#

        // 模式2: 名称在前 "美式咖啡500ml" / "鸡胸肉100g"（前缀锚定，防止名称跨分隔符吞字）
        let nameFirstPattern = #/(^|[\s，,、。;；和与])([\p{Han}A-Za-z]+?)\s*((?:[零一二三四五六七八九十百千万两]+|\d+(?:\.\d+)?))\s*(g|克|kg|公斤|ml|毫升|l|L|升|个|只|碗|杯|瓶|盒|袋)(?=$|[\s，,、。;；和与])/#

        var consumed: [Range<String.Index>] = []
        var items: [ParsedFoodItem] = []

        for match in trimmed.matches(of: amountFirstPattern) {
            let range = match.range
            guard !consumed.contains(where: { $0.overlaps(range) }),
                  let amount = Self.amount(String(match.1), unit: String(match.2)) else { continue }
            consumed.append(range)
            items.append(Self.item(name: String(match.3), amount: amount, meal: meal))
        }

        for match in trimmed.matches(of: nameFirstPattern) {
            // 名称从匹配范围内剔除前缀分隔符开始，避免把分隔符一起吞进 consumed
            let nameStart = trimmed.index(match.range.lowerBound, offsetBy: match.1.count)
            let range = nameStart..<match.range.upperBound
            guard !consumed.contains(where: { $0.overlaps(range) }),
                  let amount = Self.amount(String(match.3), unit: String(match.4)) else { continue }
            consumed.append(range)
            items.append(Self.item(name: String(match.2), amount: amount, meal: meal))
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
        let separators = CharacterSet(charactersIn: "，,、。;；和与 　")
        // 纯"数字+单位"（500ml/100g/五百毫升）不是食物，绝不生成条目
        let bareAmountPattern = #/^(?:[零一二三四五六七八九十百千万两]+|\d+(?:\.\d+)?)\s*(?:g|克|kg|公斤|ml|毫升|l|L|升|个|只|碗|杯|瓶|盒|袋)$/#
        let parts = remainder.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for part in parts where !part.isEmpty {
            if part.wholeMatch(of: bareAmountPattern) != nil { continue }
            items.append(ParsedFoodItem(name: part, grams: nil, count: nil, unit: nil, meal: meal))
        }
        return items
    }
}
