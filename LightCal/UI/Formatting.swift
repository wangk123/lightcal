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

    static func weightText(kg: Double, unit: WeightUnit) -> String {
        switch unit {
        case .kg: "\(String(format: "%.1f", kg)) kg"
        case .jin: "\(String(format: "%.1f", kg * 2)) 斤"
        }
    }
}
