import Foundation

enum MealKind: String, Codable, CaseIterable, Sendable {
    case breakfast = "早餐"
    case lunch = "午餐"
    case dinner = "晚餐"
    case snack = "加餐"

    /// 按当前时间推荐餐次（拍照等无餐次信息的入口自动预选）
    static func suggested(for date: Date = .now, calendar: Calendar = .current) -> MealKind {
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        switch minutes {
        case 5 * 60 ..< 10 * 60 + 30: return .breakfast
        case 10 * 60 + 30 ..< 15 * 60: return .lunch
        case 15 * 60 ..< 21 * 60: return .dinner
        default: return .snack
        }
    }
}

/// 解析中间结果：统一承接文字/语音/拍照三种入口（spec 4）
struct ParsedFoodItem: Equatable, Codable, Sendable {
    var name: String
    var grams: Double?   // 显式克重，如 "100g鸡胸肉"
    var count: Double?   // 数量，如 "两个鸡蛋"
    var unit: String?    // 单位：个/只/碗/杯/瓶/盒/袋
    var meal: MealKind?
}

/// 文本解析协议：DeepSeek 与本地正则兜底都实现它（spec 4.2）
protocol FoodTextParsing: Sendable {
    func parse(_ text: String) async throws -> [ParsedFoodItem]
}
