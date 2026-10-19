import SwiftUI
import AppKit

struct SettingsView: View {
    @State var browserManager = BrowserManager.shared
    #if DIRECT_DISTRIBUTION
    @State var updateController = AppUpdateController.shared
    #else
    @State var appStoreUpdateProvider = AppStoreUpdateProvider.shared
    #endif

    /// Request flag for creating a rule from elsewhere in the app (e.g. the menu's
    /// "Create Rule for Link"). The Rules page consumes it by inserting a new rule
    /// into its table + inspector; there is no separate add-rule sheet.
    @State var showingAddRuleSheet = false
    @State var currentPrefillURL: URL?
    @State var selectedSection: SettingsSection = .browsers
    @State var showingResetConfirmation = false
    @State var activityFilter: ActivityFilter = .all
    @State var activitySearch = ""
    @State var showingClearHistoryConfirmation = false
    @State var newShortenerHost = ""
    /// Rules page editing state (selection, unsaved drafts). Owned here so drafts
    /// survive switching sidebar sections.
    @State var rulesEditor = RulesEditorModel(manager: BrowserManager.shared)
    @State var preselectedRuleBrowserIdentity: String?
    @State var showingRuleMergeReview = false
    @State var profileAccessStatus = SandboxBookmarkManager.shared.grantStatus
    @State var operationAlert: SettingsOperationAlert?
    @State var rewriteCatalogSheet: VerifiedRewriteCatalog?
    @State var isCheckingRewriteCatalog = false
    @State var nativeAppDirectory: VerifiedNativeAppDirectory?
    @State var isRefreshingNativeAppDirectory = false

    struct SettingsOperationAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
        case browsers = "Browsers"
        case rules = "Rules"
        case rewrites = "Rewrites"
        case nativeApps = "Native Apps"
        case picker = "Picker"
        case privacy = "Privacy"
        case activity = "Activity"
        case general = "General"
        case backup = "Backup & Advanced"

        var id: String { rawValue }

        /// Sidebar groups, separated by a small gap.
        static let groups: [[SettingsSection]] = [
            [.browsers, .rules, .rewrites, .nativeApps],
            [.picker, .privacy, .activity],
            [.general, .backup],
        ]

        var icon: String {
            switch self {
            case .browsers: return "globe"
            case .rules: return "point.topleft.down.curvedto.point.bottomright.up"
            case .rewrites: return "arrow.triangle.2.circlepath"
            case .nativeApps: return "app.badge"
            case .picker: return "square.grid.2x2"
            case .privacy: return "hand.raised"
            case .activity: return "clock.arrow.circlepath"
            case .general: return "gearshape"
            case .backup: return "archivebox"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .browsers: return "settings.sidebar.browsers"
            case .rules: return "settings.sidebar.rules"
            case .rewrites: return "settings.sidebar.rewrites"
            case .nativeApps: return "settings.sidebar.nativeApps"
            // The Picker section is the former Appearance page; UI tests target it by
            // this identifier.
            case .picker: return "settings.sidebar.appearance"
            case .privacy: return "settings.sidebar.privacy"
            case .activity: return "settings.sidebar.activity"
            case .general: return "settings.sidebar.general"
            case .backup: return "settings.sidebar.backup"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            settingsSidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            settingsDetail
        }
        .frame(minWidth: 860, idealWidth: 1100, maxWidth: .infinity, minHeight: 560, idealHeight: 680, maxHeight: .infinity)
        .sheet(isPresented: $showingRuleMergeReview) {
            RuleMergeReviewSheet(manager: browserManager, isPresented: $showingRuleMergeReview)
        }
        .sheet(item: $rewriteCatalogSheet) { catalog in
            RewriteCatalogSelectionSheet(
                catalog: catalog,
                manager: browserManager,
                isPresented: Binding(
                    get: { rewriteCatalogSheet != nil },
                    set: { if !$0 { rewriteCatalogSheet = nil } }
                )
            )
        }
        .onAppear(perform: consumeRequestedSection)
        .onChange(of: browserManager.requestedSettingsSection) { consumeRequestedSection() }
        .onChange(of: showingAddRuleSheet) {
            guard !showingAddRuleSheet else { return }
            currentPrefillURL = nil
            preselectedRuleBrowserIdentity = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenCreateRuleFromMenu"))) { notification in
            guard let url = notification.object as? URL else { return }
            selectedSection = .rules
            currentPrefillURL = url
            showingAddRuleSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RewriteCatalogApplied"))) { notification in
            guard let result = notification.object as? RewriteCatalogApplyResult else { return }
            let details: String
            if result.changedCount == 0 {
                details = "No rewrite rules changed. Selected entries may already be installed or conflict with a user rule."
            } else {
                var parts: [String] = []
                if result.added > 0 { parts.append("\(result.added) added") }
                if result.updated > 0 { parts.append("\(result.updated) updated") }
                if result.skipped > 0 { parts.append("\(result.skipped) skipped") }
                details = parts.joined(separator: ", ").capitalized + "."
            }
            operationAlert = SettingsOperationAlert(
                title: "Signed Rewrites Reviewed",
                message: details
            )
        }
        .alert("Reset Chowser setup?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                browserManager.resetToFreshSetup()
                selectedSection = .browsers
            }
        } message: {
            Text("This restores browser configuration to the first-launch state with Safari as option 1.")
        }
        .alert(item: $operationAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .accessibilityIdentifier("settings.root")
    }

    private func consumeRequestedSection() {
        guard let section = browserManager.requestedSettingsSection else { return }
        browserManager.requestedSettingsSection = nil
        selectedSection = section
    }

    func checkForRewriteCatalogUpdates() {
        guard !isCheckingRewriteCatalog else { return }
        isCheckingRewriteCatalog = true
        Task {
            // Always re-fetch (no version gate) so catalog rules can be re-reviewed and
            // re-added after deletion. The selection sheet shows per-rule status.
            let catalog = await RewriteCatalogService.shared.fetchCatalog()
            isCheckingRewriteCatalog = false
            guard let catalog else {
                operationAlert = SettingsOperationAlert(title: "Couldn't Load Rewrites", message: "Check your connection and try again.")
                return
            }
            RewriteCatalogService.shared.notifyUpdateAvailable(catalog)
            rewriteCatalogSheet = catalog
        }
    }

    private var settingsSidebar: some View {
        List(selection: $selectedSection) {
            ForEach(Array(SettingsSection.groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group) { section in
                        sidebarRow(for: section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("settings.sidebar")
    }

    private var settingsDetail: some View {
        Group {
            switch selectedSection {
            case .browsers:
                browsersSection
            case .rules:
                rulesSection
            case .rewrites:
                rewritesSection
            case .nativeApps:
                nativeAppsSection
            case .picker:
                appearanceSection
            case .privacy:
                privacySection
            case .activity:
                activitySection
            case .general:
                generalSection
            case .backup:
                backupSection
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Monochrome symbols; the sidebar tints them with the single app accent color.
    @ViewBuilder
    private func sidebarRow(for section: SettingsSection) -> some View {
        let count = sidebarBadge(for: section)

        NavigationLink(value: section) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .frame(width: 18)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(section.rawValue)

                Spacer(minLength: 4)

                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(count) items")
                }
            }
        }
        .accessibilityIdentifier(section.accessibilityIdentifier)
    }

    func presentSettingsMessage(_ title: String, _ message: String) {
        operationAlert = SettingsOperationAlert(title: title, message: message)
    }

    func presentImportSummary(for itemName: String, summary: BrowserManager.ImportSummary, successTitle: String) {
        var rows: [String] = []
        if summary.added > 0 { rows.append("Added: \(summary.added)") }
        if summary.updated > 0 { rows.append("Updated: \(summary.updated)") }
        if summary.skipped > 0 { rows.append("Skipped (existing): \(summary.skipped)") }
        if summary.invalid > 0 { rows.append("Skipped (invalid): \(summary.invalid)") }

        let message = rows.isEmpty
            ? "No changes were made."
            : "Imported \(itemName):\n" + rows.map { "• " + $0 }.joined(separator: "\n")
        presentSettingsMessage(successTitle, message)
    }

    func sidebarBadge(for section: SettingsSection) -> Int {
        switch section {
        case .browsers:
            return browserManager.configuredBrowsers.count
        case .rules:
            return browserManager.routingRules.filter(\.isEnabled).count
        case .rewrites:
            return browserManager.rewriteRules.filter(\.isEnabled).count
        case .nativeApps:
            return browserManager.nativeAppApprovals.count
        case .picker, .privacy, .activity, .general, .backup:
            return 0
        }
    }

}

struct SettingsDetailScaffold<Actions: View, Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let scrollsContent: Bool
    let actions: Actions
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        scrollsContent: Bool = true,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.scrollsContent = scrollsContent
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.accent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                actions
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.bar)

            Divider()

            if scrollsContent {
                ScrollView {
                    content
                        .padding(24)
                        .frame(maxWidth: 920, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

extension SettingsDetailScaffold where Actions == EmptyView {
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        scrollsContent: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            scrollsContent: scrollsContent,
            actions: { EmptyView() },
            content: content
        )
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 1)
            )
        }
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 14)
    }
}

struct SettingsEmptyContent: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

#Preview {
    SettingsView()
}
