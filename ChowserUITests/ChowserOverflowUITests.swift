import XCTest

final class ChowserOverflowUITests: ChowserUITestCase {
    func testMoreBrowsersCanBeCancelledAndSelectedWithTheKeyboard() {
        for (fixture, privately) in [("Radial", false), ("Minimal", true)] {
            var arguments = ["-UITesting", "-UITesting_ClearData", "-UITesting_\(fixture)PickerFixture",
                             "-UITesting_OverflowPickerFixture", "-UITesting_DisableExternalOpen",
                             "-UITesting_DefaultURL", "-UITesting_OpenPicker"]
            if privately { arguments.append("-UITesting_PrivatePicker") }
            launchTestApp(arguments: arguments, suiteLabel: "overflow-\(fixture)", mouseLocation: CGPoint(x: 540, y: 440))
            let more = app.buttons["More browsers and profiles"]
            XCTAssertTrue(more.waitForExistence(timeout: 5))
            more.click()
            let overflow = app.descendants(matching: .any).matching(identifier: "picker.moreList").firstMatch
            XCTAssertTrue(overflow.waitForExistence(timeout: 5))
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertFalse(overflow.exists)
            XCTAssertEqual(observedOpenInvocationCount(), 0)
            XCTAssertTrue(more.exists)
            more.click()
            let firstName = fixture == "Radial" ? "Arc" : "Zen"
            let nextName = fixture == "Radial" ? "Brave" : "Firefox - Personal"
            let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open in \(firstName)")).firstMatch
            let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open in \(nextName)")).firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            first.hover()
            app.dialogs["picker"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.05)).hover()
            app.typeKey(.downArrow, modifierFlags: [])
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "selected"), object: next)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
            if privately { XCTAssertTrue((next.value as? String ?? "").contains("private mode")) }
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(waitForOpenInvocationCount(1))
            XCTAssertFalse(app.dialogs["picker"].exists)
            if !privately { assertRecordedBrowser("com.brave.Browser") }
        }
    }

    private func assertRecordedBrowser(_ bundleID: String) {
        let file = logsDirectory.appendingPathComponent("link-history.json")
        let recorded = NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: file),
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let outcome = entries.first?["outcome"] as? [String: Any],
                  let browser = outcome["browser"] as? [String: Any] else { return false }
            return browser["bundleID"] as? String == bundleID && entries.count == 1
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: recorded, object: nil)], timeout: 5), .completed)
    }
}
