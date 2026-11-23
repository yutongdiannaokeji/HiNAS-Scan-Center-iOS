import XCTest

final class ScanCenterUITests: XCTestCase {
    private func screenshot(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "scan-center-" + name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testNativeScreensAreVisible() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["connectDeviceAction"].waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(app.buttons["connectDeviceAction"].isHittable, app.debugDescription)
        XCTAssertTrue(app.navigationBars["扫描"].exists)
        screenshot("scan", app: app)

        let screens = [("文档", "我的文档", "documents"), ("打印", "打印", "print"), ("设备", "设备", "device")]
        for (tab, title, name) in screens {
            let button = app.buttons.matching(identifier: tab).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 20), app.debugDescription)
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 20), app.debugDescription)
            screenshot(name, app: app)
        }

        app.terminate()
        app.launchArguments = ["--dark-mode"]
        app.launch()
        XCTAssertTrue(app.buttons["connectDeviceAction"].waitForExistence(timeout: 45), app.debugDescription)
        screenshot("dark", app: app)

        app.terminate()
        app.launchArguments = ["--large-type"]
        app.launch()
        XCTAssertTrue(app.buttons["connectDeviceAction"].waitForExistence(timeout: 45), app.debugDescription)
        screenshot("large-type", app: app)
        app.terminate()
    }
}
