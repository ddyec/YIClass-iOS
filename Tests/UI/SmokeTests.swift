import XCTest
import UIKit

@MainActor final class SmokeTests: XCTestCase {
    func testFirstLaunchAndSettingsNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["添加课程"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["设置"].tap()
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
        app.buttons["AI 助手"].tap()
        XCTAssertTrue(app.buttons["关闭助手"].waitForExistence(timeout: 5))
        attach(app, name: "深色-助手")
        app.buttons["关闭助手"].tap()
        app.buttons["设置"].tap()
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

    func testEveningToggleStaysAboveFloatingNavigation() {
        defer { XCUIDevice.shared.orientation = .portrait }
        for appearance in ["light", "dark"] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance", appearance, "--ui-testing-demo"]
            app.launch()
            let toggle = app.buttons["evening-toggle"]
            let assistant = app.buttons["ai-assistant-button"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            XCTAssertTrue(assistant.exists)

            for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
                XCUIDevice.shared.orientation = orientation
                XCTAssertTrue(toggle.isHittable)
                XCTAssertLessThanOrEqual(toggle.frame.maxY, assistant.frame.minY)
                XCTAssertLessThanOrEqual(toggle.frame.maxY, app.buttons["课表"].frame.minY)
                toggle.tap()
                XCTAssertTrue(toggle.label.contains("收起晚间"))

                let grid = app.scrollViews["week-grid-scroll"]
                let lastPeriod = app.staticTexts["20:40"]
                for _ in 0..<5 {
                    if lastPeriod.exists && lastPeriod.frame.maxY <= toggle.frame.minY { break }
                    grid.swipeUp()
                }
                XCTAssertTrue(lastPeriod.isHittable)
                XCTAssertLessThanOrEqual(lastPeriod.frame.maxY, toggle.frame.minY, "最后一节应能滚动到晚间条上方")
                XCTAssertLessThanOrEqual(toggle.frame.maxY, assistant.frame.minY)
                attach(app, name: "\(appearance)-晚间展开-\(orientation.rawValue)")
                toggle.tap()
                XCTAssertTrue(toggle.label.contains("展开"))
                XCTAssertTrue(toggle.isHittable)
            }
            assistant.tap()
            XCTAssertTrue(app.buttons["关闭助手"].waitForExistence(timeout: 5))
            app.buttons["关闭助手"].tap()
            XCTAssertTrue(toggle.isHittable)
            app.terminate()
        }
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
        app.buttons["设置"].tap()
        attach(app, name: "紧凑-设置")
        app.buttons["统一课节时间"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "上午")).firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "紧凑-统一课节时间")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["AI 识别课表"].tap()
        XCTAssertTrue(app.buttons["直接预览结构化课表"].waitForExistence(timeout: 20))
        app.buttons["直接预览结构化课表"].tap()
        XCTAssertTrue(app.navigationBars["确认导入"].waitForExistence(timeout: 5))
        attach(app, name: "PDF-导入预览")
        app.navigationBars.buttons["导入"].tap()
        XCTAssertTrue(app.buttons["关闭助手"].waitForExistence(timeout: 5))
        app.buttons["关闭助手"].tap()
        app.buttons["课表"].tap()
        XCTAssertTrue(app.navigationBars["导入课表"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "普通化学II")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "实验室安全通识教育")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["20:40"].isHittable, "第 10 节结束时间应在默认字号的一屏中可见")
        attach(app, name: "PDF-第8周-一屏高度")
        app.buttons["列表"].tap()
        XCTAssertTrue(app.staticTexts["未排时间"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "军事技能")).firstMatch.exists)
        attach(app, name: "PDF-未排时间课程")
        app.buttons["日"].tap()
        XCTAssertTrue(app.buttons["本日"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["前一天"].exists && app.buttons["后一天"].exists)
        let calendar = app.buttons["day-calendar"]
        let today = calendar.label
        app.buttons["后一天"].tap()
        XCTAssertNotEqual(calendar.label, today)
        app.buttons["前一天"].tap()
        XCTAssertEqual(calendar.label, today)
        calendar.tap()
        XCTAssertTrue(app.navigationBars["选择日期"].waitForExistence(timeout: 5))
        attach(app, name: "日视图-日期日历")
        app.buttons["完成"].tap()
        attach(app, name: "日视图-本日导航")
    }
}
