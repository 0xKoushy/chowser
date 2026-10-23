#if DEBUG
import AppKit
import CryptoKit
import SwiftUI

/// Synthetic documents signed with a fresh in-memory key. Never alters production trust or downloads.
@MainActor
enum UITestFixtures {
    static func prepareStartup() {
        guard AppEnvironment.isUITesting,
              ProcessInfo.processInfo.arguments.contains("-UITesting_AppModeQuestionFixture") else { return }
        OnboardingManager.shared.hasCompletedOnboarding = true
        BrowserManager.shared.hasBeenAskedAppMode = false
    }

    static func settingsView() -> SettingsView {
        var view = SettingsView()
        guard AppEnvironment.isUITesting else { return view }
        let arguments = Set(ProcessInfo.processInfo.arguments)
        do {
            if arguments.contains("-UITesting_CatalogFixture") {
                view = SettingsView(selectedSection: .rewrites,
                                    rewriteCatalogSheet: try rewriteCatalog())
            } else if arguments.contains("-UITesting_NativeAppsFixture") {
                BrowserManager.shared.nativeAppApprovals["lab-native"] = "previous-behavior"
                view = SettingsView(selectedSection: .nativeApps,
                                    nativeAppDirectory: try nativeDirectory())
            } else if arguments.contains("-UITesting_MergeReviewFixture") {
                prepareMergeRules()
                view = SettingsView(selectedSection: .rules,
                                    showingRuleMergeReview: true)
            }
        } catch {
            AppLogger.log("UITestFixture", "Could not construct verified fixture: \(error)")
        }
        return view
    }

    private static func verified<Document: HostedCatalogDocument>(_ document: Document) throws -> VerifiedHostedCatalog<Document> {
        let key = Curve25519.Signing.PrivateKey()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(document)
        let metadata = HostedCatalogSignatureMetadata(
            schemaVersion: 1, catalogKind: Document.expectedCatalogKind, keyID: "ui-fixture",
            algorithm: "ed25519", sha256: HostedCatalogTrust.sha256Hex(bytes),
            signature: try key.signature(for: bytes).base64EncodedString())
        let trust = HostedCatalogTrust(keys: [HostedCatalogKey(keyID: metadata.keyID, publicKey: key.publicKey.rawRepresentation)])
        return try trust.verify(HostedCatalogArtifact(documentData: bytes, signatureData: encoder.encode(metadata)), as: Document.self)
    }

    private static func rewriteCatalog() throws -> VerifiedRewriteCatalog {
        let rules = [
            RewriteCatalogEntry(id: "lab-https", name: "Lab HTTPS", summary: "Upgrade only the lab host.",
                                hostPattern: "lab.example", actions: [.forceScheme("https")]),
            RewriteCatalogEntry(id: "lab-host", name: "Lab host change", summary: "Review the destination change.",
                                hostPattern: "old.lab.example", actions: [.replaceHost("new.lab.example")]),
        ]
        return try VerifiedRewriteCatalog(verified(RewriteCatalog(
            schemaVersion: 1, catalogKind: RewriteCatalog.expectedCatalogKind, catalogVersion: 1,
            publishedAt: "2026-10-23T00:00:00Z", rules: rules)))
    }

    private static func nativeDirectory() throws -> VerifiedNativeAppDirectory {
        let rule = NativeDeepLinkRule(id: "item", source: NativeDeepLinkSource(
            hosts: ["native.lab.example"], path: [.literal("item"), .capture(NativeCapture(
                name: "id", characterSet: .urlUnreserved, maxLength: 128))], query: []),
            target: NativeDeepLinkTarget(scheme: "lab", format: .opaqueColonPath,
                                        host: "item", path: [.capture("id")], query: []))
        let entry = NativeAppDirectoryEntry(id: "lab-native", name: "Lab Native", summary: "Synthetic consent fixture",
            bundleIdentifiers: ["com.apple.Safari"], nativeSchemes: ["lab"], rules: [rule])
        return try VerifiedNativeAppDirectory(verified(NativeAppDirectory(
            schemaVersion: 1, catalogKind: NativeAppDirectory.expectedCatalogKind, catalogVersion: 1,
            publishedAt: "2026-10-23T00:00:00Z", apps: [entry])))
    }

    private static func prepareMergeRules() {
        let manager = BrowserManager.shared
        manager.routingRules = ["first.lab.example", "second.lab.example"].flatMap { host in
            ["com.apple.mail", "com.apple.Notes"].map { source in
                BrowserRoutingRule(name: host, hostPattern: host, browserBundleId: "com.apple.Safari",
                                   sourceAppBundleIDs: [source])
            }
        }
        manager.pendingRuleMergeSuggestions = BrowserManager.computeMergeSuggestions(for: manager.routingRules)
    }
}
#endif
