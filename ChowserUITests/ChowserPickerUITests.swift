import XCTest

final class ChowserPickerUITests: ChowserUITestCase {
    func testCreateRoutingRuleFromPickerRejectsBlankNameAndSavesHost() {
        launchClassicPickerFixture(suiteLabel: "picker-create-rule")
        let configure = app.buttons["picker.configureRuleButton"]
        XCTAssertTrue(configure.waitForExistence(timeout: 5))
        configure.click()
        let name = app.textFields["Enter name..."]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let save = app.buttons["Save Rule"]
        replaceText(name, with: " ")
        XCTAssertFalse(save.isEnabled)
        XCTAssertEqual(observedOpenInvocationCount(), 0, "Typing in the rule form must not launch a browser")
        replaceText(name, with: "Lab picker route")
        XCTAssertTrue(save.isEnabled)
        app.checkBoxes["Use Private Mode"].click()
        save.click()
        XCTAssertFalse(app.dialogs["picker"].exists)
        let driver = ChowserAppDriver(app: app)
        driver.openSettings()
        driver.openRulesSection()
        let rows = app.checkBoxes.matching(identifier: "settings.rule.enabledToggle")
        assertCount(1, in: rows)
        app.outlines["settings.rules.table"].staticTexts["example.com"].click()
        let savedName = app.textFields["settings.rule.nameField"]
        XCTAssertTrue(savedName.waitForExistence(timeout: 5))
        XCTAssertEqual(savedName.value as? String, "Lab picker route")
        XCTAssertEqual(app.textFields["settings.rule.hostField"].value as? String, "example.com")
        XCTAssertEqual("\(app.switches["settings.rule.privateToggle"].value ?? "")", "1")
    }

    func testIncomingBatchAllowsTwoSuccessiveBrowserChoices() throws {
        launchTestApp(arguments: [
            "-UITesting", "-UITesting_ClearData", "-UITesting_IconsPickerFixture",
            "-UITesting_DisableExternalOpen", "-UITesting_OpenURLBatch",
            "-ApplePersistenceIgnoreState", "YES",
        ], suiteLabel: "batch-two-choices")

        let picker = app.dialogs["picker"]
        let destination = picker.staticTexts["picker.urlDisplay"]
        assertValue("first-batch.example", in: destination)
        picker.buttons["Open in Safari"].click()
        XCTAssertTrue(waitForOpenInvocationCount(1))

        assertValue("second-batch.example", in: destination)
        picker.buttons["Open in Safari"].click()
        XCTAssertTrue(waitForOpenInvocationCount(2))
        XCTAssertFalse(picker.exists, "The last choice should close the picker.")

        struct HistoryURL: Decodable { let url: URL }
        let file = logsDirectory.appendingPathComponent("link-history.json")
        let orderedHistory = NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: file),
                  let entries = try? JSONDecoder().decode([HistoryURL].self, from: data) else { return false }
            return entries.reversed().map(\.url.absoluteString) == [
                "https://first-batch.example/", "https://second-batch.example/",
            ]
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: orderedHistory, object: nil)], timeout: 5),
                       .completed, "Both choices should be recorded once, in delivery order.")
    }

    private func assertValue(_ value: String, in element: XCUIElement,
                             file: StaticString = #filePath, line: UInt = #line) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, file: file, line: line)
    }
}
