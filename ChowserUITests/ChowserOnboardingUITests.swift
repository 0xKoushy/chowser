import XCTest

final class ChowserOnboardingUITests: ChowserUITestCase {
    func testAppModeQuestionPersistsEachExplicitChoice() {
        for (choice, expectedDock) in [("Menu Bar", "0"), ("App", "1")] {
            launchTestApp(arguments: ["-UITesting", "-UITesting_ClearData", "-UITesting_MockInstalledBrowsers",
                                      "-UITesting_DisableExternalOpen",
                                      "-UITesting_AppModeQuestionFixture"], suiteLabel: "mode-question-\(choice)")
            let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", choice)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            option.click()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "selected"), object: option)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
            app.buttons["Continue"].click()
            let driver = ChowserAppDriver(app: app)
            driver.openSettings()
            driver.openGeneralSection()
            let dock = app.descendants(matching: .any).matching(identifier: "settings.general.showInDock").firstMatch
            XCTAssertTrue(dock.waitForExistence(timeout: 5))
            XCTAssertEqual("\(dock.value ?? "")", expectedDock)
            XCTAssertFalse(app.buttons["Continue"].exists)
        }
    }
}
