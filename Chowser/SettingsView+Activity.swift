import SwiftUI
import AppKit

enum ActivityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case dismissed = "Dismissed"
    case autoRouted = "Auto-routed"

    var id: String { rawValue }

    func includes(_ entry: LinkHistoryEntry) -> Bool {
        switch (self, entry.outcome) {
        case (.all, _): return true
        case (.dismissed, .dismissed): return true
        case (.autoRouted, .native): return true
        case (.autoRouted, .browser(_, _, let rule)): return rule != nil
        default: return false
        }
    }
}

/// The Full history / Stats only / Off picker. Lowering the level deletes data, so it asks first.
/// Shown on both the Privacy and Activity pages.
struct ActivityLevelControl: View {
    @Bindable var manager: BrowserManager
    @State private var pendingLevel: ActivityLevel?

    var body: some View {
        Picker("Activity data", selection: Binding(get: { manager.activityLevel }, set: request)) {
            ForEach(ActivityLevel.allCases) { level in
                Text(level.title).tag(level)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150)
        .accessibilityLabel("Activity data")
        .confirmationDialog(
            "Delete existing activity data?",
            isPresented: Binding(get: { pendingLevel != nil }, set: { if !$0 { pendingLevel = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete and Switch", role: .destructive) {
                if let pendingLevel { manager.activityLevel = pendingLevel }
                pendingLevel = nil
            }
            Button("Cancel", role: .cancel) { pendingLevel = nil }
        } message: {
            Text(pendingLevel == .off
                ? "Link history and click statistics will be deleted and nothing will be recorded."
                : "Link history will be reduced to website names only. Full addresses will be deleted.")
        }
    }

    private func request(_ level: ActivityLevel) {
        if level.isLowerThan(manager.activityLevel) {
            pendingLevel = level
        } else {
            manager.activityLevel = level
        }
    }
}

extension SettingsView {
    static let activityPrivacyFooter = "Everything stays on this Mac. Chowser never sends usage data anywhere."

    /// Settings ▸ Activity: the local link history, a few stats computed from it, and the
    /// controls to clear it or change how much is kept.
    var activitySection: some View {
        let history = LinkHistory.shared
        let level = browserManager.activityLevel

        return SettingsDetailScaffold(
            title: "Activity",
            subtitle: "Links Chowser received, where they came from, and what happened to them.",
            systemImage: "clock.arrow.circlepath",
            actions: {
                Button("Clear History", role: .destructive) {
                    showingClearHistoryConfirmation = true
                }
                .disabled(history.entries.isEmpty)
                .accessibilityIdentifier("settings.activity.clearButton")
            },
            content: {
                VStack(alignment: .leading, spacing: 20) {
                    if browserManager.showsActivityUpgradeNotice, level == .statsOnly {
                        activityUpgradeNote
                    }

                    SettingsGroup("Activity data") {
                        SettingsRow(title: "Keep", subtitle: Self.activityPrivacyFooter) {
                            ActivityLevelControl(manager: browserManager)
                                .accessibilityIdentifier("settings.activity.levelPicker")
                        }
                    }

                    if level == .full {
                        activityHistoryGroup(entries: history.entries)
                        activityStatsGroup(entries: history.entries)
                    } else if level == .statsOnly {
                        activityStatsGroup(entries: history.entries)
                    } else {
                        EmptyStateView(
                            icon: "clock.arrow.circlepath",
                            title: "History is off",
                            message: "Chowser isn't recording links. Choose Full history above to turn it back on."
                        )
                        .frame(height: 180)
                        .accessibilityIdentifier("settings.activity.emptyState")
                    }
                }
            }
        )
        .confirmationDialog(
            "Clear link history?",
            isPresented: $showingClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All recorded links are deleted from this Mac.")
        }
        .accessibilityIdentifier("settings.activitySection")
    }

    // MARK: - History

    private func activityHistoryGroup(entries: [LinkHistoryEntry]) -> some View {
        let search = activitySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visible = entries.filter { entry in
            activityFilter.includes(entry)
                && (search.isEmpty || entry.url.absoluteString.lowercased().contains(search))
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ActivityFilter.allCases) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: activityFilter == filter,
                        count: entries.filter(filter.includes).count
                    ) {
                        activityFilter = filter
                    }
                    .accessibilityIdentifier("settings.activity.filter.\(filter.rawValue)")
                }
                Spacer(minLength: 8)
                TextField("Filter by host", text: $activitySearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .accessibilityIdentifier("settings.activity.searchField")
            }

            SettingsGroup("History") {
                if visible.isEmpty {
                    Text(entries.isEmpty ? "No links yet." : "No links match.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .accessibilityIdentifier("settings.activity.noRows")
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { SettingsDivider() }
                        activityRow(entry)
                    }
                }
            }
        }
    }

    private func activityRow(_ entry: LinkHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: activitySymbol(for: entry.outcome))
                .foregroundStyle(entry.outcome == .dismissed ? .orange : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(PickerDestinationDisplay(url: entry.url).host + (entry.url.path == "/" ? "" : entry.url.path))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(entry.date.formatted(date: .abbreviated, time: .shortened))  ·  \(activitySourceName(entry.sourceBundleID)) → \(activityOutcomeText(entry.outcome))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu("Open") {
                Button("Open") { AppDelegate.shared?.application(NSApp, open: [entry.url]) }
                Button("Open in…") { showPicker(for: entry) }
                Button("Copy URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
                }
                if entry.url.host != nil {
                    Button("Create Rule for Host") {
                        selectedSection = .rules
                        currentPrefillURL = entry.url
                        showingAddRuleSheet = true
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("settings.activity.rowMenu")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(entry.outcome == .dismissed ? "settings.activity.row.dismissed" : "settings.activity.row")
    }

    /// One-time tip for installs that predate Link History (they start at "Stats only").
    private var activityUpgradeNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Get back links you dismissed")
                    .font(.callout.weight(.semibold))
                Text("Chowser can keep a list of the links it handles, so a link you closed by accident is one click away. It's off for existing installs until you turn it on, and it never leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Turn On Full History") { browserManager.activityLevel = .full }
                        .accessibilityIdentifier("settings.activity.upgradeNote.enable")
                    Button("Not Now") { browserManager.showsActivityUpgradeNotice = false }
                        .accessibilityIdentifier("settings.activity.upgradeNote.dismiss")
                }
                .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.activity.upgradeNote")
    }

    private func showPicker(for entry: LinkHistoryEntry) {
        browserManager.recordReplacedPickerLink()
        browserManager.pickerSourceAppBundleId = entry.sourceBundleID
        browserManager.pickerPrivateIntent = false
        browserManager.currentURLPrivateModeRequested = false
        browserManager.currentURL = entry.url
        AppDelegate.shared?.showPickerForCurrentURL()
    }

    private func activitySymbol(for outcome: LinkHistoryEntry.Outcome) -> String {
        switch outcome {
        case .browser: return "safari"
        case .native: return "app.badge"
        case .dismissed: return "arrow.uturn.backward"
        }
    }

    private func activitySourceName(_ bundleID: String?) -> String {
        guard let bundleID else { return "Unknown source" }
        return AppMetadataCache.shared.displayName(for: bundleID) ?? bundleID
    }

    private func activityBrowserName(bundleID: String, profile: String?) -> String {
        let configured = browserManager.configuredBrowsers.first { $0.bundleId == bundleID && $0.profile == profile }
        var name = configured?.name
            ?? AppMetadataCache.shared.displayName(for: bundleID)
            ?? bundleID
        if configured == nil, let profile { name += " (\(profile))" }
        return name
    }

    private func activityOutcomeText(_ outcome: LinkHistoryEntry.Outcome) -> String {
        switch outcome {
        case .browser(let bundleID, let profile, let rule):
            let name = activityBrowserName(bundleID: bundleID, profile: profile)
            return rule.map { "\(name) · rule \"\($0)\"" } ?? name
        case .native(let handler):
            return AppMetadataCache.shared.displayName(for: handler) ?? handler
        case .dismissed:
            return "Dismissed"
        }
    }

    // MARK: - Stats

    private func activityStatsGroup(entries: [LinkHistoryEntry]) -> some View {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let recent = entries.filter { $0.date >= weekAgo }
        let autoRouted = recent.filter { ActivityFilter.autoRouted.includes($0) }.count
        let dismissed = recent.filter { $0.outcome == .dismissed }.count
        let percent = recent.isEmpty ? 0 : Int((Double(autoRouted) / Double(recent.count) * 100).rounded())

        let topSources = Dictionary(grouping: recent.compactMap(\.sourceBundleID), by: { $0 })
            .map { (activitySourceName($0.key), $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { "\($0.0) \($0.1)" }
            .joined(separator: " · ")

        let topDomains = Dictionary(grouping: recent.compactMap { $0.url.host }, by: { $0 })
            .sorted { $0.value.count > $1.value.count }
            .prefix(3)
            .map { "\($0.key) \($0.value.count)" }
            .joined(separator: " · ")

        return SettingsGroup("Last 7 days") {
            SettingsRow(title: "Links") {
                Text("\(recent.count) \(recent.count == 1 ? "link" : "links") · \(percent)% auto-routed · \(dismissed) dismissed")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.activity.summary")
            }
            SettingsDivider()
            SettingsRow(title: "Top sources") {
                Text(topSources.isEmpty ? "None" : topSources).foregroundStyle(.secondary)
            }
            SettingsDivider()
            SettingsRow(title: "Top domains") {
                Text(topDomains.isEmpty ? "None" : topDomains).foregroundStyle(.secondary)
            }
        }
    }
}
