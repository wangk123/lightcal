import Foundation

enum WeightUnit: String, CaseIterable {
    case kg, jin
}

enum Formatting {
    static func kcalText(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    static func gramsText(_ value: Double) -> String {
        "\(Int(value.rounded()))g"
    }

    static func daysText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded())) 天"
    }

    static func mlText(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    /// 24 小时制 HH:mm（dateFormat 模式与用户时区结合，输出确定性）
    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func weightText(kg: Double, unit: WeightUnit) -> String {
        switch unit {
        case .kg: "\(String(format: "%.1f", kg)) kg"
        case .jin: "\(String(format: "%.1f", kg * 2)) 斤"
        }
    }
}
