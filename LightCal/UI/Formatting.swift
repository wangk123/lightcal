import Foundation

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
}
