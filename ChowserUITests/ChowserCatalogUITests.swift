import XCTest

final class ChowserCatalogUITests: ChowserUITestCase {
    func testCatalogRequiresExplicitSelectionAndKeepsSignedRulesReadOnly() {
        launchSettingsFixture("Catalog")
        let add = app.buttons["Add Selected"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled)
        let rule = app.checkBoxes["catalog.rule.lab-https"]
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        XCTAssertEqual("\(rule.value ?? "")", "0")
        rule.click()
        XCTAssertTrue(add.isEnabled)
        app.buttons["Clear Selection"].click()
        XCTAssertFalse(add.isEnabled)
        rule.click()
        add.click()
        let summary = app.buttons["action-button-1"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        summary.click()
        let name = app.staticTexts.matching(identifier: "settings.rewrite.name")
        assertCount(1, in: name)
        name.firstMatch.click()
        let signedNote = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "Signed and verified")).firstMatch
        XCTAssertTrue(signedNote.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["settings.rewrite.hostField"].exists)
        let duplicate = app.buttons["settings.rewriteInspector.duplicateButton"]
        reveal(duplicate, in: app.descendants(matching: .any).matching(identifier: "settings.rewriteInspector").firstMatch)
        duplicate.click()
        assertCount(2, in: name)
        XCTAssertTrue(app.textFields["settings.rewrite.hostField"].waitForExistence(timeout: 5))
    }

    func testNativeConsentShowsChangedScopeAndCanBeGrantedThenRevoked() {
        launchSettingsFixture("NativeApps")
        let review = app.staticTexts["settings.nativeApps.lab-native.needsReview"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        let toggle = app.checkBoxes["settings.nativeApps.lab-native.toggle"]
        XCTAssertEqual("\(toggle.value ?? "")", "0")
        app.buttons["settings.nativeApps.lab-native.detailsButton"].click()
        XCTAssertTrue(app.staticTexts["native.lab.example"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["lab:"].exists)
        app.typeKey(.escape, modifierFlags: [])
        toggle.click()
        XCTAssertEqual("\(toggle.value ?? "")", "1")
        XCTAssertFalse(review.exists)
        toggle.click()
        XCTAssertEqual("\(toggle.value ?? "")", "0")
        app.buttons["settings.nativeApps.directoryInfoButton"].click()
        XCTAssertTrue(app.staticTexts["ui-fixture"].waitForExistence(timeout: 5))
    }

    func testMergeReviewMergesOneGroupAndRejectsTheOther() {
        launchSettingsFixture("MergeReview")
        let rows = app.descendants(matching: .any).matching(identifier: "settings.ruleMergeReview.suggestionRow")
        XCTAssertTrue(app.buttons["settings.ruleMergeReview.mergeButton"].firstMatch.waitForExistence(timeout: 5))
        assertCount(2, in: rows)
        app.buttons["settings.ruleMergeReview.mergeButton"].firstMatch.click()
        assertCount(1, in: rows)
        app.buttons["settings.ruleMergeReview.rejectButton"].click()
        assertCount(0, in: rows)
        XCTAssertFalse(app.buttons["settings.ruleMergeReview.acceptAllButton"].isEnabled)
        app.buttons["settings.ruleMergeReview.doneButton"].click()
        assertCount(3, in: app.checkBoxes.matching(identifier: "settings.rule.enabledToggle"))
    }

    func testMergeReviewAcceptAllKeepsOneRulePerGroup() {
        launchSettingsFixture("MergeReview")
        let accept = app.buttons["settings.ruleMergeReview.acceptAllButton"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.click()
        XCTAssertTrue(app.staticTexts["All done"].waitForExistence(timeout: 5))
        app.buttons["settings.ruleMergeReview.doneButton"].click()
        assertCount(2, in: app.checkBoxes.matching(identifier: "settings.rule.enabledToggle"))
    }

    private func launchSettingsFixture(_ name: String) {
        launchTestApp(arguments: ["-UITesting", "-UITesting_ClearData", "-UITesting_MockInstalledBrowsers",
                                  "-UITesting_DisableExternalOpen", "-UITesting_OpenSettings",
                                  "-UITesting_\(name)Fixture"], suiteLabel: name)
    }
}
