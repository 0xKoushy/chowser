import XCTest
import AppKit

final class ChowserUITests: ChowserUITestCase {
    func testIncomingURLBatchOpensDistinctLinksInOrder() throws {
        launchTestApp(arguments: [
            "-UITesting",
            "-UITesting_ClearData",
            "-UITesting_IconsPickerFixture",
            "-UITesting_DisableExternalOpen",
            "-UITesting_AutoRouteBatchFixture",
            "-UITesting_OpenURLBatch",
        ], suiteLabel: "incoming-batch")

        XCTAssertTrue(waitForOpenInvocationCount(2, timeout: 8), "One delegate batch must open both links.")

        struct HistoryURL: Decodable { let url: URL }
        let historyFile = logsDirectory.appendingPathComponent("link-history.json")
        let deadline = Date().addingTimeInterval(5)
        var recordedURLs: [URL] = []
        repeat {
            if let data = try? Data(contentsOf: historyFile),
               let entries = try? JSONDecoder().decode([HistoryURL].self, from: data) {
                recordedURLs = entries.map(\.url)
            }
            if recordedURLs.count == 2 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        XCTAssertEqual(recordedURLs.reversed().map(\.absoluteString), [
            "https://first-batch.example/",
            "https://second-batch.example/",
        ])
    }

    func testAppearancePreviewStaysVisibleWhileEditingLowerSettings() throws {
        let appearanceButton = app.buttons["settings.sidebar.appearance"]
        XCTAssertTrue(appearanceButton.waitForExistence(timeout: 5))
        appearanceButton.click()

        let previewTitle = app.staticTexts["Preview"]
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(previewTitle.isHittable)

        let accentLabel = app.staticTexts["Accent Color"]
        let scrollView = app.scrollViews["settings.appearance.controls"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        for _ in 0..<4 where !accentLabel.isHittable { scrollView.swipeUp() }
        XCTAssertTrue(accentLabel.isHittable, "Lower appearance controls should be reachable.")
        XCTAssertTrue(previewTitle.isHittable, "The live preview should remain visible while editing lower appearance controls.")
    }

    func testAppearancePreviewShowsLinkMetadataInClassicPicker() throws {
        let appearanceButton = app.buttons["settings.sidebar.appearance"]
        XCTAssertTrue(appearanceButton.waitForExistence(timeout: 5))
        appearanceButton.click()

        let linkPreview = app.staticTexts[
            "Page titles and descriptions appear here before you choose a browser."
        ]
        XCTAssertTrue(
            linkPreview.waitForExistence(timeout: 5),
            "The Appearance sample should demonstrate the enabled Link Preview in Icons mode."
        )
    }

    func testAppearanceUsesPinnedTopPreviewAtNarrowWidth() throws {
        launchTestApp(arguments: [
            "-UITesting",
            "-UITesting_ClearData",
            "-UITesting_MockInstalledBrowsers",
            "-UITesting_DisableExternalOpen",
            "-UITesting_DefaultURL",
            "-UITesting_OpenSettings",
            "-UITesting_NarrowSettings",
        ], suiteLabel: "narrow")

        let appearanceButton = app.buttons["settings.sidebar.appearance"]
        XCTAssertTrue(appearanceButton.waitForExistence(timeout: 5))
        appearanceButton.click()

        let preview = app.descendants(matching: .any).matching(identifier: "settings.appearance.preview").firstMatch
        let controls = app.scrollViews["settings.appearance.controls"]
        let layoutPicker = app.descendants(matching: .any).matching(identifier: "settings.appearance.layoutPicker").firstMatch

        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        XCTAssertTrue(layoutPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.isHittable)
        // A segmented control's own group element is never the topmost hit target (its
        // segments are), so assert a segment is reachable instead.
        XCTAssertTrue(layoutPicker.radioButtons["Icons"].isHittable)
        XCTAssertLessThanOrEqual(preview.frame.maxY, controls.frame.minY + 2, "The compact preview should be pinned above the independently scrolling controls.")

        let accentLabel = app.staticTexts["Accent Color"]
        for _ in 0..<4 where !accentLabel.isHittable { controls.swipeUp() }
        XCTAssertTrue(accentLabel.isHittable, "Lower appearance controls should remain reachable in the narrow layout.")
        XCTAssertTrue(preview.isHittable, "The compact preview should remain visible while narrow controls scroll.")
    }

    func testFallbackPickerLivesOnRulesPageAndDefaultsToPicker() throws {
        let ui = ChowserAppDriver(app: app)
        ui.openSettings()
        ui.openRulesSection()

        let fallbackPicker = app.descendants(matching: .any)
            .matching(identifier: "settings.rules.fallbackPicker")
            .firstMatch
        XCTAssertTrue(fallbackPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(fallbackPicker.value as? String, "Show the picker")
    }

    func testRadialPickerUsesCursorAsCenterAndDirectionSelectsBrowser() throws {
        let screenFrame = NSScreen.main!.frame
        launchTestApp(arguments: [
            "-UITesting",
            "-UITesting_ClearData",
            "-UITesting_RadialPickerFixture",
            "-UITesting_DisableExternalOpen",
            "-UITesting_DefaultURL",
            "-UITesting_OpenPicker",
            "-ApplePersistenceIgnoreState",
            "YES",
        ], suiteLabel: "radial", mouseLocation: CGPoint(x: screenFrame.midX, y: screenFrame.midY))

        let radial = app.descendants(matching: .any).matching(identifier: "picker.radial").firstMatch
        XCTAssertTrue(radial.waitForExistence(timeout: 5), "Radial picker should be visible.")
        // Compare against the launch anchor, not the live pointer: XCTest can move the
        // pointer again while establishing its accessibility session after the picker is placed.
        let launchAnchor = CGPoint(x: screenFrame.midX, y: screenFrame.maxY - screenFrame.midY)
        XCTAssertEqual(radial.frame.midX, launchAnchor.x, accuracy: 3, "Cursor must be the radial picker's horizontal center.")
        XCTAssertEqual(radial.frame.midY, launchAnchor.y, accuracy: 3, "Cursor must be the radial picker's vertical center.")
        XCTAssertEqual(radial.frame.width, radial.frame.height, accuracy: 1, "The radial picker canvas must stay square.")
        XCTAssertLessThan(radial.frame.width, 300, "Two destinations should use the compact radial wheel, not the maximum canvas.")

        let safariButton = app.buttons["Open in Safari"]
        let chromeButton = app.buttons["Open in Chrome - Work"]
        XCTAssertTrue(safariButton.waitForExistence(timeout: 2))
        XCTAssertTrue(chromeButton.waitForExistence(timeout: 2))
        XCTAssertEqual(safariButton.value as? String, "not selected", "The cursor dead zone must start with no destination selected.")
        XCTAssertEqual(chromeButton.value as? String, "not selected", "The cursor dead zone must start with no destination selected.")

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(radial.exists, "Return must not activate an invisible destination while the cursor is in the dead zone.")

        // With two destinations browser 1 is above center and browser 2 is below center.
        // Moving down from the original cursor anchor must select Chrome, not merely hover a button.
        radial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).hover()
        let directionSelected = NSPredicate(format: "value == 'selected'")
        let selectionResult = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: directionSelected, object: chromeButton)],
            timeout: 2
        )
        XCTAssertEqual(selectionResult, .completed, "Pointer direction should visibly select Chrome before confirmation.")
        chromeButton.click()

        let pickerDismissed = NSPredicate(format: "exists == false")
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: pickerDismissed, object: radial)], timeout: 3)
        XCTAssertEqual(result, .completed, "Activating the direction-selected Chrome destination should dismiss the radial picker.")
        XCTAssertTrue(waitForOpenInvocationCount(1), "Radial pointer activation should launch exactly once.")
    }

    func testClassicPickerShowsPathAndUsesExplicitURLEditAction() throws {
        let layouts = [
            ("icons-destination", "-UITesting_IconsPickerFixture"),
            ("list-destination", "-UITesting_ListPickerFixture"),
        ]

        for (label, fixture) in layouts {
            launchTestApp(arguments: [
                "-UITesting",
                "-UITesting_ClearData",
                fixture,
                "-UITesting_DisableExternalOpen",
                "-UITesting_SensitiveURL",
                "-UITesting_OpenPicker",
                "-ApplePersistenceIgnoreState",
                "YES",
            ], suiteLabel: label)

            let path = app.staticTexts["picker.destinationPath"]
            XCTAssertTrue(path.waitForExistence(timeout: 5), "Expected destination path in \(label).")
            XCTAssertEqual(path.value as? String, "/account/reset password")
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "secret")).count, 0)

            let editButton = app.buttons["picker.urlEditTrigger"]
            XCTAssertTrue(editButton.waitForExistence(timeout: 2))
            editButton.click()

            let editField = app.textFields["picker.urlEditField"]
            XCTAssertTrue(editField.waitForExistence(timeout: 2))
            XCTAssertEqual(
                editField.value as? String,
                "https://example.com/account/reset%20password?token=secret#confirm"
            )
        }
    }

    func testFailedBrowserLaunchKeepsLinkInPicker() throws {
        launchTestApp(arguments: [
            "-UITesting",
            "-UITesting_ClearData",
            "-UITesting_IconsPickerFixture",
            "-UITesting_DisableExternalOpen",
            "-UITesting_SimulateExternalOpenFailure",
            "-UITesting_DefaultURL",
            "-UITesting_OpenPicker",
            "-ApplePersistenceIgnoreState",
            "YES",
        ], suiteLabel: "failed-launch")

        let destination = app.staticTexts["picker.urlDisplay"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        app.buttons["Open in Safari"].click()
        XCTAssertTrue(app.staticTexts["picker.launchError"].waitForExistence(timeout: 5))
        XCTAssertTrue(destination.exists, "The link must remain available after the launch failure.")
        XCTAssertTrue(waitForOpenInvocationCount(0))
    }

    func testPrivateModeIsVisibleAndAnnouncedInEveryPickerLayout() throws {
        let layouts = [
            ("icons", "-UITesting_IconsPickerFixture", "picker.urlDisplay"),
            ("list", "-UITesting_ListPickerFixture", "picker.urlDisplay"),
            ("radial-private", "-UITesting_RadialPickerFixture", "picker.radial"),
            ("minimal", "-UITesting_MinimalPickerFixture", "picker.minimal"),
        ]

        for (label, fixture, rootIdentifier) in layouts {
            launchTestApp(arguments: [
                "-UITesting",
                "-UITesting_ClearData",
                fixture,
                "-UITesting_PrivatePicker",
                "-UITesting_DisableExternalOpen",
                "-UITesting_DefaultURL",
                "-UITesting_OpenPicker",
                "-ApplePersistenceIgnoreState",
                "YES",
            ], suiteLabel: label)

            let root = app.descendants(matching: .any).matching(identifier: rootIdentifier).firstMatch
            XCTAssertTrue(root.waitForExistence(timeout: 5), "Expected \(label) picker.")

            let indicator = app.descendants(matching: .any).matching(identifier: "picker.privateModeIndicator").firstMatch
            XCTAssertTrue(indicator.waitForExistence(timeout: 2), "Expected visible private mode in \(label).")
            XCTAssertTrue(app.buttons["Open in Safari privately"].waitForExistence(timeout: 2), "Expected private launch announcement in \(label).")
        }

        for (label, fixture) in [
            ("radial-overflow-private", "-UITesting_RadialPickerFixture"),
            ("minimal-overflow-private", "-UITesting_MinimalPickerFixture"),
        ] {
            launchTestApp(arguments: [
                "-UITesting",
                "-UITesting_ClearData",
                fixture,
                "-UITesting_OverflowPickerFixture",
                "-UITesting_PrivatePicker",
                "-UITesting_DisableExternalOpen",
                "-UITesting_DefaultURL",
                "-UITesting_OpenPicker",
                "-ApplePersistenceIgnoreState",
                "YES",
            ], suiteLabel: label)

            let moreButton = app.buttons["More browsers and profiles"]
            XCTAssertTrue(moreButton.waitForExistence(timeout: 5), "Expected More in \(label).")
            moreButton.click()

            let overflow = app.descendants(matching: .any).matching(identifier: "picker.moreList").firstMatch
            XCTAssertTrue(overflow.waitForExistence(timeout: 2), "Expected overflow in \(label).")
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "picker.privateModeIndicator").firstMatch.waitForExistence(timeout: 2))
            XCTAssertTrue(app.buttons["Open in Zen privately"].waitForExistence(timeout: 2))
        }
    }

    func testQuickPickersSupportImmediateKeyboardSelectionAndLaunch() throws {
        for (label, fixture, arrowCount) in [
            ("radial-keyboard", "-UITesting_RadialPickerFixture", 2),
            ("minimal-keyboard", "-UITesting_MinimalPickerFixture", 1),
        ] {
            launchTestApp(arguments: [
                "-UITesting",
                "-UITesting_ClearData",
                fixture,
                "-UITesting_DisableExternalOpen",
                "-UITesting_DefaultURL",
                "-UITesting_OpenPicker",
                "-ApplePersistenceIgnoreState",
                "YES",
            ], suiteLabel: label)

            let chromeButton = app.buttons["Open in Chrome - Work"]
            XCTAssertTrue(chromeButton.waitForExistence(timeout: 5))
            for _ in 0..<arrowCount { app.typeKey(.rightArrow, modifierFlags: []) }
            XCTAssertEqual(chromeButton.value as? String, "selected", "Arrow selection should update immediately in \(label).")

            let picker = app.descendants(matching: .any)
                .matching(identifier: fixture.contains("Radial") ? "picker.radial" : "picker.minimal")
                .firstMatch
            app.typeKey(.return, modifierFlags: [])

            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: picker)],
                    timeout: 5
                ),
                .completed,
                "Return should launch the selected browser and dismiss \(label)."
            )
            XCTAssertTrue(waitForOpenInvocationCount(1), "Return should launch exactly once in \(label).")
        }
    }

    func testMinimalPickerHoverTracksPointerAndLaunchesOnce() throws {
        launchTestApp(arguments: [
            "-UITesting",
            "-UITesting_ClearData",
            "-UITesting_MinimalPickerFixture",
            "-UITesting_DisableExternalOpen",
            "-UITesting_DefaultURL",
            "-UITesting_OpenPicker",
            "-ApplePersistenceIgnoreState",
            "YES",
        ], suiteLabel: "minimal-hover")

        let picker = app.descendants(matching: .any).matching(identifier: "picker.minimal").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
        let chromeButton = app.buttons["Open in Chrome - Work"]
        XCTAssertTrue(chromeButton.waitForExistence(timeout: 5), app.debugDescription)
        chromeButton.hover()
        XCTAssertEqual(chromeButton.value as? String, "selected")
        chromeButton.click()
        XCTAssertTrue(waitForOpenInvocationCount(1), "Minimal pointer activation should launch exactly once.")
    }

    func testQuickPickerDragSelectionLaunchesOnce() throws {
        for (label, fixture, rootIdentifier) in [
            ("radial-drag", "-UITesting_RadialPickerFixture", "picker.radial"),
            ("minimal-drag", "-UITesting_MinimalPickerFixture", "picker.minimal"),
        ] {
            launchTestApp(arguments: [
                "-UITesting",
                "-UITesting_ClearData",
                fixture,
                "-UITesting_DisableExternalOpen",
                "-UITesting_DefaultURL",
                "-UITesting_OpenPicker",
                "-ApplePersistenceIgnoreState",
                "YES",
            ], suiteLabel: label, mouseLocation: CGPoint(x: 360, y: 380))

            let picker = app.descendants(matching: .any).matching(identifier: rootIdentifier).firstMatch
            let safariButton = app.buttons["Open in Safari"]
            let chromeButton = app.buttons["Open in Chrome - Work"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertTrue(safariButton.waitForExistence(timeout: 2))
            XCTAssertTrue(chromeButton.waitForExistence(timeout: 2))

            let start = (rootIdentifier == "picker.radial" ? picker : safariButton)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = chromeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.click(forDuration: 0.1, thenDragTo: end)

            XCTAssertTrue(waitForOpenInvocationCount(1), "Drag activation should launch exactly once in \(label).")
            XCTAssertFalse(picker.exists, "Drag activation should dismiss \(label).")
        }
    }

    func testEmptyPickerOffersDirectSettingsRecovery() throws {
        launchTestApp(arguments: [
            "-UITesting",
            "-UITesting_ClearData",
            "-UITesting_EmptyPickerFixture",
            "-UITesting_DisableExternalOpen",
            "-UITesting_DefaultURL",
            "-UITesting_OpenPicker",
            "-ApplePersistenceIgnoreState",
            "YES",
        ], suiteLabel: "empty-picker")

        let settingsButton = app.buttons["picker.openSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), app.debugDescription)
        settingsButton.click()

        XCTAssertTrue(app.buttons["settings.addBrowserButton"].waitForExistence(timeout: 5))
    }

    func testSettingsDeleteButtonDoesNotCloseSettingsWindow() throws {
        let ui = ChowserAppDriver(app: app)

        ui.openSettings()
        ui.assertSettingsVisible()

        if ui.browserRows.count < 2 {
            ui.openAddBrowserSheet()
            ui.addFirstBrowserOption()
        }

        XCTAssertGreaterThanOrEqual(ui.browserRows.count, 2, "Need at least two rows to verify deletion.")

        ui.browserRows.element(boundBy: 1).click()
        XCTAssertTrue(ui.browserRemoveButton.waitForExistence(timeout: 5), "Remove button not found.")
        ui.browserRemoveButton.click()
        ui.assertSettingsVisible()
    }

    func testCommandClickSelectsTwoBrowsersAndRemovingThemAsksFirst() throws {
        let ui = ChowserAppDriver(app: app)

        ui.openSettings()
        ui.assertSettingsVisible()

        while ui.browserRows.count < 3 {
            let before = ui.browserRows.count
            ui.openAddBrowserSheet()
            ui.addFirstBrowserOption()
            if ui.browserRows.count == before { break }
        }
        let startCount = ui.browserRows.count
        try XCTSkipIf(startCount < 3, "Need at least three browsers to remove two and keep one.")

        ui.browserRows.element(boundBy: 0).click()
        XCUIElement.perform(withKeyModifiers: .command) {
            ui.browserRows.element(boundBy: 1).click()
        }

        let summary = app.descendants(matching: .any).matching(identifier: "settings.browsers.multiSelectSummary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "Selecting two browsers should show the multi-select summary.")

        ui.browserRemoveButton.click()

        let confirm = app.buttons["settings.confirmDelete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Removing should ask for confirmation first.")
        XCTAssertEqual(ui.browserRows.count, startCount, "Nothing should be removed before confirming.")

        confirm.click()

        let predicate = NSPredicate(format: "count == %d", startCount - 2)
        let removed = XCTNSPredicateExpectation(predicate: predicate, object: ui.browserRows)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed, "Both selected browsers should be gone.")
        ui.assertSettingsVisible()
    }

    func testResetToFreshSetupRestoresFirstLaunchState() throws {
        let ui = ChowserAppDriver(app: app)

        ui.openSettings()
        ui.assertSettingsVisible()

        ui.openAddBrowserSheet()
        ui.addFirstBrowserOption()
        XCTAssertGreaterThanOrEqual(ui.browserRows.count, 2, "Add browser should increase browser list size.")

        ui.openBackupSection()
        ui.resetToFreshSetup()
        ui.openBrowsersSection()

        XCTAssertEqual(ui.browserRows.count, 1, "Fresh setup should restore one default browser.")
        XCTAssertTrue(ui.firstBrowserNameValue.localizedCaseInsensitiveContains("Safari"))
    }

    func testPickerSelectionClearsPendingURL() throws {
        launchClassicPickerFixture(suiteLabel: "picker-selection")
        let ui = ChowserAppDriver(app: app)
        ui.assertPickerVisible()
        XCTAssertTrue(ui.lastOpenedBrowserText.waitForExistence(timeout: 3), "Expected picker selection marker before choosing a browser.")

        XCTAssertTrue(ui.firstPickerBrowserRow.waitForExistence(timeout: 3), "Expected at least one picker browser row.")
        ui.firstPickerBrowserRow.click()

        ui.assertBrowserSelectionRecorded()
    }

    func testDismissedLinkAppearsInActivity() throws {
        launchClassicPickerFixture(suiteLabel: "activity-dismissed")
        let ui = ChowserAppDriver(app: app)
        ui.assertPickerVisible()

        app.typeKey(.escape, modifierFlags: [])
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: ui.pickerRoot)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "Escape should dismiss the picker.")
        // Let the debounced history write land before relaunching.
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        // Relaunch without ClearData: the history file must survive and show the dismissal.
        launchTestApp(arguments: [
            "-UITesting",
            "-UITesting_MockInstalledBrowsers",
            "-UITesting_DisableExternalOpen",
            "-UITesting_OpenSettings",
        ], suiteLabel: "activity-dismissed-settings")
        ui.openSettings()
        ui.clickSidebarItem(identifier: "settings.sidebar.activity")

        let dismissedRow = app.descendants(matching: .any)
            .matching(identifier: "settings.activity.row.dismissed")
            .firstMatch
        XCTAssertTrue(dismissedRow.waitForExistence(timeout: 5), "Dismissed link should be listed under Activity.")

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "activity-page"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPickerNumberShortcutSelectsBrowser() throws {
        launchClassicPickerFixture(suiteLabel: "picker-number")
        let ui = ChowserAppDriver(app: app)
        ui.assertPickerVisible()
        XCTAssertTrue(ui.lastOpenedBrowserText.waitForExistence(timeout: 3), "Expected picker selection marker before using keyboard shortcut.")

        app.typeKey("1", modifierFlags: [])

        ui.assertBrowserSelectionRecorded()
    }

    func testCanAddRoutingRule() throws {
        let ui = ChowserAppDriver(app: app)

        ui.openSettings()
        ui.assertSettingsVisible()
        ui.openRulesSection()
        ui.openAddRuleSheet()
        ui.addRule(hostPattern: "github.com")
        ui.assertRuleCreated()
    }

    func testOpenLinkShortcutSelectionWorks() throws {
        let ui = ChowserAppDriver(app: app)
        ui.openSettings()
        ui.assertSettingsVisible()

        let testURL = "https://example.com/chowser-shortcut-\(UUID().uuidString)"
        triggerOpenURLInChowser(testURL)

        ui.assertPickerVisible()
        XCTAssertTrue(ui.lastOpenedBrowserText.waitForExistence(timeout: 3), "Expected picker selection marker before using keyboard shortcut after URL open.")

        app.typeKey("1", modifierFlags: [])

        ui.assertBrowserSelectionRecorded()
    }

    func testSendToIPhoneActionMenu() throws {
        launchClassicPickerFixture(suiteLabel: "picker-phone")
        let ui = ChowserAppDriver(app: app)
        ui.assertPickerVisible()

        XCTAssertTrue(ui.sendToIPhoneButton.waitForExistence(timeout: 5), "Send to iPhone button should exist for a transferable URL.")
        ui.sendToIPhoneButton.click()

        XCTAssertTrue(ui.iphoneAirDropButton.waitForExistence(timeout: 5), "AirDrop action should appear in the Send to iPhone menu.")
        XCTAssertTrue(ui.iphoneShowQRCodeButton.waitForExistence(timeout: 5), "Show QR Code action should appear in the Send to iPhone menu.")
        XCTAssertTrue(ui.iphoneCopyURLButton.waitForExistence(timeout: 5), "Copy URL action should appear in the Send to iPhone menu.")
        XCTAssertTrue(ui.iphoneHandoffStatusText.waitForExistence(timeout: 5), "Handoff explanation text should appear in the Send to iPhone menu.")

        ui.iphoneShowQRCodeButton.click()

        XCTAssertTrue(ui.iphoneQRSheet.waitForExistence(timeout: 5), "QR sheet should be visible after choosing Show QR Code.")
        XCTAssertTrue(ui.iphoneQRImage.waitForExistence(timeout: 5), "QR image should be visible in the QR sheet.")
        XCTAssertTrue(ui.iphoneQRURLText.waitForExistence(timeout: 5), "URL text should be visible in the QR sheet.")
        XCTAssertTrue(ui.iphoneQRCloseButton.waitForExistence(timeout: 5), "Close button should be visible in the QR sheet.")

        ui.iphoneQRCloseButton.click()
    }

    // MARK: - Profile-Aware Tests

    func testAddBrowserSheetShowsProfileEntries() throws {
        let ui = ChowserAppDriver(app: app)

        ui.openSettings()
        ui.assertSettingsVisible()
        ui.openAddBrowserSheet()

        // The add-browser sheet should show browser options (mock or real).
        // Each option has the identifier "settings.addSheet.option".
        let options = app.descendants(matching: .any).matching(identifier: "settings.addSheet.option")
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5), "Expected at least one browser option in add sheet.")
        XCTAssertGreaterThanOrEqual(options.count, 1, "Should have at least one browser option displayed.")
    }

    func testAddBrowserWithProfileAppearsInList() throws {
        let ui = ChowserAppDriver(app: app)

        ui.openSettings()
        ui.assertSettingsVisible()
        let beforeCount = ui.browserRows.count
        ui.openAddBrowserSheet()
        ui.addFirstBrowserOption()
        let added = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", beforeCount + 1), object: ui.browserRows
        )
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 5), .completed,
                       "Adding one browser should increase the list by exactly one.")
    }

    func testRulesMenuButtonExists() throws {
        let ui = ChowserAppDriver(app: app)

        ui.openSettings()
        ui.assertSettingsVisible()
        ui.openRulesSection()

        // The rules section should have a menu button for export/import
        let menuButton = app.descendants(matching: .any).matching(identifier: "settings.rulesMenuButton").firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5), "Rules menu button should exist.")
    }

    func testRulesMenuShowsExportImportOptions() throws {
        let ui = ChowserAppDriver(app: app)

        ui.openSettings()
        ui.assertSettingsVisible()

        // Need at least one rule first
        ui.openRulesSection()
        ui.openAddRuleSheet()
        ui.addRule(hostPattern: "example.com")
        ui.assertRuleCreated()

        // Click the menu button to open the menu
        let menuButton = app.descendants(matching: .any).matching(identifier: "settings.rulesMenuButton").firstMatch
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5), "Rules menu button should exist.")
        menuButton.click()

        // Check that Export and Import items appear
        let exportItem = app.menuItems["Export Rules…"]
        let importItem = app.menuItems["Import Rules…"]
        XCTAssertTrue(exportItem.waitForExistence(timeout: 3), "Export Rules menu item should appear.")
        XCTAssertTrue(importItem.waitForExistence(timeout: 3), "Import Rules menu item should appear.")

        // Dismiss the menu by pressing Escape
        app.typeKey(.escape, modifierFlags: [])
    }

    func testAppModeRoundTripKeepsBothModesReachableAndRecordsDiagnostics() throws {
        let ui = ChowserAppDriver(app: app)

        ui.openSettings()
        ui.openGeneralSection()

        // "Show in Dock" on = App mode, off = Menu Bar mode.
        let showInDock = app.descendants(matching: .any)
            .matching(identifier: "settings.general.showInDock").firstMatch
        XCTAssertTrue(showInDock.waitForExistence(timeout: 5))
        func isOn() -> Bool { "\(showInDock.value ?? "")" == "1" }

        if !isOn() { showInDock.click() }
        XCTAssertTrue(isOn())

        showInDock.click()
        XCTAssertFalse(isOn())

        showInDock.click()
        XCTAssertTrue(isOn())

        showInDock.click()
        XCTAssertFalse(isOn())

        showInDock.click()
        XCTAssertTrue(isOn())

        ui.openBackupSection()

        let diagnosticsButton = app.buttons["settings.diagnosticsButton"]
        XCTAssertTrue(diagnosticsButton.waitForExistence(timeout: 5))
        diagnosticsButton.click()

        let events = app.descendants(matching: .any).matching(identifier: "diagnosticsRecentEvents").firstMatch
        XCTAssertTrue(events.waitForExistence(timeout: 5))
        let eventText = events.value as? String ?? ""
        XCTAssertTrue(eventText.contains("status-item-created"), "Diagnostics should record creation of the menu-bar item.")
        XCTAssertTrue(eventText.contains("status-item-removed"), "Diagnostics should record removal of the menu-bar item.")
        XCTAssertTrue(eventText.contains("activation-policy-transition-did-complete"), "Diagnostics should record completed transitions.")
    }

    func testAddRuleWithBrowserPickerSelection() throws {
        let ui = ChowserAppDriver(app: app)

        ui.openSettings()
        ui.assertSettingsVisible()

        // Ensure multiple browsers are configured
        if ui.browserRows.count < 2 {
            ui.openAddBrowserSheet()
            ui.addFirstBrowserOption()
        }

        // Switch to rules and add a rule
        ui.openRulesSection()
        ui.openAddRuleSheet()

        // The inspector for the new rule shows its browser picker.
        let browserPicker = app.descendants(matching: .any).matching(identifier: "settings.rule.browserPicker").firstMatch
        XCTAssertTrue(browserPicker.waitForExistence(timeout: 5), "Browser picker should be present in the rule inspector.")

        ui.addRule(hostPattern: "test.example.com")
        ui.assertRuleCreated()
    }


}
