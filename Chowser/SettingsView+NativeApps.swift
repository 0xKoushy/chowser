import SwiftUI
import AppKit

extension SettingsView {
    /// Settings ▸ Native Apps: one Allow switch per installed app from the signed
    /// directory. Per-app hosts/transforms and the directory's version/key/refresh live
    /// behind (i) popovers so the page stays a short list.
    var nativeAppsSection: some View {
        NativeAppsSettingsPage(
            manager: browserManager,
            directory: nativeAppDirectory,
            isRefreshing: isRefreshingNativeAppDirectory,
            onRefresh: refreshNativeAppDirectory
        )
        .onAppear {
            guard nativeAppDirectory == nil else { return }
            nativeAppDirectory = NativeAppDirectoryService.shared.currentDirectory
                ?? NativeAppDirectoryService.shared.loadLastKnownGood()
        }
    }

    private func refreshNativeAppDirectory() {
        guard !isRefreshingNativeAppDirectory else { return }
        isRefreshingNativeAppDirectory = true
        Task {
            let directory = await NativeAppDirectoryService.shared.refresh()
            isRefreshingNativeAppDirectory = false
            guard let directory else {
                presentSettingsMessage(
                    "Couldn't Verify Native App Directory",
                    "The download, signature, or catalog version was rejected. A previously verified directory remains in use if available."
                )
                return
            }
            nativeAppDirectory = directory
        }
    }
}

private struct NativeAppsSettingsPage: View {
    let manager: BrowserManager
    let directory: VerifiedNativeAppDirectory?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    @State private var showingDirectoryInfo = false

    var body: some View {
        SettingsDetailScaffold(
            title: "Native Apps",
            subtitle: "Open supported links in the app instead of a browser.",
            systemImage: "app.badge",
            scrollsContent: true,
            actions: { headerActions },
            content: {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Only apps you allow are used. Approval is revoked automatically if an app’s hosts, schemes, or link changes are updated.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    SettingsGroup("Apps on This Mac") {
                        appRows
                    }

                    Text("Links you open in private mode always go to a browser, never to an app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.nativeApps.privateNote")
                }
            }
        )
        .accessibilityIdentifier("settings.nativeAppsSection")
    }

    // MARK: Header

    private var headerActions: some View {
        Button("About the App Directory", systemImage: "info.circle") {
            showingDirectoryInfo.toggle()
        }
        .labelStyle(.iconOnly)
        .help("About the signed app directory")
        .accessibilityIdentifier("settings.nativeApps.directoryInfoButton")
        .popover(isPresented: $showingDirectoryInfo, arrowEdge: .bottom) {
            directoryInfo
        }
    }

    private var directoryInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signed App Directory")
                .font(.headline)

            Text("Chowser downloads a list of supported apps from fixed addresses and verifies its signature. The link you are opening is never sent.")
                .foregroundStyle(.secondary)

            if let directory {
                LabeledContent("Version", value: "\(directory.directory.catalogVersion)")
                LabeledContent("Signing key") {
                    Text(directory.provenance.keyID)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("Source", value: directory.provenance.source == .cache
                    ? "Verified copy saved on this Mac"
                    : "Freshly downloaded and verified")
            } else {
                Text("No verified directory is saved yet.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Check for Updates", action: onRefresh)
                    .disabled(isRefreshing)
                    .accessibilityIdentifier("settings.nativeApps.refreshButton")
            }
        }
        .padding(16)
        .frame(width: 340)
        .accessibilityIdentifier("settings.nativeApps.directoryInfo")
    }

    // MARK: Rows

    @ViewBuilder
    private var appRows: some View {
        if let directory {
            let installed = installedNativeApps(in: directory)
            if installed.isEmpty {
                SettingsRow(
                    title: "No supported apps installed",
                    subtitle: "Install an app from the directory, then check for updates with the (i) button."
                ) {
                    EmptyView()
                }
            } else {
                ForEach(installed) { installedApp in
                    NativeAppConsentRow(
                        entry: installedApp.entry,
                        bundleIdentifier: installedApp.bundleIdentifier,
                        isApproved: manager.isNativeAppApproved(installedApp.entry),
                        needsReview: manager.nativeAppApprovals[installedApp.entry.id] != nil
                            && !manager.isNativeAppApproved(installedApp.entry)
                    ) { enabled in
                        if enabled {
                            manager.approveNativeApp(installedApp.entry)
                        } else {
                            manager.revokeNativeApp(entryID: installedApp.entry.id)
                        }
                    }
                    if installedApp.id != installed.last?.id {
                        SettingsDivider()
                    }
                }
            }
        } else {
            SettingsRow(
                title: "App directory not downloaded yet",
                subtitle: "Download the signed list of supported apps. Chowser never sends the link you are opening."
            ) {
                Button("Download", action: onRefresh)
                    .disabled(isRefreshing)
                    .accessibilityIdentifier("settings.nativeApps.downloadButton")
            }
        }
    }

    private func installedNativeApps(in directory: VerifiedNativeAppDirectory) -> [InstalledNativeApp] {
        directory.directory.apps.compactMap { entry in
            guard let bundleIdentifier = NativeAppDirectoryService.shared
                .installedBundleIdentifier(for: entry) else {
                return nil
            }
            return InstalledNativeApp(entry: entry, bundleIdentifier: bundleIdentifier)
        }
    }
}

private struct InstalledNativeApp: Identifiable {
    let entry: NativeAppDirectoryEntry
    let bundleIdentifier: String

    var id: String { entry.id }
}

/// One app: icon, name, one-line summary, an (i) popover with the exact hosts, schemes,
/// and transforms being approved, and the Allow switch.
private struct NativeAppConsentRow: View {
    let entry: NativeAppDirectoryEntry
    let bundleIdentifier: String
    let isApproved: Bool
    let needsReview: Bool
    let onToggle: (Bool) -> Void

    @State private var showingDetails = false

    var body: some View {
        HStack(spacing: 12) {
            BrowserAppIcon(bundleId: bundleIdentifier, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.body.weight(.medium))
                    if needsReview {
                        Text("Changed — review again")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("settings.nativeApps.\(entry.id).needsReview")
                    }
                }
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(entry.summary)
            }

            Spacer(minLength: 12)

            Button("Details for \(entry.name)", systemImage: "info.circle") {
                showingDetails.toggle()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("What allowing \(entry.name) covers")
            .accessibilityIdentifier("settings.nativeApps.\(entry.id).detailsButton")
            .popover(isPresented: $showingDetails, arrowEdge: .trailing) {
                details
            }

            Text("Allow")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Toggle("Allow \(entry.name)", isOn: Binding(get: { isApproved }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier("settings.nativeApps.\(entry.id).toggle")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.name)
                .font(.headline)
            Text(bundleIdentifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()

            LabeledContent("Web links on") {
                Text(sourceHosts.joined(separator: ", "))
                    .textSelection(.enabled)
            }
            LabeledContent("Opens as") {
                Text(entry.nativeSchemes.map { $0 + ":" }.joined(separator: ", "))
                    .font(.body.monospaced())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Link changes")
                // Bounded so an app with many transforms can't grow the popover past the screen.
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(entry.rules) { rule in
                            Text("• \(rule.reviewDescription)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Label("Approval is revoked automatically if hosts, bundle IDs, schemes, or transforms change.", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 380)
        .accessibilityIdentifier("settings.nativeApps.\(entry.id).details")
    }

    private var sourceHosts: [String] {
        var hosts: [String] = []
        for host in entry.rules.flatMap(\.source.hosts) where !hosts.contains(host) {
            hosts.append(host)
        }
        return hosts
    }
}
