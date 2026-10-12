import SwiftUI
import AppKit

extension SettingsView {
    /// Settings ▸ General: default-browser status, startup and Dock presence, updates,
    /// and the version.
    var generalSection: some View {
        @Bindable var manager = browserManager

        return SettingsDetailScaffold(
            title: "General",
            subtitle: "How Chowser starts and stays up to date.",
            systemImage: "gearshape",
            scrollsContent: true,
            content: {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsGroup("Default Browser") {
                        DefaultBrowserStatusRow()
                    }

                    SettingsGroup("Startup") {
                        SettingsRow(title: "Launch at login") {
                            Toggle("Launch at login", isOn: $manager.launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityIdentifier("settings.general.launchAtLogin")
                        }

                        SettingsDivider()

                        SettingsRow(
                            title: "Show in Dock",
                            subtitle: manager.appMode == .app
                                ? "Chowser has a Dock icon and appears in Command-Tab."
                                : "Chowser lives only in the menu bar."
                        ) {
                            Toggle("Show in Dock", isOn: Binding(
                                get: { manager.appMode == .app },
                                set: { transitionAppMode(to: $0 ? .app : .menuBar) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("settings.general.showInDock")
                        }
                    }

                    updatesSettingsGroup

                    HStack(spacing: 10) {
                        Image(nsImage: BrowserManager.currentAppIcon())
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 32, height: 32)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Chowser \(appVersion)")
                                .font(.callout.weight(.medium))
                                .textSelection(.enabled)
                            Text(distributionDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.general.about")
                }
            }
        )
        .accessibilityIdentifier("settings.generalSection")
    }

    var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    private var distributionDescription: String {
        #if DIRECT_DISTRIBUTION
        return "A browser chooser for macOS · direct download"
        #else
        return "A browser chooser for macOS · Mac App Store"
        #endif
    }

    @ViewBuilder
    private var updatesSettingsGroup: some View {
        #if DIRECT_DISTRIBUTION
        SettingsGroup(
            "Updates",
            subtitle: updateController.isConfigured
                ? nil
                : "Update signing is not configured in this local build."
        ) {
            SettingsRow(
                title: "Update channel",
                subtitle: updateController.includesBetaReleases
                    ? "Beta builds arrive earlier and may have rough edges."
                    : nil
            ) {
                Picker("Update channel", selection: $updateController.includesBetaReleases) {
                    Text("Stable").tag(false)
                    Text("Beta").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("settings.updates.includeBeta")
            }

            SettingsDivider()

            SettingsRow(title: "Check for updates automatically") {
                Toggle(
                    "Check for updates automatically",
                    isOn: Binding(
                        get: { updateController.automaticallyChecksForUpdates },
                        set: { updateController.automaticallyChecksForUpdates = $0 }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!updateController.isConfigured)
                .accessibilityIdentifier("settings.updates.automaticChecks")
            }

            SettingsDivider()

            SettingsRow(
                title: "Download updates automatically",
                subtitle: "Installs when Chowser quits."
            ) {
                Toggle(
                    "Download updates automatically",
                    isOn: Binding(
                        get: { updateController.automaticallyDownloadsUpdates },
                        set: { updateController.automaticallyDownloadsUpdates = $0 }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!updateController.isConfigured)
                .accessibilityIdentifier("settings.updates.automaticDownloads")
            }

            SettingsDivider()

            SettingsRow(title: "Check for a newer version") {
                Button("Check Now") {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
                .accessibilityIdentifier("settings.updates.checkNow")
            }
        }
        #else
        SettingsGroup("Updates") {
            SettingsRow(
                title: "Managed by the Mac App Store",
                subtitle: "Automatic update preferences are controlled in the App Store."
            ) {
                Button("Open App Store…") {
                    appStoreUpdateProvider.openAppStore()
                }
                .accessibilityIdentifier("settings.updates.openAppStore")
            }
        }
        #endif
    }

    /// Keeps the existing App Mode transition API and its failure alert.
    @MainActor
    private func transitionAppMode(to mode: ChowserAppMode) {
        guard mode != browserManager.appMode else { return }
        guard case .failure(let error) = AppDelegate.transitionAppMode(to: mode) else { return }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Could Not Change App Mode"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

/// Live default-browser status. Re-reads Launch Services when Settings appears, when the
/// app becomes active, and briefly after "Set as Default" (macOS asks the user to
/// confirm in a system dialog, so the change lands asynchronously).
struct DefaultBrowserStatusRow: View {
    @State private var isDefault = BrowserManager.isDefaultBrowser()
    @State private var currentDefaultName = DefaultBrowserStatusRow.defaultBrowserName()
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isDefault ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isDefault
                    ? "Chowser is your default browser"
                    : "\(currentDefaultName ?? "Another app") is your default browser")
                    .font(.system(size: 13, weight: .medium))
                Text(isDefault
                    ? "Every link you click goes through your rules."
                    : "Links open there directly, so your rules don’t run.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.general.defaultBrowserStatus")

            Spacer(minLength: 16)

            if !isDefault {
                Button("Set as Default", action: setAsDefault)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Set Chowser as the default browser")
                    .accessibilityIdentifier("settings.general.setDefaultBrowser")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func setAsDefault() {
        BrowserManager.setAsDefaultBrowser()
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                refresh()
                if isDefault { return }
            }
        }
    }

    private func refresh() {
        isDefault = BrowserManager.isDefaultBrowser()
        currentDefaultName = Self.defaultBrowserName()
    }

    private static func defaultBrowserName() -> String? {
        guard let url = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return FileManager.default.displayName(atPath: appURL.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
