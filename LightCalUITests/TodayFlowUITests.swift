import XCTest

final class TodayFlowUITests: XCTestCase {
    @MainActor
    func testWaterQuickAddAndTextLogging() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]   // 内存库 + 种子档案（跳过 Onboarding）
        app.launch()

        // 饮水快加
        let water = app.buttons["waterQuick500"]
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        water.tap()
        XCTAssertTrue(app.staticTexts["500 / 2100 ml"].waitForExistence(timeout: 5))

        // 文字录入：无 API Key 时走本地正则兜底
        app.buttons["addEntry"].tap()
        app.buttons["textEntry"].tap()
        let field = app.textFields["logTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("100g鸡胸肉")
        app.buttons["parseAndConfirm"].tap()
        XCTAssertTrue(app.staticTexts["鸡胸肉"].waitForExistence(timeout: 10))
        app.buttons["saveDraft"].tap()

        // 时间线出现记录
        XCTAssertTrue(app.staticTexts["鸡胸肉 100g"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["133 kcal"].waitForExistence(timeout: 5))
    }
}
