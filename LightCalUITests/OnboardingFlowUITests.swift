import XCTest

final class OnboardingFlowUITests: XCTestCase {
    @MainActor
    func testOnboardingSaveEntersTodayPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-fresh"]   // 空库：走建档流程
        app.launch()

        // 建档页出现
        XCTAssertTrue(app.navigationBars["欢迎使用轻卡"].waitForExistence(timeout: 5))

        // 填必填字段（其余用默认值）
        let height = app.textFields["heightField"]
        XCTAssertTrue(height.waitForExistence(timeout: 5))
        height.tap()
        height.typeText("175")

        let targetWeight = app.textFields["targetWeightField"]
        targetWeight.tap()
        targetWeight.typeText("65")

        // 点开始 → 应立即进入主页（响应式切换，不需重启）
        app.buttons["finishOnboarding"].tap()

        // 主页出现：导航标题「今日」
        XCTAssertTrue(app.navigationBars["今日"].waitForExistence(timeout: 5))
    }
}
