import AppKit
import Testing
@testable import Chowser

struct AppModeTransitionTests {
    @Test("Reapplying the active app mode keeps its entry point without changing activation policy",
          arguments: [ChowserAppMode.app, .menuBar])
    @MainActor
    func reapplyingActiveModeIsIdempotent(_ mode: ChowserAppMode) {
        var events: [String] = []
        let result = AppDelegate.performAppModeTransition(
            to: mode, currentMode: mode,
            ensureStatusItem: { events.append("status-created"); return true },
            setActivationPolicy: { _ in events.append("unexpected-policy-change"); return false },
            removeStatusItem: { events.append("status-removed") },
            persistMode: { events.append("persist-\($0.rawValue)") }
        )
        guard case .success = result else { Issue.record("An already active mode must succeed"); return }
        #expect(events == (mode == .menuBar
            ? ["status-created", "persist-menuBar"] : ["status-removed", "persist-app"]))
    }

    @Test("Incoming URL batches wait for the picker and retain each source and intent")
    func incomingURLQueuePreservesOrderAndContext() {
        var queue = IncomingURLQueue()
        let first = IncomingURLQueue.Entry(
            url: URL(string: "https://first.example")!, sourceApp: "app.first",
            forceShowPicker: true, privateModeRequested: false
        )
        let second = IncomingURLQueue.Entry(
            url: URL(string: "https://second.example")!, sourceApp: "app.first",
            forceShowPicker: true, privateModeRequested: true
        )
        let third = IncomingURLQueue.Entry(
            url: URL(string: "https://third.example")!, sourceApp: "app.second",
            forceShowPicker: false, privateModeRequested: false
        )
        let duplicate = IncomingURLQueue.Entry(
            url: first.url, sourceApp: first.sourceApp,
            forceShowPicker: first.forceShowPicker, privateModeRequested: first.privateModeRequested
        )
        #expect(first != duplicate, "Two deliveries of the same URL need distinct identities")

        #expect(queue.enqueue([first, second]) == first)
        #expect(queue.enqueue([third]) == nil)
        #expect(queue.active == first)
        let unwrapped = IncomingURLQueue.Entry(
            url: URL(string: "https://unwrapped.example")!, sourceApp: first.sourceApp,
            forceShowPicker: first.forceShowPicker, privateModeRequested: first.privateModeRequested,
            id: first.id
        )
        #expect(queue.replaceActive(with: unwrapped) == unwrapped)
        #expect(queue.finishActive() == second)
        #expect(queue.finishActive() == third)
        #expect(queue.finishActive() == nil)
    }

    @Test("Reopen is deferred only when no URL open is in flight")
    func reopenSuppression() {
        #expect(!AppDelegate.shouldScheduleDeferredReopen(
            hasVisibleWindows: false,
            secondsSinceLastURLOpen: 0.05
        ))
        #expect(!AppDelegate.shouldScheduleDeferredReopen(
            hasVisibleWindows: true,
            secondsSinceLastURLOpen: 10
        ))
        #expect(AppDelegate.shouldScheduleDeferredReopen(
            hasVisibleWindows: false,
            secondsSinceLastURLOpen: 10
        ))
    }

    @Test("Menu Bar transition creates status item before hiding the Dock icon")
    @MainActor
    func menuBarTransitionOrder() {
        var events: [String] = []

        let result = AppDelegate.performAppModeTransition(
            to: .menuBar,
            currentMode: .app,
            ensureStatusItem: { events.append("status-created"); return true },
            setActivationPolicy: { events.append("policy-\($0.rawValue)"); return true },
            removeStatusItem: { events.append("status-removed") },
            persistMode: { events.append("persist-\($0.rawValue)") }
        )

        if case .failure(let error) = result {
            Issue.record("Expected success, got \(error)")
        }
        #expect(events == ["status-created", "policy-\(NSApplication.ActivationPolicy.accessory.rawValue)", "persist-menuBar"])
    }

    @Test("App transition shows the Dock icon before removing the status item")
    @MainActor
    func appTransitionOrder() {
        var events: [String] = []

        let result = AppDelegate.performAppModeTransition(
            to: .app,
            currentMode: .menuBar,
            ensureStatusItem: { events.append("status-created"); return true },
            setActivationPolicy: { events.append("policy-\($0.rawValue)"); return true },
            removeStatusItem: { events.append("status-removed") },
            persistMode: { events.append("persist-\($0.rawValue)") }
        )

        if case .failure(let error) = result {
            Issue.record("Expected success, got \(error)")
        }
        #expect(events == ["policy-\(NSApplication.ActivationPolicy.regular.rawValue)", "status-removed", "persist-app"])
    }

    @Test("Missing status item rolls back to reachable App Mode")
    @MainActor
    func statusItemFailureRollsBack() {
        var events: [String] = []

        let result = AppDelegate.performAppModeTransition(
            to: .menuBar,
            currentMode: .app,
            ensureStatusItem: { events.append("status-failed"); return false },
            setActivationPolicy: { events.append("policy-\($0.rawValue)"); return true },
            removeStatusItem: { events.append("status-removed") },
            persistMode: { events.append("persist-\($0.rawValue)") }
        )

        guard case .failure(.statusItemUnavailable) = result else {
            Issue.record("Expected statusItemUnavailable")
            return
        }
        #expect(events == ["status-failed"])
    }

    @Test("Rejected accessory policy removes the attempted item and rolls back")
    @MainActor
    func accessoryFailureRollsBack() {
        var events: [String] = []

        let result = AppDelegate.performAppModeTransition(
            to: .menuBar,
            currentMode: .app,
            ensureStatusItem: { events.append("status-created"); return true },
            setActivationPolicy: {
                events.append("policy-\($0.rawValue)")
                return $0 == .regular
            },
            removeStatusItem: { events.append("status-removed") },
            persistMode: { events.append("persist-\($0.rawValue)") }
        )

        guard case .failure(.activationPolicyRejected(.menuBar)) = result else {
            Issue.record("Expected menuBar activationPolicyRejected")
            return
        }
        #expect(events == [
            "status-created",
            "policy-\(NSApplication.ActivationPolicy.accessory.rawValue)",
            "policy-\(NSApplication.ActivationPolicy.regular.rawValue)",
            "status-removed",
            "persist-app",
        ])
    }

    @Test("Rejected regular policy leaves the menu item and persisted mode unchanged")
    @MainActor
    func regularFailurePreservesCurrentMode() {
        var events: [String] = []

        let result = AppDelegate.performAppModeTransition(
            to: .app,
            currentMode: .menuBar,
            ensureStatusItem: { events.append("status-created"); return true },
            setActivationPolicy: { events.append("policy-\($0.rawValue)"); return false },
            removeStatusItem: { events.append("status-removed") },
            persistMode: { events.append("persist-\($0.rawValue)") }
        )

        guard case .failure(.activationPolicyRejected(.app)) = result else {
            Issue.record("Expected app activationPolicyRejected")
            return
        }
        #expect(events == ["policy-\(NSApplication.ActivationPolicy.regular.rawValue)"])
    }

    @Test("Failed accessory rollback keeps the status item as a recovery entry point")
    @MainActor
    func failedRollbackKeepsRecoveryEntryPoint() {
        var events: [String] = []

        let result = AppDelegate.performAppModeTransition(
            to: .menuBar,
            currentMode: .app,
            ensureStatusItem: { events.append("status-created"); return true },
            setActivationPolicy: { events.append("policy-\($0.rawValue)"); return false },
            removeStatusItem: { events.append("status-removed") },
            persistMode: { events.append("persist-\($0.rawValue)") }
        )

        guard case .failure(.rollbackFailed(.menuBar)) = result else {
            Issue.record("Expected menuBar rollbackFailed")
            return
        }
        #expect(events == [
            "status-created",
            "policy-\(NSApplication.ActivationPolicy.accessory.rawValue)",
            "policy-\(NSApplication.ActivationPolicy.regular.rawValue)",
            "persist-menuBar",
        ])
    }
}
