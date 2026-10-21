import XCTest

@MainActor final class SmokeTests: XCTestCase {
    func testFirstLaunchAndSettingsNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["添加课程"].firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["设置"].tap()
        app.buttons["统一课节时间"].tap()
        XCTAssertTrue(app.navigationBars["统一课节时间"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "统一课节时间-iOS26"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testDarkAppearanceAcrossMainScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance", "dark", "--ui-testing-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["添加课程"].firstMatch.waitForExistence(timeout: 10))
        attach(app, name: "深色-课表")
        app.tabBars.buttons["助手"].tap()
        XCTAssertTrue(app.navigationBars["课表助手"].waitForExistence(timeout: 5))
        attach(app, name: "深色-助手")
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["统一课节时间"].waitForExistence(timeout: 5))
        attach(app, name: "深色-设置")
    }

    func testLightWeeklySchedule() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance", "light", "--ui-testing-demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["秋季学期"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "高等数学")).firstMatch.exists)
        attach(app, name: "浅色-周视图")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
