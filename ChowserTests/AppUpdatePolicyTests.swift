import Testing
import Foundation
@testable import Chowser

struct AppUpdatePolicyTests {
    @Test("Stable update policy does not allow prerelease channels")
    func stablePolicy() {
        let policy = AppUpdatePolicy(includesBetaReleases: false)

        #expect(policy.allowedChannels.isEmpty)
    }

    @Test("Beta opt-in allows only the beta channel")
    func betaPolicy() {
        let policy = AppUpdatePolicy(includesBetaReleases: true)

        #expect(policy.allowedChannels == ["beta"])
    }

    @Test("Beta preference persists in the provided defaults store")
    @MainActor
    func betaPreferencePersists() {
        let suiteName = "in.sreerams.Chowser.UpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = AppUpdateController(defaults: defaults)
        controller.includesBetaReleases = true

        #expect(defaults.bool(forKey: AppUpdateController.includeBetaDefaultsKey))
        #expect(AppUpdateController(defaults: defaults).includesBetaReleases)
    }

    @Test("An unconfigured personal build never checks for updates automatically")
    @MainActor
    func updaterDefaults() {
        let controller = AppUpdateController()

        #expect(!controller.isConfigured)
        #expect(!controller.automaticallyChecksForUpdates)
        #expect(!controller.automaticallyDownloadsUpdates)
    }

    @Test("The direct product only names the fork as its update source")
    func forkFeedIsOptIn() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
            == "https://raw.githubusercontent.com/0xKoushy/chowser/updates/appcast.xml")
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == false)
    }
}
