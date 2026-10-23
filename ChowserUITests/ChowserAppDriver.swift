import XCTest

struct ChowserAppDriver {
    let app: XCUIApplication

    var pickerSettingsButton: XCUIElement { app.buttons["picker.openSettingsButton"] }
    var pickerRoot: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "picker.urlDisplay").firstMatch
    }
    var settingsAddBrowserButton: XCUIElement { app.buttons["settings.addBrowserButton"] }

    /// One name label per row of the browsers list (in picker order).
    var browserRows: XCUIElementQuery {
        app.staticTexts.matching(identifier: "settings.browser.name")
    }

    /// The table footer's "-" button; removes the selected browser.
    var browserRemoveButton: XCUIElement {
        app.buttons["settings.browser.removeButton"]
    }

    var addSheetRoot: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settings.addSheet.root").firstMatch
    }

    var lastOpenedBrowserText: XCUIElement {
        app.staticTexts["picker.lastOpenedBrowser"]
    }

    var addSheetConfirmButton: XCUIElement {
        app.buttons["settings.addSheet.addButton"]
    }

    var firstPickerBrowserRow: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "picker.browserRow").firstMatch
    }

    var sendToIPhoneButton: XCUIElement { app.buttons["picker.sendToIPhoneButton"] }
    var iphoneAirDropButton: XCUIElement { app.buttons["iphoneAction.airDropButton"] }
    var iphoneShowQRCodeButton: XCUIElement { app.buttons["iphoneAction.showQRCodeButton"] }
    var iphoneCopyURLButton: XCUIElement { app.buttons["iphoneAction.copyURLButton"] }
    var iphoneHandoffStatusText: XCUIElement { app.staticTexts["iphoneAction.handoffStatusText"] }
    var iphoneQRCloseButton: XCUIElement { app.buttons["iphoneQR.closeButton"] }

    var iphoneQRSheet: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "iphoneQR.sheet").firstMatch
    }

    var iphoneQRImage: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "iphoneQR.image").firstMatch
    }

    var iphoneQRURLText: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "iphoneQR.urlText").firstMatch
    }

    var addRuleButton: XCUIElement {
        app.buttons["settings.addRuleButton"]
    }

    var ruleInspectorHostField: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settings.rule.hostField").firstMatch
    }

    var rulesTable: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settings.rules.table").firstMatch
    }

    var firstBrowserNameValue: String {
        guard browserRows.count > 0 else { return "" }
        let label = browserRows.element(boundBy: 0)
        if let value = label.value as? String, !value.isEmpty { return value }
        return label.label
    }

    func assertPickerVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(pickerRoot.waitForExistence(timeout: 5), "Picker UI should be visible.", file: file, line: line)
    }

    func assertBrowserSelectionRecorded(file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value != 'none'")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: lastOpenedBrowserText)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Picker should record selected browser in UI-test mode.", file: file, line: line)
    }

    func assertSettingsVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(settingsAddBrowserButton.waitForExistence(timeout: 5), "Settings UI should remain visible.", file: file, line: line)
    }

    func openSettings() {
        if settingsAddBrowserButton.waitForExistence(timeout: 5) {
            return
        }

        if pickerSettingsButton.waitForExistence(timeout: 5) {
            pickerSettingsButton.click()
            XCTAssertTrue(settingsAddBrowserButton.waitForExistence(timeout: 5), "Settings did not open after tapping picker gear button.")
            return
        }

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settingsAddBrowserButton.waitForExistence(timeout: 5), "Settings UI did not appear.")
    }

    func openBrowsersSection() {
        clickSidebarItem(identifier: "settings.sidebar.browsers")
    }

    func openGeneralSection() {
        clickSidebarItem(identifier: "settings.sidebar.general")
    }

    func openRulesSection() {
        clickSidebarItem(identifier: "settings.sidebar.rules")
    }

    func openBackupSection() {
        clickSidebarItem(identifier: "settings.sidebar.backup")
    }

    func openAddBrowserSheet() {
        let addButton = app.buttons["settings.addBrowserButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add browser button not found.")
        addButton.click()

        XCTAssertTrue(addSheetRoot.waitForExistence(timeout: 5), "Add browser sheet should open.")
    }

    func addFirstBrowserOption() {
        // Already-added browsers are listed too (checked + disabled); pick the first addable one.
        let options = app.descendants(matching: .any).matching(identifier: "settings.addSheet.option")
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5), "No browser option found.")
        let firstOption = options.matching(NSPredicate(format: "isEnabled == true")).firstMatch
        XCTAssertTrue(firstOption.exists, "No addable browser option found.")
        firstOption.click()

        XCTAssertTrue(addSheetConfirmButton.waitForExistence(timeout: 5), "Add Browsers button not found.")
        addSheetConfirmButton.click()

        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: addSheetRoot)
        _ = XCTWaiter.wait(for: [expectation], timeout: 5)
    }

    func resetToFreshSetup() {
        let resetButton = app.buttons["settings.resetButton"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 5), "Reset button not found in Backup & Advanced section.")
        let detail = app.scrollViews.containing(.button, identifier: "settings.resetButton").firstMatch
        for _ in 0..<8 where !resetButton.isHittable { detail.swipeUp() }
        XCTAssertTrue(resetButton.isHittable, "Reset should be reachable by scrolling the detail pane.")
        resetButton.click()

        let confirmButton = app.buttons["action-button-1"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Reset confirmation not shown.")
        confirmButton.click()
    }

    /// Adds a rule inline: the "+" button inserts a row and focuses the inspector's
    /// "Link matches" field (there is no add-rule sheet anymore).
    func openAddRuleSheet() {
        XCTAssertTrue(addRuleButton.waitForExistence(timeout: 5), "Add rule button not found.")
        addRuleButton.click()
        XCTAssertTrue(ruleInspectorHostField.waitForExistence(timeout: 5), "Rule inspector should open for the new rule.")
    }

    func addRule(hostPattern: String) {
        let hostField = ruleInspectorHostField
        XCTAssertTrue(hostField.waitForExistence(timeout: 5), "Link matches field not found.")
        hostField.click()
        hostField.typeText(hostPattern)
        // Rules save as soon as they validate; Tab moves focus without activating a default button.
        app.typeKey(.tab, modifierFlags: [])
    }

    func assertRuleCreated(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(rulesTable.waitForExistence(timeout: 5), "Rules table should exist.", file: file, line: line)
        let error = app.descendants(matching: .any).matching(identifier: "settings.rule.hostError").firstMatch
        XCTAssertFalse(error.exists, "The new rule should be valid.", file: file, line: line)
        // SwiftUI's Table surfaces as an accessibility Outline whose rows are OutlineRows.
        let predicate = NSPredicate(format: "count > 0")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: rulesTable.outlineRows)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, "Expected at least one routing rule row.", file: file, line: line)
    }

    func clickSidebarItem(identifier: String) {
        let candidates: [XCUIElement] = [
            app.buttons[identifier],
            app.staticTexts[identifier],
            app.cells[identifier],
            app.otherElements[identifier],
        ]

        for candidate in candidates where candidate.waitForExistence(timeout: 1) {
            candidate.click()
            return
        }

        XCTFail("Sidebar item \(identifier) not found.")
    }
}
