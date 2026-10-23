import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers

extension SettingsView {
    var rewritesSection: some View {
        RewritesSettingsPage(
            manager: browserManager,
            isCheckingCatalog: isCheckingRewriteCatalog,
            onCheckCatalog: checkForRewriteCatalogUpdates,
            onExport: exportRewrites,
            onImport: importRewrites
        )
    }

    func exportRewrites() {
        let panel = NSSavePanel()
        panel.title = "Export Rewrite Rules"
        panel.nameFieldStringValue = "ChowserRewrites.json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try browserManager.exportRewrites(to: url)
            presentSettingsMessage("Export complete", "Rewrites exported to \(url.lastPathComponent).")
        } catch {
            presentSettingsMessage("Export failed", "Could not export rewrites.\n\n\(error.localizedDescription)")
        }
    }

    func importRewrites() {
        let panel = NSOpenPanel()
        panel.title = "Import Rewrite Rules"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let summary = try browserManager.importRewrites(
                from: url,
                skipExisting: browserManager.skipExistingImportedRules
            )
            presentImportSummary(for: "Rewrites", summary: summary, successTitle: "Rewrites import complete")
        } catch {
            presentSettingsMessage("Import failed", "Could not import rewrites.\n\n\(error.localizedDescription)")
        }
    }
}

// MARK: - Page

/// Settings ▸ Rewrites: an ordered, drag-to-reorder list (the pipeline runs top to
/// bottom), a side inspector for the selected rewrite, undoable deletion, the signed
/// catalog, and a "Test a Link" popover. Mirrors the Browsers page's List + side panel.
struct RewritesSettingsPage: View {
    let manager: BrowserManager
    let isCheckingCatalog: Bool
    let onCheckCatalog: () -> Void
    let onExport: () -> Void
    let onImport: () -> Void

    @Environment(\.undoManager) private var undoManager

    @State private var selection: UUID?
    @State private var showingAddSheet = false
    @State private var showingTester = false
    @State private var idsBeforeAdd: Set<UUID> = []
    @State private var status: StatusMessage?

    /// One-line feedback under the list. Carries the removed rewrite so Undo can be offered.
    struct StatusMessage: Equatable {
        let text: String
        var removedID: UUID?
        var removedName: String?
    }

    var body: some View {
        let rules = manager.rewriteRules
        let selectedRule = selection.flatMap { id in rules.first { $0.id == id } }

        SettingsDetailScaffold(
            title: "Rewrites",
            subtitle: "Change a link before any rule looks at it.",
            systemImage: "arrow.triangle.2.circlepath",
            scrollsContent: false,
            actions: { headerActions },
            content: {
                HStack(spacing: 0) {
                    mainColumn(rules: rules)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    if let selectedRule {
                        Divider()
                        RewriteInspector(
                            rule: selectedRule,
                            manager: manager,
                            skipReason: manager.rewriteSkipReasons[selectedRule.id],
                            onDuplicate: { duplicate(selectedRule.id) },
                            onDelete: { delete(selectedRule.id) }
                        )
                        .id(selectedRule.id)
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        )
        .sheet(isPresented: $showingAddSheet, onDismiss: selectNewlyAddedRule) {
            RewriteRuleEditorSheet(manager: manager, isPresented: $showingAddSheet)
        }
        .onChange(of: rules.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) {
                self.selection = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.rewritesSection")
    }

    // MARK: Header actions

    private var headerActions: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Export Rewrites…", systemImage: "square.and.arrow.up", action: onExport)
                    .disabled(manager.rewriteRules.isEmpty)
                Button("Import Rewrites…", systemImage: "square.and.arrow.down", action: onImport)
            } label: {
                Label("Rewrite Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Import or export rewrites")
            .accessibilityLabel("Rewrite Actions")
            .accessibilityIdentifier("settings.rewritesMenuButton")

            Button("Test a Link", systemImage: "checkmark.circle") { showingTester.toggle() }
                .help("See which rewrites change a link")
                .accessibilityIdentifier("settings.rewrites.testButton")
                .popover(isPresented: $showingTester, arrowEdge: .bottom) {
                    RewriteTesterPopover(manager: manager)
                }

            Button("Predefined Rewrites…", systemImage: "sparkle.magnifyingglass", action: onCheckCatalog)
                .disabled(isCheckingCatalog)
                .help("Check Chowser's signed catalog for predefined rewrites")
                .accessibilityIdentifier("settings.checkRewriteCatalogButton")

            Button("Add Rewrite", systemImage: "plus", action: presentAddSheet)
                .labelStyle(.iconOnly)
                .help("Add Rewrite")
                .accessibilityIdentifier("settings.addRewriteButton")
        }
        .controlSize(.regular)
    }

    // MARK: Main column

    private func mainColumn(rules: [URLRewriteRule]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            rewriteList(rules: rules)
                .frame(minHeight: 180, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text("Rewrites run in this order before any rule is checked. Drag to reorder. Catalog rewrites are signed by Chowser and checked before use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let status {
                    statusLine(status, rules: rules)
                }
            }
        }
        .padding(20)
    }

    private func rewriteList(rules: [URLRewriteRule]) -> some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(rules) { rule in
                        RewriteListRow(
                            rule: rule,
                            skipReason: manager.rewriteSkipReasons[rule.id],
                            onSetEnabled: { setEnabled(rule.id, $0) }
                        )
                        .tag(rule.id)
                    }
                    .onMove { offsets, destination in
                        manager.moveRewriteRules(from: offsets, to: destination)
                    }
                } header: {
                    RewriteListHeader()
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first {
                    let index = rules.firstIndex { $0.id == id } ?? 0
                    Button("Move Up") { manager.moveRewriteRule(id: id, offsetBy: -1) }
                        .disabled(index == 0)
                    Button("Move Down") { manager.moveRewriteRule(id: id, offsetBy: 1) }
                        .disabled(index >= rules.count - 1)
                    Divider()
                    Button("Duplicate") { duplicate(id) }
                    Divider()
                    Button("Delete Rewrite") { delete(id) }
                }
            }
            .onDeleteCommand {
                guard let selection else { return }
                delete(selection)
            }
            .overlay {
                if rules.isEmpty {
                    emptyListContent
                }
            }
            .accessibilityLabel("Rewrites, applied in order")
            .accessibilityIdentifier("settings.rewrites.list")

            Divider()

            listFooter
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator)
        )
    }

    private var emptyListContent: some View {
        VStack(spacing: 8) {
            Text("No rewrites")
                .font(.headline)
            Text("Rewrites clean up or redirect a link before your rules run.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Add Rewrite", action: presentAddSheet)
                    .accessibilityIdentifier("settings.rewrites.emptyAddButton")
                Button("Predefined Rewrites…", action: onCheckCatalog)
                    .disabled(isCheckingCatalog)
            }
        }
        .padding()
    }

    private var listFooter: some View {
        HStack(spacing: 0) {
            Button(action: presentAddSheet) {
                Image(systemName: "plus")
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .help("Add Rewrite")
            .accessibilityLabel("Add Rewrite")
            .accessibilityIdentifier("settings.rewrites.footerAddButton")

            Divider()
                .frame(height: 14)

            Button {
                if let selection { delete(selection) }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .disabled(selection == nil)
            .help("Delete the selected rewrite")
            .accessibilityLabel("Delete Selected Rewrite")
            .accessibilityIdentifier("settings.rewrites.footerRemoveButton")

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private func statusLine(_ status: StatusMessage, rules: [URLRewriteRule]) -> some View {
        let isRestored = status.removedID.map { id in rules.contains { $0.id == id } } ?? false
        let text = isRestored ? "Restored \(status.removedName ?? "rewrite")." : status.text

        return HStack(spacing: 6) {
            Text(text)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.rewrites.statusText")

            if canUndoRemoval(status, rules: rules) {
                Button("Undo") {
                    undoManager?.undo()
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("settings.rewrites.undoDeleteButton")
            }
        }
        .font(.caption)
    }

    private func canUndoRemoval(_ status: StatusMessage, rules: [URLRewriteRule]) -> Bool {
        guard let removedID = status.removedID, let undoManager else { return false }
        return undoManager.canUndo
            && undoManager.undoActionName == "Delete Rewrite"
            && !rules.contains { $0.id == removedID }
    }

    // MARK: Actions

    private func presentAddSheet() {
        idsBeforeAdd = Set(manager.rewriteRules.map(\.id))
        showingAddSheet = true
    }

    private func selectNewlyAddedRule() {
        if let added = manager.rewriteRules.last(where: { !idsBeforeAdd.contains($0.id) }) {
            selection = added.id
            announce(StatusMessage(text: "Added \(added.name)."))
        }
        idsBeforeAdd = []
    }

    private func setEnabled(_ id: UUID, _ isEnabled: Bool) {
        guard var rule = manager.rewriteRules.first(where: { $0.id == id }), rule.isEnabled != isEnabled else { return }
        rule.isEnabled = isEnabled
        _ = manager.updateRewriteRule(rule)
    }

    private func duplicate(_ id: UUID) {
        let before = Set(manager.rewriteRules.map(\.id))
        manager.duplicateRewriteRule(id: id)
        if let copy = manager.rewriteRules.first(where: { !before.contains($0.id) }) {
            selection = copy.id
        }
    }

    private func delete(_ id: UUID) {
        guard let rule = manager.rewriteRules.first(where: { $0.id == id }) else { return }
        guard let index = manager.deleteRewriteRule(id: id, undoManager: undoManager) else { return }

        // Keep keyboard flow: select the row that slid into the deleted one's place.
        let remaining = manager.rewriteRules
        if selection == id {
            selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
        announce(StatusMessage(text: "Deleted \(rule.name).", removedID: rule.id, removedName: rule.name))
    }

    private func announce(_ message: StatusMessage) {
        status = message
        AccessibilityNotification.Announcement(message.text).post()
    }
}

// MARK: - List pieces

private enum RewriteListMetrics {
    static let toggleWidth: CGFloat = 18
    static let sourceWidth: CGFloat = 72
    static let spacing: CGFloat = 8
}

private struct RewriteListHeader: View {
    var body: some View {
        HStack(spacing: RewriteListMetrics.spacing) {
            Color.clear
                .frame(width: RewriteListMetrics.toggleWidth, height: 1)
            Text("Rewrite")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Source")
                .frame(width: RewriteListMetrics.sourceWidth, alignment: .leading)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

private struct RewriteListRow: View {
    let rule: URLRewriteRule
    let skipReason: String?
    let onSetEnabled: (Bool) -> Void

    var body: some View {
        HStack(spacing: RewriteListMetrics.spacing) {
            Toggle("Enabled", isOn: Binding(get: { rule.isEnabled }, set: onSetEnabled))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: RewriteListMetrics.toggleWidth)
                .accessibilityLabel("Enable \(rule.name)")
                .accessibilityIdentifier("settings.rewrite.enabledToggle")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let skipReason {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Last skipped: \(skipReason)")
                            .accessibilityLabel("Last skipped: \(skipReason)")
                    }
                    Text(rule.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                        .accessibilityIdentifier("settings.rewrite.name")
                }
                Text(rule.matchSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(rule.isFromCatalog ? "Catalog" : "Custom")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                .frame(width: RewriteListMetrics.sourceWidth, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.rewrite.row")
    }
}

private extension URLRewriteRule {
    var isFromCatalog: Bool { catalogProvenance != nil }

    /// "*.example.com/docs", with the scheme restriction when there is one.
    var matchSummary: String {
        var text = match.hostPattern == "*" ? "All sites" : match.hostPattern
        if let path = match.pathPrefix, !path.isEmpty {
            text += path.hasPrefix("/") ? path : "/" + path
        }
        if !match.schemes.isEmpty {
            text = match.schemes.joined(separator: ", ") + " · " + text
        }
        if match.useRegex {
            text += " (regex)"
        }
        return text
    }
}

// MARK: - Inspector

/// Side panel for the selected rewrite. Custom rewrites edit in place (commit on Return
/// or when a field loses focus; invalid edits stay as a visible draft with Revert).
/// Catalog rewrites are signed, so only Enabled can change here; Duplicate makes an
/// editable copy.
private struct RewriteInspector: View {
    let rule: URLRewriteRule
    let manager: BrowserManager
    let skipReason: String?
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private enum Field: Hashable {
        case name, host, path, excludedHosts
    }

    @State private var draft: URLRewriteRule
    @State private var schemeFilter: RewriteSchemeFilter
    @State private var actionFields: RewriteActionFieldsState
    @State private var excludedHostsText: String
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    init(
        rule: URLRewriteRule,
        manager: BrowserManager,
        skipReason: String?,
        onDuplicate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.rule = rule
        self.manager = manager
        self.skipReason = skipReason
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
        _draft = State(initialValue: rule)
        _schemeFilter = State(initialValue: RewriteSchemeFilter(schemes: rule.match.schemes))
        _actionFields = State(initialValue: RewriteActionFieldsState.derive(from: rule.actions))
        _excludedHostsText = State(initialValue: rule.match.excludeHostPatterns.joined(separator: ", "))
    }

    var body: some View {
        Form {
            if rule.isFromCatalog {
                catalogSections
            } else {
                customSections
            }

            Section {
                Toggle("Enabled", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { newValue in
                        var updated = rule
                        updated.isEnabled = newValue
                        _ = manager.updateRewriteRule(updated)
                    }
                ))
                .accessibilityIdentifier("settings.rewriteInspector.enabledToggle")

                if let skipReason {
                    Label("Last skipped: \(skipReason)", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("settings.rewrite.skipBadge")
                }
            }

            Section {
                HStack {
                    Button("Duplicate", action: onDuplicate)
                        .accessibilityIdentifier("settings.rewriteInspector.duplicateButton")
                    Spacer()
                    Button("Delete Rewrite", role: .destructive, action: onDelete)
                        .accessibilityIdentifier("settings.rewriteInspector.deleteButton")
                }
            }
        }
        .formStyle(.grouped)
        .textFieldStyle(.roundedBorder)
        .onChange(of: rule) { _, newValue in
            // Outside changes (list checkbox, Undo, duplicate) — resync unless the user is
            // mid-edit or holding an invalid draft.
            guard focus == nil, errorMessage == nil else { return }
            resync(to: newValue)
        }
        .onChange(of: focus) { oldValue, newValue in
            guard oldValue != nil, oldValue != newValue else { return }
            commit()
        }
        .onDisappear {
            if !rule.isFromCatalog { commit() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.rewriteInspector")
    }

    // MARK: Custom

    @ViewBuilder
    private var customSections: some View {
        Section {
            labeledField("Name", optional: true) {
                TextField("Name", text: $draft.name, prompt: Text(draft.match.hostPattern.isEmpty ? "Untitled rewrite" : draft.match.hostPattern))
                    .focused($focus, equals: .name)
                    .onSubmit(commit)
                    .accessibilityIdentifier("settings.rewrite.nameField")
            }

            labeledField("Match links on") {
                TextField("Host", text: $draft.match.hostPattern, prompt: Text(draft.match.useRegex ? "^(www\\.)?example\\.com$" : "*.example.com"))
                    .font(draft.match.useRegex ? .body.monospaced() : .body)
                    .focused($focus, equals: .host)
                    .onSubmit(commit)
                    .accessibilityIdentifier("settings.rewrite.hostField")
                hintText(draft.match.useRegex
                    ? "Matched against the whole host name."
                    : "Examples: example.com, *.example.com. Separate several with commas.")
            }

            labeledField("Path starts with", optional: true) {
                TextField("Path", text: Binding(
                    get: { draft.match.pathPrefix ?? "" },
                    set: { draft.match.pathPrefix = $0.isEmpty ? nil : $0 }
                ), prompt: Text("/docs"))
                .focused($focus, equals: .path)
                .onSubmit(commit)
                .accessibilityIdentifier("settings.rewrite.pathField")
            }

            Picker("Scheme", selection: Binding(
                get: { schemeFilter },
                set: { schemeFilter = $0; commit() }
            )) {
                ForEach(RewriteSchemeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .accessibilityIdentifier("settings.rewrite.schemePicker")

            Toggle("Use regular expression", isOn: Binding(
                get: { draft.match.useRegex },
                set: { draft.match.useRegex = $0; commit() }
            ))
            .accessibilityIdentifier("settings.rewrite.regexToggle")
        } header: {
            Text("Rewrite")
        }

        Section("Change the Link") {
            RewriteActionFieldsView(fields: $actionFields, onCommit: commit)
        }

        if let errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.rewrite.error")
                HStack {
                    Text("These changes aren’t saved until the error is fixed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Revert") { revert() }
                        .accessibilityIdentifier("settings.rewrite.revertButton")
                }
            }
        }

        Section("Only When") {
            labeledField("Clicked in") {
                SourceAppTokenList(bundleIDs: draft.match.sourceAppBundleIDs) { newValue in
                    draft.match.sourceAppBundleIDs = newValue
                    commit()
                }
                .accessibilityIdentifier("settings.rewrite.sourceApps")
            }

            labeledField("Except on hosts", optional: true) {
                TextField("Excluded hosts", text: $excludedHostsText, prompt: Text("localhost, *.local"))
                    .focused($focus, equals: .excludedHosts)
                    .onSubmit(commit)
                    .accessibilityIdentifier("settings.rewrite.excludeHostsField")
            }
        }
    }

    // MARK: Catalog (read-only)

    @ViewBuilder
    private var catalogSections: some View {
        Section {
            LabeledContent("Name", value: rule.name)
            LabeledContent("Match links on", value: rule.match.hostPattern == "*" ? "All sites" : rule.match.hostPattern)
            if let path = rule.match.pathPrefix, !path.isEmpty {
                LabeledContent("Path starts with", value: path)
            }
            if !rule.match.schemes.isEmpty {
                LabeledContent("Scheme", value: rule.match.schemes.joined(separator: ", "))
            }
            if !rule.match.excludeHostPatterns.isEmpty {
                LabeledContent("Except on hosts", value: rule.match.excludeHostPatterns.joined(separator: ", "))
            }
        } header: {
            Text("Rewrite")
        } footer: {
            Text(catalogFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Changes") {
            ForEach(Array(rule.actions.enumerated()), id: \.offset) { _, action in
                Text(action.reviewDescription)
                    .textSelection(.enabled)
            }
        }
    }

    private var catalogFooter: String {
        guard let provenance = rule.catalogProvenance else { return "" }
        return "From the Chowser catalog (v\(provenance.catalogVersion), key \(provenance.keyID)). Signed and verified, so it can’t be edited here. Duplicate it to make an editable copy."
    }

    // MARK: Commit

    private func commit() {
        guard !rule.isFromCatalog else { return }
        var candidate = draft
        candidate.isEnabled = rule.isEnabled
        candidate.match.schemes = schemeFilter.schemes
        candidate.actions = actionFields.buildActions()
        candidate.match.excludeHostPatterns = excludedHostsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard candidate != rule else {
            errorMessage = nil
            return
        }

        switch manager.updateRewriteRule(candidate) {
        case .success(let saved):
            errorMessage = nil
            if focus == nil { resync(to: saved) }
        case .failure(let error):
            errorMessage = error.message
        }
    }

    private func revert() {
        errorMessage = nil
        resync(to: rule)
    }

    private func resync(to rule: URLRewriteRule) {
        draft = rule
        schemeFilter = RewriteSchemeFilter(schemes: rule.match.schemes)
        actionFields = RewriteActionFieldsState.derive(from: rule.actions)
        excludedHostsText = rule.match.excludeHostPatterns.joined(separator: ", ")
    }

    // MARK: Building blocks

    private func labeledField<Content: View>(_ title: String, optional: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                if optional {
                    Text("(optional)")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            content()
                .labelsHidden()
        }
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Tester popover

/// Runs the exact same `RewritePipeline.apply` used at runtime (FR-025) and shows one
/// step per rewrite that fired (FR-021).
private struct RewriteTesterPopover: View {
    let manager: BrowserManager
    @State private var urlString = ""
    @State private var sourceAppBundleId = ""
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Test a Link")
                .font(.headline)

            TextField("Link", text: $urlString, prompt: Text("https://example.com/docs?utm_source=x"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($urlFocused)
                .accessibilityLabel("Link to test")
                .accessibilityIdentifier("settings.rewriteTester.urlField")

            TextField("Source app", text: $sourceAppBundleId, prompt: Text("Clicked in (bundle ID, optional)"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .font(.body.monospaced())
                .accessibilityLabel("Source app bundle ID")
                .accessibilityIdentifier("settings.rewriteTester.sourceAppField")

            Divider()

            result
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings.rewriteTester.result")
        }
        .padding(16)
        .frame(width: 380)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.rewriteTester.popover")
        .onAppear { urlFocused = true }
    }

    @ViewBuilder
    private var result: some View {
        if urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Paste or type a link to see how rewrites change it.")
                .foregroundStyle(.secondary)
        } else if let url = parsedURL {
            let trimmedSourceApp = sourceAppBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = RewritePipeline.apply(url: url, rules: manager.rewriteRules, sourceApp: trimmedSourceApp.isEmpty ? nil : trimmedSourceApp)

            if result.steps.isEmpty {
                Label("No rewrites change this link.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(result.steps) { step in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: step.skipped ? "exclamationmark.triangle.fill" : "arrow.right.circle.fill")
                                .foregroundStyle(step.skipped ? .orange : .green)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.ruleName)
                                    .fontWeight(.semibold)
                                if step.skipped {
                                    Text(step.skipReason ?? "Skipped")
                                        .font(.callout)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("→ \(step.afterURL.absoluteString)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }

                    Divider()

                    Text("Opens as \(result.finalURL.absoluteString)")
                        .fontWeight(.medium)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        } else {
            Label("That isn’t a complete link. Try https://example.com.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var parsedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), url.host != nil else { return nil }
        return url
    }
}

/// Explicit review surface for the signed rewrite catalog. Nothing starts selected; each
/// rule exposes its match scope, exact typed actions, and elevated-risk reasons before it
/// can be installed or updated.
struct RewriteCatalogSelectionSheet: View {
    let catalog: VerifiedRewriteCatalog
    let manager: BrowserManager
    @Binding var isPresented: Bool

    enum RuleStatus {
        case new, added, changed, conflict

        var label: String {
            switch self {
            case .new: return "New"
            case .added: return "Added"
            case .changed: return "Changed"
            case .conflict: return "Name conflict"
            }
        }

        var color: Color {
            switch self {
            case .new: return Color.accentColor
            case .added: return .secondary
            case .changed: return .orange
            case .conflict: return .red
            }
        }

        var icon: String {
            switch self {
            case .new: return "plus.circle"
            case .added: return "checkmark.circle.fill"
            case .changed: return "exclamationmark.arrow.triangle.2.circlepath"
            case .conflict: return "exclamationmark.triangle"
            }
        }
    }

    private struct Item: Identifiable {
        let id = UUID()
        let entry: RewriteCatalogEntry
        let status: RuleStatus
    }

    private var items: [Item] {
        catalog.catalog.rules.map { entry in
            let status: RuleStatus = switch catalog.status(for: entry, manager: manager) {
            case .new: .new
            case .added: .added
            case .changed: .changed
            case .conflict: .conflict
            }
            return Item(entry: entry, status: status)
        }
    }

    @State private var selected: Set<String> = []

    init(catalog: VerifiedRewriteCatalog, manager: BrowserManager, isPresented: Binding<Bool>) {
        self.catalog = catalog
        self.manager = manager
        self._isPresented = isPresented
        self._selected = State(initialValue: catalog.defaultSelectedEntryIDs)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.status.icon)
                            .foregroundStyle(item.status.color)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                Text(item.entry.name)
                                    .font(.system(size: 13, weight: .medium))
                                if item.entry.review.riskLevel == .elevated {
                                    Text("ELEVATED")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.16), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                            }
                            if !item.entry.summary.isEmpty {
                                Text(item.entry.summary)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Text("Match host: \(item.entry.hostPattern)\(item.entry.useRegex ? " (regular expression)" : "")")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            ForEach(item.entry.review.actionDescriptions, id: \.self) { action in
                                Text("• \(action)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            ForEach(item.entry.review.riskReasons, id: \.self) { reason in
                                Label(reason, systemImage: "exclamationmark.shield")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Text(item.status.label)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(item.status.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(item.status.color)
                        Toggle("", isOn: Binding(
                            get: { selected.contains(item.entry.id) },
                            set: { on in
                                if on { selected.insert(item.entry.id) } else { selected.remove(item.entry.id) }
                            }
                        ))
                        .labelsHidden()
                        .disabled(item.status == .added || item.status == .conflict)
                        .accessibilityIdentifier("catalog.rule.\(item.entry.id)")
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("catalog.row.\(item.entry.id)")
                }
            }
            .listStyle(.plain)
            footer
        }
        .frame(width: 660, height: 600)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catalog.selectionSheet")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20))
                .foregroundStyle(.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Predefined Rewrites")
                    .font(.system(size: 16, weight: .semibold))
                Text("Signed catalog v\(catalog.catalog.catalogVersion) · \(catalog.catalog.rules.count) rules · nothing selected automatically")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Verified with key \(catalog.provenance.keyID) · \(catalog.provenance.source == .cache ? "last-known-good cache" : "fresh download")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Clear Selection") { selected.removeAll() }
                .disabled(selected.isEmpty)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Text("\(selected.count) selected")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel) { isPresented = false }
                .keyboardShortcut(.cancelAction)
            Button("Add Selected") {
                let result = RewriteCatalogService.shared.applySelected(
                    catalog,
                    manager: manager,
                    selectedEntryIDs: selected
                )
                isPresented = false
                NotificationCenter.default.post(
                    name: NSNotification.Name("RewriteCatalogApplied"),
                    object: result
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
        .padding(16)
    }
}
