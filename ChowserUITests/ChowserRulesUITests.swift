import XCTest

final class ChowserRulesUITests: ChowserUITestCase {
    func testAdvancedRuleValidationRevertsInvalidDraftAndTesterUsesSavedRule() {
        let driver = ChowserAppDriver(app: app)
        driver.openRulesSection()
        driver.openAddRuleSheet()
        driver.addRule(hostPattern: "example.com")
        driver.assertRuleCreated()
        let inspector = app.descendants(matching: .any).matching(identifier: "settings.rules.inspector").firstMatch
        let advanced = app.descendants(matching: .any).matching(identifier: "settings.rule.advancedDisclosure").firstMatch
        reveal(advanced, in: inspector)
        let disclosure = app.disclosureTriangles["Advanced"]
        disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.5)).click()
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 1 OR value == '1'"), object: disclosure)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        let host = app.textFields["settings.rule.hostField"]
        replaceText(host, with: "[")
        let regex = app.switches["settings.rule.regexToggle"]
        reveal(regex, in: inspector)
        regex.click()
        let error = app.staticTexts["settings.rule.hostError"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        let revert = app.buttons["settings.rule.revertButton"]
        reveal(revert, in: inspector)
        revert.click()
        XCTAssertFalse(error.exists)
        reveal(host, in: inspector)
        XCTAssertEqual(host.value as? String, "example.com")
        app.buttons["settings.rules.testButton"].click()
        let tester = app.descendants(matching: .any).matching(identifier: "settings.ruleTester.popover").firstMatch
        XCTAssertTrue(tester.waitForExistence(timeout: 5))
        let input = app.textFields["settings.ruleTester.urlField"]
        replaceText(input, with: "https://example.com/docs")
        let result = app.descendants(matching: .any).matching(identifier: "settings.ruleTester.result").firstMatch
        assertContains("Opens in", in: result)
        replaceText(input, with: "https://unmatched.lab.example/")
        assertContains("No rule matches this link", in: result)
    }

    func testSourceAppConditionCanBeAddedRemovedAndTested() {
        let driver = ChowserAppDriver(app: app)
        driver.openRulesSection()
        driver.openAddRuleSheet()
        driver.addRule(hostPattern: "example.com")
        let inspector = app.descendants(matching: .any).matching(identifier: "settings.rules.inspector").firstMatch
        let add = app.menuButtons["settings.rule.sourceApps"]
        reveal(add, in: inspector)
        add.click()
        app.menuItems["Finder"].click()
        let remove = app.buttons["Remove Finder"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        app.buttons["settings.rules.testButton"].click()
        let input = app.textFields["settings.ruleTester.urlField"]
        let result = app.descendants(matching: .any).matching(identifier: "settings.ruleTester.result").firstMatch
        replaceText(input, with: "https://example.com/docs")
        assertContains("No rule matches this link", in: result)
        app.popUpButtons["settings.ruleTester.sourceAppPicker"].click()
        app.menuItems["Finder"].click()
        assertContains("Opens in", in: result)
        app.typeKey(.escape, modifierFlags: [])
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        reveal(remove, in: inspector)
        remove.click()
        XCTAssertFalse(remove.exists)
        app.buttons["settings.rules.testButton"].click()
        app.popUpButtons["settings.ruleTester.sourceAppPicker"].click()
        app.menuItems["Any app"].click()
        assertContains("Opens in", in: result)
    }

    func testReplayOnboardingCanFinishWithoutDefaultBrowserChange() {
        ChowserAppDriver(app: app).openBackupSection()
        let replay = app.buttons["settings.backup.replayOnboardingButton"]
        reveal(replay, in: app.descendants(matching: .any).matching(identifier: "settings.backupSection").firstMatch)
        replay.click()
        let skip = app.links["onboarding.notNow"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.click()
        XCTAssertFalse(skip.exists)
        XCTAssertTrue(app.windows["Chowser Settings"].exists)
    }
}
