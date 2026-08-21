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

        // 时间线在页面底部（List 懒加载），先滚动到可见
        app.swipeUp()

        // 时间线出现记录
        XCTAssertTrue(app.staticTexts["鸡胸肉 100g"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["133 kcal"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTimelineShowsWaterAndSwipeDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()

        // 饮水快加后，滚动到底部，时间线出现饮水行（区别于水卡「X / 2100 ml」）
        let water = app.buttons["waterQuick250"]
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        water.tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["250 ml"].waitForExistence(timeout: 5))

        // 左滑删除饮水行：时间线行消失；回到顶部后水卡归零
        revealSwipeActions(forText: "250 ml", in: app)
        let delete = app.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(app.staticTexts["250 ml"].waitForExistence(timeout: 2))
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["0 / 2100 ml"].waitForExistence(timeout: 5))

        // 文字录入食物 → 时间线出现（先滚动）→ 左滑删除 → 回到空态
        app.buttons["addEntry"].tap()
        app.buttons["textEntry"].tap()
        let field = app.textFields["logTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("100g鸡胸肉")
        app.buttons["parseAndConfirm"].tap()
        XCTAssertTrue(app.staticTexts["鸡胸肉"].waitForExistence(timeout: 10))
        app.buttons["saveDraft"].tap()

        app.swipeUp()
        XCTAssertTrue(app.staticTexts["鸡胸肉 100g"].waitForExistence(timeout: 5))
        revealSwipeActions(forText: "鸡胸肉 100g", in: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(app.staticTexts["鸡胸肉 100g"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["还没有记录，点右上角 + 开始打卡"].waitForExistence(timeout: 5))
    }

    /// 受控左滑露出行尾删除按钮。
    /// 直接对行内文本 `swipeLeft()` 不可靠：窄文本（如「250 ml」约 50pt）拖距太短，低于滑动操作露出阈值，
    /// 按钮不会出现；拖距过长又会触发 `swipeActions(allowsFullSwipe: true)` 直接整行删除、同样看不到按钮。
    /// 这里对整行做约一半宽度的慢速拖拽，稳定露出「删除」。
    private func revealSwipeActions(forText text: String, in app: XCUIApplication) {
        let cell = app.cells.containing(.staticText, identifier: text).firstMatch
        let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        start.press(forDuration: 0.6, thenDragTo: end)
    }
}
