import Foundation
import Testing
@testable import Chowser

@MainActor
struct PreferencePersistenceTests {
    private func isolatedDefaults() -> (String, UserDefaults) {
        let name = "Chowser.PreferencePersistence.\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }

    @Test("Quit-time flush saves the latest queued browsers, routes and rewrites immediately")
    func flushKeepsLatestEditsAndIsIdempotent() {
        let (suite, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = BrowserManager(defaults: defaults, immediateWrite: false)
        manager.configuredBrowsers = [BrowserConfig(name: "Old", bundleId: "com.apple.Safari", shortcutKey: "1")]
        let browser = BrowserConfig(name: "Final lab browser", bundleId: "com.apple.Safari", shortcutKey: "2")
        let route = BrowserRoutingRule(name: "Lab route", hostPattern: "lab.example", browserBundleId: browser.bundleId)
        let rewrite = URLRewriteRule(name: "Lab HTTPS", match: URLRewriteMatch(hostPattern: "lab.example"),
                                     actions: [.forceScheme("https")])
        manager.configuredBrowsers = [browser]
        manager.routingRules = [route]
        manager.rewriteRules = [rewrite]
        manager.flushPendingSaves()
        manager.flushPendingSaves()
        let restored = BrowserManager(defaults: defaults)
        #expect(restored.configuredBrowsers == [browser])
        #expect(restored.routingRules == [route])
        #expect(restored.rewriteRules == [rewrite])
        #expect(restored.applyRewritePipeline(to: URL(string: "http://lab.example/docs")!, sourceApp: nil).finalURL.absoluteString
                == "https://lab.example/docs")
        #expect(restored.resolvedBrowser(for: URL(string: "https://other.example/")!) == nil)
    }

    @Test("A new manager restores all custom picker appearance and privacy preferences")
    func customPickerPreferencesSurviveRecreation() {
        let (suite, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = BrowserManager(defaults: defaults)
        manager.pickerIconSize = "large"
        manager.pickerShowLabels = false
        manager.pickerLayoutMode = .minimal
        manager.densityPreference = "comfortable"
        manager.pickerAppearanceMode = "custom"
        manager.pickerTintHex = "#112233"
        manager.pickerBackgroundOpacity = 0.42
        manager.pickerCornerRadius = 23
        manager.pickerAccentHex = "#445566"
        manager.qrCodeAccentHex = "#778899"
        manager.pickerDimInactiveBrowsers = false
        manager.pickerColorScheme = "dark"
        manager.showLinkPreview = false
        let restored = BrowserManager(defaults: defaults)
        #expect(restored.pickerIconSize == "large" && !restored.pickerShowLabels)
        #expect(restored.pickerLayoutMode == .minimal && restored.densityPreference == "comfortable")
        #expect(restored.pickerAppearanceMode == "custom" && restored.pickerTintHex == "#112233")
        #expect(restored.pickerBackgroundOpacity == 0.42 && restored.pickerCornerRadius == 23)
        #expect(restored.pickerAccentHex == "#445566" && restored.qrCodeAccentHex == "#778899")
        #expect(!restored.pickerDimInactiveBrowsers && restored.pickerColorScheme == "dark")
        #expect(!restored.showLinkPreview)
    }

    @Test("Out-of-range stored appearance values are clamped and unknown modes use safe defaults")
    func invalidStoredPreferencesDoNotEscapeBounds() {
        let (suite, defaults) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(-4.0, forKey: "pickerBackgroundOpacity")
        defaults.set(90.0, forKey: "pickerCornerRadius")
        for key in ["pickerLayoutMode", "densityPreference", "pickerAppearanceMode", "pickerColorScheme"] {
            defaults.set("unknown-lab-mode", forKey: key)
        }
        let restored = BrowserManager(defaults: defaults)
        #expect(restored.pickerBackgroundOpacity == 0.2 && restored.pickerCornerRadius == 28)
        #expect(restored.pickerLayoutMode == .icons && restored.densityPreference == "default")
        #expect(restored.pickerAppearanceMode == "auto" && restored.pickerColorScheme == "system")
    }
}
