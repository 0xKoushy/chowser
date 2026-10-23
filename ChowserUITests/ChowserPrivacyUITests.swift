import XCTest

final class ChowserPrivacyUITests: ChowserUITestCase {
    func testReducingActivityRequiresConsentAndOffErasesPersistedLinks() {
        launchClassicPickerFixture(suiteLabel: "activity-levels")
        let driver = ChowserAppDriver(app: app)
        driver.assertPickerVisible()
        app.typeKey(.escape, modifierFlags: [])
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: driver.pickerRoot)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        driver.openSettings()
        driver.clickSidebarItem(identifier: "settings.sidebar.activity")
        let row = app.descendants(matching: .any).matching(identifier: "settings.activity.row.dismissed").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let file = logsDirectory.appendingPathComponent("link-history.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        chooseLevel("Stats only", action: "Cancel")
        XCTAssertEqual(level.value as? String, "Full history")
        XCTAssertTrue(row.exists)
        chooseLevel("Stats only", action: "Delete and Switch")
        XCTAssertEqual(level.value as? String, "Stats only")
        XCTAssertFalse(app.textFields["settings.activity.searchField"].exists)
        chooseLevel("Off", action: "Delete and Switch")
        XCTAssertEqual(level.value as? String, "Off")
        XCTAssertTrue(app.staticTexts["History is off"].waitForExistence(timeout: 5))
        let erased = NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: file.path)
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: erased, object: nil)], timeout: 5), .completed)
        chooseLevel("Full history")
        XCTAssertEqual(level.value as? String, "Full history")
        XCTAssertTrue(app.staticTexts["settings.activity.noRows"].exists)
        XCTAssertFalse(row.exists)
    }

    private var level: XCUIElement { app.popUpButtons["settings.activity.levelPicker"] }

    private func chooseLevel(_ title: String, action: String? = nil) {
        app.activate()
        level.click()
        let option = app.menuItems[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.click()
        if let action {
            let button = app.sheets.buttons[action]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.click()
        }
    }
}
