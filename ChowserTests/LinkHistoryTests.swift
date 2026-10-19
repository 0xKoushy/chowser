import Testing
import Foundation
@testable import Chowser

@MainActor
struct LinkHistoryTests {
    private func makeHistory() -> LinkHistory {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("link-history-tests-\(UUID().uuidString)/link-history.json")
        return LinkHistory(fileURL: url)
    }

    private let sample = URL(string: "https://github.com/anthropics/claude?tab=readme#top")!
    private let browserOutcome = LinkHistoryEntry.Outcome.browser(bundleID: "com.apple.Safari", profile: nil, viaRule: nil)

    @Test("Prunes to 500 entries, keeping the newest")
    func prunesByCount() {
        let history = makeHistory()
        for i in 0..<(LinkHistory.maxEntries + 20) {
            history.record(url: URL(string: "https://example.com/\(i)")!, source: nil, outcome: browserOutcome)
        }
        #expect(history.entries.count == LinkHistory.maxEntries)
        #expect(history.entries.first?.url.path == "/519")
    }

    @Test("Prunes entries older than 30 days on write")
    func prunesByAge() {
        let history = makeHistory()
        let now = Date()
        history.record(url: sample, source: nil, outcome: browserOutcome, date: now.addingTimeInterval(-31 * 24 * 3600))
        history.record(url: sample, source: nil, outcome: browserOutcome, date: now.addingTimeInterval(-29 * 24 * 3600))
        history.record(url: sample, source: nil, outcome: .dismissed, date: now)
        #expect(history.entries.count == 2)
        #expect(history.entries.allSatisfy { $0.date > now.addingTimeInterval(-30 * 24 * 3600) })
    }

    @Test("Entries persist to disk and reload")
    func persistsAndReloads() {
        let history = makeHistory()
        history.record(url: sample, source: "com.apple.Terminal", outcome: .dismissed)
        let reloaded = LinkHistory(fileURL: history.fileURL)
        #expect(reloaded.entries.map(\.id) == history.entries.map(\.id))
        #expect(reloaded.lastDismissed?.sourceBundleID == "com.apple.Terminal")
    }

    @Test("Lowering to Stats only strips stored URLs to scheme and host")
    func downgradeToStatsOnlyStrips() {
        let history = makeHistory()
        history.record(url: sample, source: nil, outcome: browserOutcome)
        history.setLevel(.statsOnly)
        #expect(history.entries.first?.url.absoluteString == "https://github.com")

        history.record(url: sample, source: nil, outcome: browserOutcome)
        #expect(history.entries.count == 2)
        #expect(history.entries.allSatisfy { $0.url.absoluteString == "https://github.com" })

        let reloaded = LinkHistory(fileURL: history.fileURL)
        #expect(reloaded.entries.allSatisfy { $0.url.absoluteString == "https://github.com" })
    }

    @Test("Lowering to Off wipes the history and the file")
    func downgradeToOffWipes() {
        let history = makeHistory()
        history.record(url: sample, source: nil, outcome: browserOutcome)
        #expect(FileManager.default.fileExists(atPath: history.fileURL.path))
        history.setLevel(.off)
        #expect(history.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: history.fileURL.path))
    }

    @Test("Private-mode opens are never recorded")
    func skipsPrivateMode() {
        let history = makeHistory()
        history.record(url: sample, source: nil, outcome: browserOutcome, isPrivate: true)
        #expect(history.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: history.fileURL.path))
    }

    @Test("Off writes nothing")
    func offWritesNothing() {
        let history = makeHistory()
        history.setLevel(.off)
        history.record(url: sample, source: nil, outcome: .dismissed)
        #expect(history.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: history.fileURL.path))
    }

    @Test("Click-away within the grace period is ignored")
    func gracePeriod() {
        #expect(!ContentView.shouldDismissOnResignKey(elapsedSincePresented: 0))
        #expect(!ContentView.shouldDismissOnResignKey(elapsedSincePresented: 0.399))
        #expect(ContentView.shouldDismissOnResignKey(elapsedSincePresented: 0.4))
        #expect(ContentView.shouldDismissOnResignKey(elapsedSincePresented: 2))
    }

    @Test("Domain tracker records nothing while disabled and clear() empties it")
    func trackerGatingAndClear() {
        let suite = UserDefaults(suiteName: "com.chowser.tests.\(UUID().uuidString)")!
        let tracker = DomainFrequencyTracker(defaults: suite)
        tracker.record(domain: "a.com", browserBundleID: "x")
        #expect(tracker.stats(for: "a.com") == ["x": 1])

        tracker.isRecordingEnabled = false
        tracker.record(domain: "b.com", browserBundleID: "x")
        tracker.isRecordingEnabled = true
        #expect(tracker.stats(for: "b.com").isEmpty)

        tracker.clear()
        #expect(tracker.stats(for: "a.com").isEmpty)
    }

    @Test("Dismissing the same link twice in a row keeps one entry")
    func repeatedDismissalCollapses() {
        let history = makeHistory()
        history.record(url: sample, source: nil, outcome: .dismissed)
        history.record(url: sample, source: nil, outcome: .dismissed)
        #expect(history.entries.count == 1)
    }

    @Test("A dismissed link opened later is no longer the one to reopen")
    func lastDismissedSkipsHandledLink() {
        let history = makeHistory()
        history.record(url: sample, source: nil, outcome: .dismissed)
        history.record(url: sample, source: nil, outcome: browserOutcome)
        #expect(history.lastDismissed == nil)
    }

    @Test("A future-dated entry doesn't stay on top as the last link")
    func keepsRecordingOrder() {
        let history = makeHistory()
        history.record(url: URL(string: "https://skewed.example")!, source: nil, outcome: browserOutcome,
                       date: Date().addingTimeInterval(24 * 3600))
        history.record(url: sample, source: nil, outcome: browserOutcome)
        #expect(history.entries.first?.url == sample)
    }

    @Test("An unreadable history file is moved aside, not overwritten")
    func corruptFileMovedAside() throws {
        let history = makeHistory()
        try FileManager.default.createDirectory(at: history.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: history.fileURL)
        let reloaded = LinkHistory(fileURL: history.fileURL)
        #expect(reloaded.entries.isEmpty)
        let aside = history.fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
        #expect(FileManager.default.fileExists(atPath: aside.path))
    }

    @Test("Always open puts the rule ahead of a broader rule that also matches")
    func alwaysOpenBeatsWildcard() {
        let defaults = UserDefaults(suiteName: "com.chowser.tests.\(UUID().uuidString)")!
        let manager = BrowserManager(defaults: defaults)
        let chrome = BrowserConfig(name: "Chrome", bundleId: "com.google.Chrome", shortcutKey: "1")
        let firefox = BrowserConfig(name: "Firefox", bundleId: "org.mozilla.firefox", shortcutKey: "2")
        manager.configuredBrowsers = [chrome, firefox]
        manager.routingRules = []
        manager.addRoutingRule(name: "Example", hostPattern: "*.example.com", pathPrefix: nil, browserBundleId: chrome.bundleId)

        manager.alwaysOpen(host: "docs.example.com", in: firefox)

        let route = manager.resolvedRoute(for: URL(string: "https://docs.example.com/page")!)
        #expect(route?.browser.bundleId == firefox.bundleId)
    }
}
