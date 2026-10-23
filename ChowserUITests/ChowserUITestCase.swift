import XCTest
import AppKit

class ChowserUITestCase: XCTestCase {
    var app: XCUIApplication!
    var logsDirectory: URL!
    var defaultsSuiteName: String!
    let chowserBundleIdentifier = "in.sreerams.Chowser"

    override func setUpWithError() throws {
        continueAfterFailure = false

        terminateRunningChowserApps()

        logsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chowser-ui-tests-\(UUID().uuidString)", isDirectory: true)
        launchTestApp(arguments: [
            "-UITesting",
            "-UITesting_ClearData",
            "-UITesting_MockInstalledBrowsers",
            "-UITesting_DisableExternalOpen",
            "-UITesting_DefaultURL",
            "-UITesting_OpenSettings",
        ])
    }

    override func tearDownWithError() throws {
        if (testRun?.totalFailureCount ?? 0) > 0 { attachFailureDiagnostics() }
        if let app, app.state != .notRunning {
            app.terminate()
        }

        terminateRunningChowserApps(timeout: 2)
        if let logsDirectory {
            try? FileManager.default.removeItem(at: logsDirectory)
        }
        if let defaultsSuiteName {
            UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
        }
        logsDirectory = nil
        defaultsSuiteName = nil
        app = nil
    }

    func terminateRunningChowserApps(timeout: TimeInterval = 6) {
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: chowserBundleIdentifier)
            guard !runningApps.isEmpty else { return }

            for runningApp in runningApps {
                if !runningApp.terminate() {
                    runningApp.forceTerminate()
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.15))

            if Date() >= deadline {
                for runningApp in runningApps where !runningApp.isTerminated {
                    runningApp.forceTerminate()
                }
                return
            }
        }
    }

    func launchTestApp(
        arguments: [String],
        suiteLabel: String = "default",
        mouseLocation: CGPoint? = nil
    ) {
        if let app, app.state != .notRunning {
            app.terminate()
        }
        terminateRunningChowserApps()
        if let defaultsSuiteName {
            UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
        }

        let counterFile = logsDirectory.appendingPathComponent("open-count.txt")
        if FileManager.default.fileExists(atPath: counterFile.path) {
            do { try FileManager.default.removeItem(at: counterFile) }
            catch { XCTFail("Could not reset the launch observation: \(error)"); return }
        }

        defaultsSuiteName = "in.sreerams.Chowser.UITests.\(suiteLabel).\(UUID().uuidString)"
        let applicationURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Chowser.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: applicationURL.path))
        app = XCUIApplication(url: applicationURL)
        app.launchEnvironment["CHOWSER_LOGS_DIRECTORY"] = logsDirectory.path
        app.launchEnvironment["CHOWSER_DEFAULTS_SUITE"] = defaultsSuiteName
        app.launchArguments = arguments
        if let mouseLocation {
            CGWarpMouseCursorPosition(mouseLocation)
        }
        app.launch()
        let launched = NSRunningApplication.runningApplications(withBundleIdentifier: chowserBundleIdentifier).first?.bundleURL
        XCTAssertEqual(launched?.resolvingSymlinksInPath(), applicationURL.resolvingSymlinksInPath())
    }

    func launchClassicPickerFixture(suiteLabel: String) {
        launchTestApp(arguments: [
            "-UITesting",
            "-UITesting_ClearData",
            "-UITesting_IconsPickerFixture",
            "-UITesting_DisableExternalOpen",
            "-UITesting_DefaultURL",
            "-UITesting_OpenPicker",
            "-ApplePersistenceIgnoreState",
            "YES",
        ], suiteLabel: suiteLabel)
    }

    /// The app publishes successful opens atomically; UserDefaults disk writes are asynchronous.
    func observedOpenInvocationCount() -> Int {
        let file = logsDirectory.appendingPathComponent("open-count.txt")
        guard FileManager.default.fileExists(atPath: file.path) else { return 0 }
        do { return Int(try String(contentsOf: file, encoding: .utf8)) ?? -1 }
        catch { XCTFail("Could not read the launch observation: \(error)"); return -1 }
    }

    private func attachFailureDiagnostics() {
        if let app, app.state != .notRunning {
            let testWindows = app.windows.allElementsBoundByIndex + app.dialogs.allElementsBoundByIndex
            let tree = XCTAttachment(string: testWindows.map(\.debugDescription).joined(separator: "\n"))
            tree.name = "Chowser accessibility state"
            tree.lifetime = .keepAlways
            add(tree)
            let settings = app.windows["Chowser Settings"]
            if settings.exists {
                let screenshot = XCTAttachment(screenshot: settings.screenshot())
                screenshot.name = "Test Settings window"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
        }
        guard let logsDirectory else { return }
        do {
            for file in try FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
                where file.pathExtension == "log" || file.lastPathComponent == "open-count.txt" {
                let log = XCTAttachment(contentsOfFile: file)
                log.name = file.lastPathComponent
                log.lifetime = .keepAlways
                add(log)
            }
        } catch { XCTFail("Could not attach test diagnostics: \(error)") }
    }

    /// Waits for exactly `expectedCount` launches, then lets a late duplicate launch surface
    /// before confirming the count did not move.
    func waitForOpenInvocationCount(_ expectedCount: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if observedOpenInvocationCount() == expectedCount {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                return observedOpenInvocationCount() == expectedCount
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return false
    }

    func replaceText(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        app.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    func reveal(_ element: XCUIElement, in container: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let scroll = container.elementType == .scrollView ? container : container.scrollViews.firstMatch
        func isFullyVisible() -> Bool {
            let visible = scroll.frame.insetBy(dx: 0, dy: 8)
            return element.isHittable && element.frame.minY >= visible.minY && element.frame.maxY <= visible.maxY
        }
        for _ in 0..<12 where !isFullyVisible() {
            let distance = element.frame.midY - scroll.frame.midY
            scroll.scroll(byDeltaX: 0, deltaY: -min(max(distance, -200), 200))
        }
        XCTAssertTrue(isFullyVisible(), "Control should be fully reachable by scrolling: \(element.identifier)")
    }

    func assertCount(_ count: Int, in query: XCUIElementQuery,
                     file: StaticString = #filePath, line: UInt = #line) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", count), object: query)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, file: file, line: line)
    }

    func assertContains(_ text: String, in element: XCUIElement,
                        file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", text, text)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5),
                       .completed, file: file, line: line)
    }

    func triggerOpenURLInChowser(_ urlString: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let appURL = NSRunningApplication.runningApplications(withBundleIdentifier: chowserBundleIdentifier).first?.bundleURL else {
            XCTFail("Could not locate running Chowser app to open URL.", file: file, line: line)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appURL.path, urlString]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            XCTFail("Failed to invoke open command for URL test: \(error.localizedDescription)", file: file, line: line)
            return
        }

        XCTAssertEqual(process.terminationStatus, 0, "open command should succeed when sending URL to Chowser.", file: file, line: line)
    }}
