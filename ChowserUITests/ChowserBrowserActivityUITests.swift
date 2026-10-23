import XCTest

final class ChowserBrowserActivityUITests: ChowserUITestCase {
    func testBrowserInspectorCommitsChangesAndUndoRestoresTheBrowser() {
        let driver = ChowserAppDriver(app: app)
        driver.openBrowsersSection()
        XCTAssertTrue(driver.browserRows.firstMatch.waitForExistence(timeout: 5))
        driver.browserRows.firstMatch.click()
        let inspector = app.descendants(matching: .any).matching(identifier: "settings.browserInspector").firstMatch
        let name = app.textFields["settings.browserInspector.nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: "Lab Safari")
        app.typeKey(.return, modifierFlags: [])
        assertContains("Lab Safari", in: driver.browserRows.firstMatch)
        let advanced = inspector.disclosureTriangles.firstMatch
        reveal(advanced, in: inspector)
        advanced.click()
        let args = app.textFields["settings.browserInspector.argsField"]
        reveal(args, in: inspector)
        replaceText(args, with: "--lab={url}")
        app.typeKey(.return, modifierFlags: [])
        let privateArgs = app.textFields["settings.browserInspector.privateArgsField"]
        reveal(privateArgs, in: inspector)
        replaceText(privateArgs, with: "--private-lab")
        app.typeKey(.return, modifierFlags: [])
        driver.browserRemoveButton.click()
        let confirm = app.buttons["settings.confirmDelete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        assertCount(0, in: driver.browserRows)
        let undo = app.links["settings.browser.undoRemoveButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.click()
        assertCount(1, in: driver.browserRows)
        driver.browserRows.firstMatch.click()
        assertContains("Lab Safari", in: driver.browserRows.firstMatch)
        XCTAssertEqual(app.textFields["settings.browserInspector.nameField"].value as? String, "Lab Safari")
    }

    func testHiddenAppCanBeAddedThenRemovedWithoutChangingBrowsers() {
        let driver = ChowserAppDriver(app: app)
        driver.openBrowsersSection()
        XCTAssertTrue(driver.browserRows.firstMatch.waitForExistence(timeout: 5))
        let count = driver.browserRows.count
        app.buttons["settings.hiddenApps.disclosure"].click()
        let field = app.textFields["settings.hiddenApps.bundleIdField"]
        replaceText(field, with: "lab.synthetic.browser")
        app.buttons["settings.hiddenApps.hideButton"].click()
        let row = app.staticTexts["lab.synthetic.browser"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let show = app.buttons.matching(identifier: "settings.hiddenApps.showButton")
            .matching(NSPredicate(format: "label CONTAINS %@", "lab.synthetic.browser")).firstMatch
        show.click()
        XCTAssertFalse(row.exists)
        app.buttons["Done"].click()
        assertCount(count, in: driver.browserRows)
    }

    func testActivityFiltersSearchAndClearHistoryUseOnlyTheSelectedData() {
        launchClassicPickerFixture(suiteLabel: "activity-controls")
        let driver = ChowserAppDriver(app: app)
        driver.assertPickerVisible()
        app.typeKey(.escape, modifierFlags: [])
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: driver.pickerRoot)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        driver.openSettings()
        driver.clickSidebarItem(identifier: "settings.sidebar.activity")
        let row = app.descendants(matching: .any).matching(identifier: "settings.activity.row.dismissed").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.buttons["settings.activity.filter.Auto-routed"].click()
        XCTAssertFalse(row.exists)
        XCTAssertTrue(app.staticTexts["settings.activity.noRows"].exists)
        app.buttons["settings.activity.filter.Dismissed"].click()
        XCTAssertTrue(row.exists)
        let search = app.textFields["settings.activity.searchField"]
        replaceText(search, with: "unmatched.lab.example")
        XCTAssertFalse(row.exists)
        replaceText(search, with: "example.com")
        XCTAssertTrue(row.exists)
        app.buttons["settings.activity.clearButton"].click()
        let confirm = app.buttons["action-button-1"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertFalse(row.exists)
        XCTAssertFalse(app.buttons["settings.activity.clearButton"].isEnabled)
    }
}
