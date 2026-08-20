import Foundation
import HealthKit

enum HealthKitError: Error, Equatable {
    case unavailable      // HealthKit 在当前设备不可用
    case notDetermined    // 未授权（UI 应先 requestAuthorization）
}

protocol HealthKitServing: Sendable {
    func requestAuthorization() async throws
    func activeEnergyKcal(on day: Date) async throws -> Double
    func saveWeight(kg: Double, date: Date) async throws
    func saveWater(ml: Double, date: Date) async throws
    func latestWeightKg() async throws -> Double?
    func weights(limit: Int) async throws -> [WeightSample]
}

/// HealthKit 读写封装（spec 2/5.2/12）：运动消耗读取、体重/饮水写回
final class HealthKitService: HealthKitServing, Sendable {
    private let store: HKHealthStore

    static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    static let bodyMassType = HKQuantityType(.bodyMass)
    static let waterType = HKQuantityType(.dietaryWater)

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    private var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        let types: Set<HKSampleType> = [Self.activeEnergyType, Self.bodyMassType, Self.waterType]
        try await store.requestAuthorization(toShare: types, read: types)
    }

    func activeEnergyKcal(on day: Date) async throws -> Double {
        guard isAvailable else { throw HealthKitError.unavailable }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: Self.activeEnergyType, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum
        )
        let result = try await descriptor.result(for: store)
        return result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
    }

    func saveWeight(kg: Double, date: Date) async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        let sample = HKQuantitySample(
            type: Self.bodyMassType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date, end: date
        )
        try await store.save(sample)
    }

    func saveWater(ml: Double, date: Date) async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        let sample = HKQuantitySample(
            type: Self.waterType,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml),
            start: date, end: date
        )
        try await store.save(sample)
    }

    func latestWeightKg() async throws -> Double? {
        try await weights(limit: 1).first?.weightKg
    }

    func weights(limit: Int) async throws -> [WeightSample] {
        guard isAvailable else { throw HealthKitError.unavailable }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMassType)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit
        )
        let samples = try await descriptor.result(for: store)
        return samples.map { sample in
            WeightSample(date: sample.startDate, weightKg: sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo)))
        }
    }
}
