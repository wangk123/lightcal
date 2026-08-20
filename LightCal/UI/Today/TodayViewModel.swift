import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {
    private let store: DataStore
    private let database: FoodDatabase
    private let healthKit: HealthKitServing
    private let pipeline: LoggingPipelining

    var selectedMeal: MealKind = .lunch
    var draft: LogDraft?
    private(set) var summary = DaySummary(totalNutrition: NutritionFacts(), waterMl: 0)
    private(set) var gap = GapAnalysis(remainingKcal: 0, proteinGap: 0, carbGap: 0, fatGap: 0)
    private(set) var suggestions: [FoodSuggestion] = []
    private(set) var prediction: PredictionScenarios?
    private(set) var weightRate: Double?
    private(set) var energyRate: Double?

    init(store: DataStore, database: FoodDatabase, healthKit: HealthKitServing, pipeline: LoggingPipelining) {
        self.store = store
        self.database = database
        self.healthKit = healthKit
        self.pipeline = pipeline
    }

    var waterTargetMl: Double {
        (try? store.currentGoal()?.waterTargetMl) ?? 2100
    }

    var waterText: String {
        "\(Formatting.mlText(summary.waterMl)) / \(Formatting.mlText(waterTargetMl)) ml"
    }

    func refresh() async {
        let now = Date()
        summary = (try? store.daySummary(now)) ?? DaySummary(totalNutrition: NutritionFacts(), waterMl: 0)
        let goal = try? store.currentGoal()
        let targets = goal?.targets ?? DailyTargets()

        let intake = summary.totalNutrition
        gap = GapAnalysis(
            remainingKcal: targets.kcal - intake.kcal,
            proteinGap: targets.protein - intake.protein,
            carbGap: targets.carb - intake.carb,
            fatGap: targets.fat - intake.fat
        )

        // 建议清单：候选池 = 内置库 + 自定义食物（AI 估算不进池，spec 6.2）
        var candidates = database.foods
        if let custom = try? store.allCustomFoods() {
            candidates += custom.map {
                FoodRecord(name: $0.name, aliases: [], nutritionPer100g: $0.nutritionPer100g, defaultServingGrams: 100)
            }
        }
        let eaten = Set((try? store.logItems(on: now).map(\.name)) ?? [])
        suggestions = RecommendationEngine.suggestions(gap: gap, candidates: candidates, eatenToday: eaten)

        // 预测（spec 5.3/5.4）
        let samples = (try? store.weightSamples(limit: 50)) ?? []
        let localWeightRate = RateCalculator.weightTrendRateKgsPerWeek(samples: samples)
        var deficits: [Double] = []   // deficit[i] = 消耗[i] - 摄入[i]（正 = 有缺口）
        var totalIntake = 0.0
        let calendar = Calendar.current
        var deficitDays = 0
        for daysAgo in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let intake = (try? store.daySummary(day))?.totalNutrition.kcal ?? 0
            let bmr = Self.bmrForCurrentProfile(store: store)
            let active = (try? await healthKit.activeEnergyKcal(on: day)) ?? 0
            deficits.append(bmr + active - intake)
            totalIntake += intake
            deficitDays += 1
        }
        let energyRate = RateCalculator.energyTrendRateKgsPerWeek(dailyDeficits: deficits)
        weightRate = localWeightRate
        self.energyRate = energyRate

        let latestWeight = samples.first?.weightKg ?? (try? store.profile())?.initialWeightKg ?? 0
        let targetWeight = goal?.targetWeightKg ?? 0
        // 平均总消耗 = 平均摄入 + 平均缺口（deficit = 消耗 - 摄入 恒等变形）
        let avgDeficit = deficitDays > 0 ? deficits.reduce(0, +) / Double(deficitDays) : 0
        let avgIntake = deficitDays > 0 ? totalIntake / Double(deficitDays) : 0
        let avgExpenditure = avgIntake + avgDeficit

        prediction = PredictionCalculator.scenarios(
            currentWeightKg: latestWeight,
            targetWeightKg: targetWeight,
            weightRate: localWeightRate,
            energyRate: energyRate,
            targetKcal: targets.kcal,
            avgDailyExpenditureLast7d: avgExpenditure
        )
    }

    private static func bmrForCurrentProfile(store: DataStore) -> Double {
        guard let profile = try? store.profile() else { return 1600 }
        let age = Calendar.current.dateComponents([.year], from: profile.birthDate, to: .now).year ?? 30
        let input = ProfileInput(
            sex: Sex(rawValue: profile.sex) ?? .male,
            ageYears: age,
            heightCm: profile.heightCm,
            weightKg: profile.initialWeightKg,
            activityFactor: profile.activityFactor
        )
        return NutritionCalculator.bmr(input)
    }

    func addWater(ml: Double) {
        try? store.addWater(ml: ml, date: .now)
    }

    func saveDraft(items: [CompletedFoodItem]? = nil) {
        let toSave = items ?? draft?.items ?? []
        guard !toSave.isEmpty else { return }
        try? store.saveLogItems(toSave, date: .now, meal: selectedMeal)
        self.draft = nil
    }
}
