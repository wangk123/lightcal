import Foundation
import SwiftData

struct DaySummary: Equatable {
    var totalNutrition: NutritionFacts
    var waterMl: Double
}

@MainActor
final class DataStore {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    static func makeInMemory() throws -> DataStore {
        let schema = Schema([
            UserProfile.self, Goal.self, CustomFood.self,
            FoodLogItem.self, WaterLogItem.self, WeightRecord.self, PresetFood.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return DataStore(container: try ModelContainer(for: schema, configurations: [config]))
    }

    static func makeOnDisk() throws -> DataStore {
        let schema = Schema([
            UserProfile.self, Goal.self, CustomFood.self,
            FoodLogItem.self, WaterLogItem.self, WeightRecord.self, PresetFood.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return DataStore(container: try ModelContainer(for: schema, configurations: [config]))
    }

    // MARK: - Profile

    func upsertProfile(_ profile: UserProfile) throws {
        let context = container.mainContext
        let existing = try self.profile()
        if let existing {
            existing.sex = profile.sex
            existing.birthDate = profile.birthDate
            existing.heightCm = profile.heightCm
            existing.initialWeightKg = profile.initialWeightKg
            existing.activityFactor = profile.activityFactor
        } else {
            context.insert(profile)
        }
        try context.save()
    }

    func profile() throws -> UserProfile? {
        try container.mainContext.fetch(FetchDescriptor<UserProfile>()).first
    }

    // MARK: - Goal（历史版本全部保留，currentGoal 取最新）

    func appendGoal(_ goal: Goal) throws {
        container.mainContext.insert(goal)
        try container.mainContext.save()
    }

    func allGoals() throws -> [Goal] {
        try container.mainContext.fetch(FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    func currentGoal() throws -> Goal? {
        try allGoals().first
    }

    // MARK: - 打卡

    func saveLogItems(_ items: [CompletedFoodItem], date: Date, meal: MealKind) throws {
        let startOfDay = Calendar.current.startOfDay(for: date)
        for item in items {
            container.mainContext.insert(FoodLogItem(
                date: startOfDay,
                meal: meal.rawValue,
                name: item.name,
                grams: item.grams,
                nutrition: item.nutrition,
                source: item.source.rawValue,
                volumeMl: item.volumeMl
            ))
        }
        try container.mainContext.save()
    }

    func logItems(on day: Date) throws -> [FoodLogItem] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return try container.mainContext.fetch(FetchDescriptor<FoodLogItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    func deleteLogItem(_ item: FoodLogItem) throws {
        container.mainContext.delete(item)
        try container.mainContext.save()
    }

    // MARK: - 饮水

    func addWater(ml: Double, date: Date) throws {
        container.mainContext.insert(WaterLogItem(date: Calendar.current.startOfDay(for: date), amountMl: ml))
        try container.mainContext.save()
    }

    func waterItems(on day: Date) throws -> [WaterLogItem] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return try container.mainContext.fetch(FetchDescriptor<WaterLogItem>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    func deleteWaterItem(_ item: WaterLogItem) throws {
        container.mainContext.delete(item)
        try container.mainContext.save()
    }

    // MARK: - 每日聚合（派生数据，不落库 spec 3.8）

    func daySummary(_ day: Date) throws -> DaySummary {
        let items = try logItems(on: day)
        let total = items.reduce(NutritionFacts()) { $0 + $1.nutrition }
        let water = try waterItems(on: day).reduce(0) { $0 + $1.amountMl }
        return DaySummary(totalNutrition: total, waterMl: water)
    }

    // MARK: - 自定义食物

    func saveCustomFood(_ food: CustomFood) throws {
        container.mainContext.insert(food)
        try container.mainContext.save()
    }

    func allCustomFoods() throws -> [CustomFood] {
        try container.mainContext.fetch(FetchDescriptor<CustomFood>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    func deleteCustomFood(_ food: CustomFood) throws {
        container.mainContext.delete(food)
        try container.mainContext.save()
    }

    // MARK: - 体重

    func addWeight(kg: Double, date: Date) throws {
        container.mainContext.insert(WeightRecord(date: date, weightKg: kg))
        try container.mainContext.save()
    }

    func weightSamples(limit: Int = 100) throws -> [WeightSample] {
        let records = try container.mainContext.fetch(FetchDescriptor<WeightRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
        return records.prefix(limit).map { WeightSample(date: $0.date, weightKg: $0.weightKg) }
    }

    // MARK: - 预设食物（缺口建议只在此范围内推荐）

    func savePresetFood(_ food: PresetFood) throws {
        container.mainContext.insert(food)
        try container.mainContext.save()
    }

    func allPresetFoods() throws -> [PresetFood] {
        try container.mainContext.fetch(FetchDescriptor<PresetFood>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    func deletePresetFood(_ food: PresetFood) throws {
        container.mainContext.delete(food)
        try container.mainContext.save()
    }

    // MARK: - 导出

    /// 导出快照：纯值 Codable 结构（@Model 类不自动获得 Codable 合成，导出格式与 SwiftData 内部解耦）
    struct ExportDTO: Codable {
        let exportedAt: Date
        let profile: ProfileSnapshot?
        let goals: [GoalSnapshot]
        let customFoods: [CustomFoodSnapshot]
        let presetFoods: [PresetFoodSnapshot]
        let logItems: [LogItemSnapshot]
        let waterItems: [WaterSnapshot]
        let weightRecords: [WeightSnapshot]

        struct ProfileSnapshot: Codable {
            let sex: String
            let birthDate: Date
            let heightCm: Double
            let initialWeightKg: Double
            let activityFactor: Double
        }

        struct GoalSnapshot: Codable {
            let targetWeightKg: Double
            let startDate: Date
            let startWeightKg: Double
            let targets: DailyTargets
            let systemTargets: DailyTargets
            let waterTargetMl: Double
            let createdAt: Date
        }

        struct CustomFoodSnapshot: Codable {
            let name: String
            let nutritionPer100g: NutritionFacts
            let createdAt: Date
        }

        struct PresetFoodSnapshot: Codable {
            let name: String
            let nutritionPer100g: NutritionFacts
            let createdAt: Date
        }

        struct LogItemSnapshot: Codable {
            let date: Date
            let meal: String
            let name: String
            let grams: Double
            let nutrition: NutritionFacts
            let source: String
            let volumeMl: Double?
            let createdAt: Date
        }

        struct WaterSnapshot: Codable {
            let date: Date
            let amountMl: Double
            let createdAt: Date
        }

        struct WeightSnapshot: Codable {
            let date: Date
            let weightKg: Double
            let createdAt: Date
        }
    }

    func exportJSON() throws -> Data {
        let context = container.mainContext
        let profileModel = try profile()
        let dto = ExportDTO(
            exportedAt: .now,
            profile: profileModel.map {
                ExportDTO.ProfileSnapshot(
                    sex: $0.sex, birthDate: $0.birthDate, heightCm: $0.heightCm,
                    initialWeightKg: $0.initialWeightKg, activityFactor: $0.activityFactor
                )
            },
            goals: try context.fetch(FetchDescriptor<Goal>()).map {
                ExportDTO.GoalSnapshot(
                    targetWeightKg: $0.targetWeightKg, startDate: $0.startDate, startWeightKg: $0.startWeightKg,
                    targets: $0.targets, systemTargets: $0.systemTargets, waterTargetMl: $0.waterTargetMl, createdAt: $0.createdAt
                )
            },
            customFoods: try context.fetch(FetchDescriptor<CustomFood>()).map {
                ExportDTO.CustomFoodSnapshot(name: $0.name, nutritionPer100g: $0.nutritionPer100g, createdAt: $0.createdAt)
            },
            presetFoods: try context.fetch(FetchDescriptor<PresetFood>()).map {
                ExportDTO.PresetFoodSnapshot(name: $0.name, nutritionPer100g: $0.nutritionPer100g, createdAt: $0.createdAt)
            },
            logItems: try context.fetch(FetchDescriptor<FoodLogItem>()).map {
                ExportDTO.LogItemSnapshot(
                    date: $0.date, meal: $0.meal, name: $0.name, grams: $0.grams,
                    nutrition: $0.nutrition, source: $0.source, volumeMl: $0.volumeMl, createdAt: $0.createdAt
                )
            },
            waterItems: try context.fetch(FetchDescriptor<WaterLogItem>()).map {
                ExportDTO.WaterSnapshot(date: $0.date, amountMl: $0.amountMl, createdAt: $0.createdAt)
            },
            weightRecords: try context.fetch(FetchDescriptor<WeightRecord>()).map {
                ExportDTO.WeightSnapshot(date: $0.date, weightKg: $0.weightKg, createdAt: $0.createdAt)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(dto)
    }
}
