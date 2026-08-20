import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    var sex: Sex = .male
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
    var heightCm: Double = 175
    var initialWeightKg: Double = 70
    var targetWeightKg: Double = 65
    var activityFactor: Double = 1.375

    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 30
    }

    var profileInput: ProfileInput {
        ProfileInput(sex: sex, ageYears: ageYears, heightCm: heightCm, weightKg: initialWeightKg, activityFactor: activityFactor)
    }

    var defaultTargets: DailyTargets {
        NutritionCalculator.defaultTargets(for: profileInput)
    }

    var defaultWaterMl: Double {
        NutritionCalculator.defaultWaterTargetMl(weightKg: initialWeightKg)
    }

    /// 保存档案 + 首个目标版本（spec 3.2：目标可后续修改并留档）
    func save(into store: DataStore) throws {
        let profile = UserProfile(
            sex: sex.rawValue,
            birthDate: birthDate,
            heightCm: heightCm,
            initialWeightKg: initialWeightKg,
            activityFactor: activityFactor
        )
        try store.upsertProfile(profile)
        let targets = defaultTargets
        try store.appendGoal(Goal(
            targetWeightKg: targetWeightKg,
            startDate: .now,
            startWeightKg: initialWeightKg,
            targets: targets,
            systemTargets: targets,
            waterTargetMl: defaultWaterMl
        ))
    }
}
