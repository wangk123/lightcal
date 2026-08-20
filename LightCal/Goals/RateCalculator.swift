import Foundation

enum RateCalculator {
    static let kcalPerKgFat = 7700.0

    /// 体重趋势速率（kg/周）：最近 14 天、≥3 点线性回归（spec 5.3）
    static func weightTrendRateKgsPerWeek(samples: [WeightSample], now: Date = .now, calendar: Calendar = .current) -> Double? {
        guard let cutoff = calendar.date(byAdding: .day, value: -14, to: now) else { return nil }
        let recent = samples.filter { $0.date >= cutoff }
        guard recent.count >= 3 else { return nil }
        let sorted = recent.sorted { $0.date < $1.date }
        guard let first = sorted.first?.date else { return nil }
        let points = sorted.map { (x: $0.date.timeIntervalSince(first) / 86400, y: $0.weightKg) }
        guard let fit = LinearRegression.fit(points: points) else { return nil }
        return fit.slope * 7  // kg/天 → kg/周
    }

    /// 能量趋势速率（kg/周）：近 7 天平均缺口 ÷ 7700 × 7（spec 5.3）
    static func energyTrendRateKgsPerWeek(dailyDeficits: [Double]) -> Double? {
        guard !dailyDeficits.isEmpty else { return nil }
        let avg = dailyDeficits.reduce(0, +) / Double(dailyDeficits.count)
        return avg / kcalPerKgFat * 7
    }
}
