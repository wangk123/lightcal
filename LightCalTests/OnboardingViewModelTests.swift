import XCTest
@testable import LightCal

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testProfileInputDerived() {
        let vm = OnboardingViewModel()
        vm.sex = .female
        vm.heightCm = 165
        vm.initialWeightKg = 60
        vm.activityFactor = 1.2
        vm.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
        XCTAssertEqual(vm.profileInput.sex, .female)
        XCTAssertEqual(vm.profileInput.ageYears, 30)
        XCTAssertEqual(vm.profileInput.heightCm, 165)
        XCTAssertEqual(vm.profileInput.weightKg, 60)
    }

    func testDefaultTargetsFromViewModel() {
        let vm = OnboardingViewModel()
        vm.initialWeightKg = 70
        XCTAssertEqual(vm.defaultTargets.protein, 1.8 * 70, accuracy: 0.001)
        XCTAssertEqual(vm.defaultWaterMl, 2100)
    }

    func testSavePersistsProfileAndGoal() throws {
        let store = try DataStore.makeInMemory()
        let vm = OnboardingViewModel()
        vm.targetWeightKg = 65
        try vm.save(into: store)
        XCTAssertNotNil(try store.profile())
        let goal = try store.currentGoal()
        XCTAssertEqual(goal?.targetWeightKg, 65)
        XCTAssertEqual(goal?.startWeightKg, vm.initialWeightKg)
        XCTAssertEqual(goal?.targets, vm.defaultTargets)          // 当前目标 = 系统默认（未微调）
        XCTAssertEqual(goal?.systemTargets, vm.defaultTargets)    // 默认值分开留档
        XCTAssertEqual(goal?.waterTargetMl, 2100)
    }
}
