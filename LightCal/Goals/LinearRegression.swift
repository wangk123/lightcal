import Foundation

/// 最小二乘线性拟合（spec 5.3 体重回归与趋势线共用）
enum LinearRegression {
    static func fit(points: [(x: Double, y: Double)]) -> (slope: Double, intercept: Double)? {
        let n = Double(points.count)
        guard points.count >= 2 else { return nil }
        let meanX = points.reduce(0) { $0 + $1.x } / n
        let meanY = points.reduce(0) { $0 + $1.y } / n
        let numerator = points.reduce(0.0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let denominator = points.reduce(0.0) { $0 + ($1.x - meanX) * ($1.x - meanX) }
        guard denominator > 0 else { return nil }
        let slope = numerator / denominator
        return (slope: slope, intercept: meanY - slope * meanX)
    }
}
