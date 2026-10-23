import XCTest

/// Optional manual UI suite. Device delivery does not run or wait for a simulator.
@MainActor final class NavigationPolishTests: XCTestCase {
    private func launch(_ appearance: String, todos: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance", appearance, "-reminders.permissionAsked", "YES", "-reminders.enabled", "NO", "--ui-testing-demo"]
        if todos { app.launchArguments.append("--ui-testing-todos") }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["课表"].waitForExistence(timeout: 15))
        return app
    }
    func testNativeTabsAndAssistantReturnToSelectedPage() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            app.tabBars.buttons["设置"].tap()
            XCTAssertTrue(app.buttons["统一课节时间"].waitForExistence(timeout: 5))
            app.tabBars.buttons["AI 助手"].tap()
            XCTAssertTrue(app.buttons["关闭助手"].waitForExistence(timeout: 5))
            app.buttons["关闭助手"].tap()
            XCTAssertTrue(app.tabBars.buttons["设置"].isSelected)
            XCTAssertTrue(app.buttons["统一课节时间"].exists)
            app.tabBars.buttons["待办"].tap()
            XCTAssertTrue(app.staticTexts["待完成"].waitForExistence(timeout: 5))
            app.tabBars.buttons["课表"].tap()
            XCTAssertTrue(app.buttons["添加课程"].firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
    }
    func testPendingProminenceAndCompletedDefaultCollapse() {
        for appearance in ["light", "dark"] {
            for populated in [false, true] {
                let app = launch(appearance, todos: populated)
                app.tabBars.buttons["待办"].tap()
                XCTAssertTrue(app.staticTexts["待完成"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["暂无已完成事项"].exists)
                XCTAssertFalse(app.staticTexts["已完成的测试事项"].exists)
                if populated { XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "完成实验报告")).firstMatch.exists || app.staticTexts["完成实验报告"].exists) }
                else { XCTAssertTrue(app.staticTexts["暂无待办"].exists) }
                app.terminate()
            }
        }
    }
}
