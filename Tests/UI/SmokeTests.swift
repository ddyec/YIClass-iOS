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

extension SmokeTests {
    func testPDFImportCompactSettingsAndWeekHeight() throws {
        let fixture = Bundle(for: SmokeTests.self).url(forResource: "timetable-grid", withExtension: "pdf")!
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--ui-testing-demo", "--ui-testing-pdf"]
        app.launchEnvironment["YICLASS_UI_PDF"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launch()
        XCTAssertTrue(app.buttons["添加课程"].firstMatch.waitForExistence(timeout: 20))
        app.tabBars.buttons["设置"].tap()
        attach(app, name: "紧凑-设置")
        app.buttons["统一课节时间"].tap()
        XCTAssertTrue(app.steppers.matching(NSPredicate(format: "label CONTAINS %@", "上午")).firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "紧凑-统一课节时间")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["AI 识别课表"].tap()
        XCTAssertTrue(app.buttons["直接预览结构化课表"].waitForExistence(timeout: 20))
        app.buttons["直接预览结构化课表"].tap()
        XCTAssertTrue(app.navigationBars["确认导入"].waitForExistence(timeout: 5))
        attach(app, name: "PDF-导入预览")
        app.navigationBars.buttons["导入"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.tabBars.buttons["课表"].tap()
        XCTAssertTrue(app.navigationBars["导入课表"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "普通化学II")).firstMatch.exists)
        attach(app, name: "PDF-第8周-一屏高度")
        app.buttons["列表"].tap()
        XCTAssertTrue(app.staticTexts["未排时间"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "军事技能")).firstMatch.exists)
        attach(app, name: "PDF-未排时间课程")
    }
}
