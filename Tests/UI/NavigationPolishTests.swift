import XCTest

@MainActor final class NavigationPolishTests: XCTestCase {
    private func launch(_ appearance: String, todos: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance", appearance, "-reminders.permissionAsked", "YES", "-reminders.enabled", "NO", "--ui-testing-demo"]
        if todos { app.launchArguments.append("--ui-testing-todos") }
        app.launch()
        XCTAssertTrue(app.buttons["ai-assistant-button"].waitForExistence(timeout: 15))
        return app
    }
    private func attach(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func waitValue(_ value: String, button: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", value), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 6), .completed)
    }
    func testGlassRestSelectionDragAndScrollCollapse() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance)
            app.segmentedControls.buttons["日"].firstMatch.tap()
            let scroll = app.scrollViews["day-agenda-scroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 5))
            let assistant = app.buttons["ai-assistant-button"]
            let originalAIFrame = assistant.frame
            attach("\(appearance)-01-rest-day", app: app)
            let first = app.buttons["navigation-0"]
            let last = app.buttons["navigation-2"]
            first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.3, thenDragTo: last.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            XCTAssertTrue(app.buttons["统一课节时间"].waitForExistence(timeout: 5))
            attach("\(appearance)-02-rest-after-drag", app: app)
            app.buttons["navigation-0"].tap()
            XCTAssertTrue(scroll.waitForExistence(timeout: 5))
            scroll.swipeUp(velocity: .slow)
            waitValue("已收起", button: first)
            XCTAssertLessThanOrEqual(first.frame.width, 64)
            XCTAssertEqual(assistant.frame.midX, originalAIFrame.midX, accuracy: 1)
            XCTAssertEqual(assistant.frame.midY, originalAIFrame.midY, accuracy: 1)
            attach("\(appearance)-03-collapsed", app: app)
            first.tap()
            waitValue("已展开", button: first)
            XCTAssertGreaterThan(first.frame.width, 65)
            scroll.swipeUp(velocity: .slow)
            waitValue("已收起", button: first)
            scroll.swipeDown(velocity: .slow)
            waitValue("已展开", button: first)
            attach("\(appearance)-04-expanded-after-scroll", app: app)
            assistant.tap()
            XCTAssertTrue(app.buttons["关闭助手"].waitForExistence(timeout: 5))
            app.buttons["关闭助手"].tap()
            app.terminate()
        }
    }
    func testPendingProminenceAndCompletedDefaultCollapse() {
        for appearance in ["light", "dark"] {
            for populated in [false, true] {
                let app = launch(appearance, todos: populated)
                app.buttons["navigation-3"].tap()
                XCTAssertTrue(app.staticTexts["待完成"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.staticTexts["暂无已完成事项"].exists)
                XCTAssertFalse(app.staticTexts["已完成的测试事项"].exists)
                if populated { XCTAssertTrue(app.buttons.containing(.staticText, identifier: "完成实验报告").firstMatch.exists || app.staticTexts["完成实验报告"].exists) }
                else { XCTAssertTrue(app.staticTexts["暂无待办"].exists) }
                attach("\(appearance)-todo-\(populated ? "populated" : "empty")", app: app)
                app.terminate()
            }
        }
    }
}
