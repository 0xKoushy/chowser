import XCTest

final class ChowserSettingsUITests: ChowserUITestCase {
    func testRewriteChangesOnlyMatchingLinksAndSupportsUndo() throws {
        openRewrites()
        createHTTPSRewrite()
        assertCount(1, in: rewriteNames)
        app.buttons["settings.rewrites.testButton"].click()
        let input = app.textFields["settings.rewriteTester.urlField"]
        let result = app.descendants(matching: .any).matching(identifier: "settings.rewriteTester.result").firstMatch
        replaceText(input, with: "http://example.com/docs?keep=1")
        assertContains("https://example.com/docs?keep=1", in: result)
        replaceText(input, with: "https://other.example/")
        assertContains("No rewrites change this link", in: result)
        replaceText(input, with: "https://")
        assertContains("isn’t a complete link", in: result)
        app.typeKey(.escape, modifierFlags: [])

        let inspector = app.descendants(matching: .any).matching(identifier: "settings.rewriteInspector").firstMatch
        let duplicate = app.buttons["settings.rewriteInspector.duplicateButton"]
        reveal(duplicate, in: inspector)
        duplicate.click()
        assertCount(2, in: rewriteNames)
        app.buttons["settings.rewrites.footerRemoveButton"].click()
        assertCount(1, in: rewriteNames)
        app.links["settings.rewrites.undoDeleteButton"].click()
        assertCount(2, in: rewriteNames)
    }

    func testRewriteInvalidRegexIsNotSavedAndCanBeReverted() throws {
        openRewrites()
        createHTTPSRewrite()
        let inspector = app.descendants(matching: .any).matching(identifier: "settings.rewriteInspector").firstMatch
        let host = app.textFields["settings.rewrite.hostField"]
        replaceText(host, with: "[")
        let regex = app.switches["settings.rewrite.regexToggle"]
        reveal(regex, in: inspector)
        regex.click()
        let error = app.descendants(matching: .any).matching(identifier: "settings.rewrite.error").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        let revert = app.buttons["settings.rewrite.revertButton"]
        reveal(revert, in: inspector)
        revert.click()
        reveal(host, in: inspector)
        XCTAssertEqual(host.value as? String, "example.com")
        XCTAssertFalse(error.exists)
    }

    func testPrivacyLookupSwitchGatesShortenerManagement() throws {
        ChowserAppDriver(app: app).clickSidebarItem(identifier: "settings.sidebar.privacy")
        let online = app.checkBoxes["settings.behavior.networkLookupsToggle"]
        let domain = app.textFields["settings.behavior.addShortenerHostField"]
        XCTAssertTrue(online.waitForExistence(timeout: 5))
        XCTAssertEqual("\(online.value ?? "")", "0")
        XCTAssertFalse(domain.isEnabled)
        online.click()
        XCTAssertTrue(domain.isEnabled)
        replaceText(domain, with: "short.lab.example")
        app.buttons["settings.privacy.addShortenerHostButton"].click()
        let added = app.staticTexts["short.lab.example"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        app.buttons["settings.privacy.removeShortenerHost"].click()
        XCTAssertFalse(added.exists)
        online.click()
        XCTAssertEqual("\(online.value ?? "")", "0")
        XCTAssertFalse(domain.isEnabled)
    }

    func testNativeAppsDirectoryDetailsAreAvailableWithoutRefreshing() throws {
        ChowserAppDriver(app: app).clickSidebarItem(identifier: "settings.sidebar.nativeApps")
        let page = app.descendants(matching: .any).matching(identifier: "settings.nativeAppsSection").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        app.buttons["settings.nativeApps.directoryInfoButton"].click()
        let info = app.descendants(matching: .any).matching(identifier: "settings.nativeApps.directoryInfo").firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.nativeApps.refreshButton"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(info.exists)
    }

    private var rewriteNames: XCUIElementQuery {
        app.staticTexts.matching(identifier: "settings.rewrite.name")
    }

    private func openRewrites() {
        ChowserAppDriver(app: app).clickSidebarItem(identifier: "settings.sidebar.rewrites")
        XCTAssertTrue(app.buttons["settings.addRewriteButton"].waitForExistence(timeout: 5))
    }

    private func createHTTPSRewrite() {
        app.buttons["settings.addRewriteButton"].click()
        let root = app.descendants(matching: .any).matching(identifier: "settings.addRewrite.root").firstMatch
        let save = app.buttons["settings.addRewrite.confirmButton"]
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        replaceText(app.textFields["settings.addRewrite.nameField"], with: "Upgrade lab HTTPS")
        replaceText(app.textFields["settings.addRewrite.hostField"], with: "example.com")
        let force = root.checkBoxes["Force scheme"]
        reveal(force, in: root)
        force.click()
        XCTAssertTrue(save.isEnabled)
        save.click()
        XCTAssertTrue(app.textFields["settings.rewrite.hostField"].waitForExistence(timeout: 5))
    }
}
