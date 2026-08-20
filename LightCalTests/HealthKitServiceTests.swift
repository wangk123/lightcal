import XCTest
import HealthKit
@testable import LightCal

final class HealthKitServiceTests: XCTestCase {
    // 模拟器环境无法稳定授权，本任务单测覆盖：类型标识映射、错误枚举、协议可被 mock（Task 13 的管线测试使用 MockHealthKit）

    func testQuantityTypeIdentifiers() {
        XCTAssertEqual(HealthKitService.activeEnergyType.identifier, HKQuantityTypeIdentifier.activeEnergyBurned.rawValue)
        XCTAssertEqual(HealthKitService.bodyMassType.identifier, HKQuantityTypeIdentifier.bodyMass.rawValue)
        XCTAssertEqual(HealthKitService.waterType.identifier, HKQuantityTypeIdentifier.dietaryWater.rawValue)
    }

    func testHealthKitErrorEquatable() {
        XCTAssertEqual(HealthKitError.unavailable, .unavailable)
        XCTAssertEqual(HealthKitError.notDetermined, .notDetermined)
    }
}

/// 供管线测试复用的 mock（Task 13 用）
final class MockHealthKit: HealthKitServing, @unchecked Sendable {
    var activeEnergy: [String: Double] = [:]
    var weightsToReturn: [WeightSample] = []
    var latestWeight: Double?
    var savedWeights: [(kg: Double, date: Date)] = []
    var savedWaters: [(ml: Double, date: Date)] = []
    var authorizationError: Error?

    func requestAuthorization() async throws {
        if let authorizationError { throw authorizationError }
    }

    func activeEnergyKcal(on day: Date) async throws -> Double {
        let key = ISO8601DateFormatter().string(from: day)
        return activeEnergy[key] ?? 0
    }

    func saveWeight(kg: Double, date: Date) async throws { savedWeights.append((kg, date)) }
    func saveWater(ml: Double, date: Date) async throws { savedWaters.append((ml, date)) }
    func latestWeightKg() async throws -> Double? { latestWeight }
    func weights(limit: Int) async throws -> [WeightSample] { Array(weightsToReturn.prefix(limit)) }
}
