import Foundation
import Observation

struct WeightPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let kg: Double
}

struct IntakePoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let kcal: Double
}

@MainActor
@Observable
final class TrendsViewModel {
    enum Range: String, CaseIterable, Identifiable {
        case week = "周", month = "月", quarter = "3月", all = "全部"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            case .all: nil
            }
        }
    }

    var range: Range = .month
    private(set) var weightPoints: [WeightPoint] = []
    private(set) var trendPoints: [WeightPoint] = []
    private(set) var intakePoints: [IntakePoint] = []
    private(set) var targetKcal: Double = 0
    private(set) var hasEnoughWeightData = false

    private let store: DataStore

    init(store: DataStore) {
        self.store = store
    }

    func refresh() async {
        let calendar = Calendar.current
        let now = Date()
        // 近 N 天 = (N-1) 天前到今天，共 N 个自然日（含今天）
        let cutoff = range.days.map { calendar.date(byAdding: .day, value: -($0 - 1), to: now)! }

        let samples = ((try? store.weightSamples(limit: 400)) ?? [])
            .filter { sample in
                guard let cutoff else { return true }
                // 按自然日比较，避免样本记录时间与查询时刻的分钟级漂移落在窗口外
                return calendar.startOfDay(for: sample.date) >= calendar.startOfDay(for: cutoff)
            }
            .sorted { $0.date < $1.date }
        weightPoints = samples.map { WeightPoint(date: $0.date, kg: $0.weightKg) }
        hasEnoughWeightData = samples.count >= 4   // spec 7.6：数据点 < 4 显示统计卡

        if samples.count >= 3, let firstDate = samples.first?.date {
            let points = samples.map { (x: $0.date.timeIntervalSince(firstDate) / 86400, y: $0.weightKg) }
            if let fit = LinearRegression.fit(points: points) {
                trendPoints = [
                    WeightPoint(date: firstDate, kg: fit.intercept + fit.slope * points.first!.x),
                    WeightPoint(date: samples.last!.date, kg: fit.intercept + fit.slope * points.last!.x)
                ]
            }
        } else {
            trendPoints = []
        }

        var intake: [IntakePoint] = []
        let start = cutoff.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: samples.first?.date ?? now)
        var day = start
        let end = calendar.startOfDay(for: now)
        while day <= end {
            intake.append(IntakePoint(date: day, kcal: (try? store.daySummary(day))?.totalNutrition.kcal ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        intakePoints = intake
        targetKcal = (try? store.currentGoal())?.targets.kcal ?? 0
    }
}
