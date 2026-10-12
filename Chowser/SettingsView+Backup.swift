import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension SettingsView {
    /// Settings ▸ Backup & Advanced: export/import of browsers, rules, and rewrites,
    /// moving from the App Store build, import behavior, the local developer API, AI
    /// setup, diagnostics, and reset.
    var backupSection: some View {
        @Bindable var manager = browserManager

        return SettingsDetailScaffold(
            title: "Backup & Advanced",
            subtitle: "Move your setup between Macs and reach developer tools.",
            systemImage: "archivebox",
            scrollsContent: true,
            content: {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsGroup("Backup") {
                        SettingsRow(
                            title: "Browsers, rules, and rewrites",
                            subtitle: "Export saves three files in a new folder you can keep or move to another Mac."
                        ) {
                            HStack(spacing: 8) {
                                Button("Export All…", action: exportAll)
                                    .accessibilityIdentifier("settings.backup.exportAllButton")

                                Menu("Import") {
                                    Button("From an Exported Folder…", action: importAllFromFolder)
                                        .accessibilityIdentifier("settings.backup.importFolderButton")
                                    Divider()
                                    Button("Browsers…", action: importBrowsers)
                                    Button("Rules…", action: importRules)
                                    Button("Rewrites…", action: importRewrites)
                                }
                                .fixedSize()
                                .accessibilityIdentifier("settings.backup.importMenu")
                            }
                        }

                        #if DIRECT_DISTRIBUTION
                        if BrowserManager.hasAppStoreInstallPreferences {
                            SettingsDivider()

                            SettingsRow(
                                title: "Import from the App Store version",
                                subtitle: "Copies browsers, rules, and rewrites from the App Store or TestFlight install on this Mac."
                            ) {
                                Button("Import…", action: importFromAppStoreInstall)
                                    .accessibilityIdentifier("settings.importFromAppStoreInstall")
                            }
                        }
                        #endif
                    }

                    SettingsGroup("When Importing") {
                        SettingsRow(title: "Skip browsers that already exist") {
                            Toggle("Skip browsers that already exist", isOn: $manager.skipExistingImportedBrowsers)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityIdentifier("settings.importBrowsersSkipExisting")
                        }

                        SettingsDivider()

                        SettingsRow(
                            title: "Skip rules and rewrites that already exist",
                            subtitle: "When off, matching items are replaced by the imported version."
                        ) {
                            Toggle("Skip rules and rewrites that already exist", isOn: $manager.skipExistingImportedRules)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityIdentifier("settings.importRulesSkipExisting")
                        }
                    }

                    SettingsGroup("Advanced") {
                        MCPServerSettingsRow()

                        SettingsDivider()

                        SettingsRow(
                            title: "Set up with AI",
                            subtitle: "Copies a prompt that lets an AI assistant write your rules through the developer API."
                        ) {
                            Button("Set Up with AI…") { AISetup.run() }
                                .accessibilityIdentifier("settings.backup.aiSetupButton")
                        }

                        SettingsDivider()

                        SettingsRow(
                            title: "Diagnostics",
                            subtitle: "Recent startup, App Mode, and window events, with link addresses removed. Export a support report from there."
                        ) {
                            Button("Open Diagnostics…") {
                                DiagnosticsWindowController.shared.showDiagnostics()
                            }
                            .accessibilityIdentifier("settings.diagnosticsButton")
                        }
                    }

                    SettingsGroup("Start Over") {
                        SettingsRow(
                            title: "Replay onboarding",
                            subtitle: "Open the Welcome and Setup flow again."
                        ) {
                            Button("Replay") {
                                OnboardingManager.shared.resetOnboarding()
                                OnboardingManager.shared.showOnboardingWindow {}
                            }
                            .accessibilityIdentifier("settings.backup.replayOnboardingButton")
                        }

                        SettingsDivider()

                        SettingsRow(
                            title: "Reset setup",
                            subtitle: "Restores the first-launch browser setup with Safari as option 1."
                        ) {
                            Button("Reset…", role: .destructive) {
                                showingResetConfirmation = true
                            }
                            .accessibilityIdentifier("settings.resetButton")
                        }
                    }
                }
            }
        )
        .accessibilityIdentifier("settings.backupSection")
    }

    // MARK: - Export / import everything

    private static let backupFileNames = (
        browsers: "ChowserBrowsers.json",
        rules: "ChowserRules.json",
        rewrites: "ChowserRewrites.json"
    )

    /// Writes the three existing per-type exports into a new, dated folder so nothing
    /// already on disk is overwritten.
    private func exportAll() {
        let panel = NSOpenPanel()
        panel.title = "Export Chowser Settings"
        panel.message = "Choose where to save. Chowser creates a new folder with your browsers, rules, and rewrites."
        panel.prompt = "Export"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        var folder = parent.appendingPathComponent("Chowser Settings \(formatter.string(from: Date()))", isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = parent.appendingPathComponent("Chowser Settings \(formatter.string(from: Date())) \(suffix)", isDirectory: true)
            suffix += 1
        }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try browserManager.exportBrowsers(to: folder.appendingPathComponent(Self.backupFileNames.browsers))
            try browserManager.exportRules(to: folder.appendingPathComponent(Self.backupFileNames.rules))
            try browserManager.exportRewrites(to: folder.appendingPathComponent(Self.backupFileNames.rewrites))
            presentSettingsMessage(
                "Export complete",
                "Saved \(browserManager.configuredBrowsers.count) browsers, \(browserManager.routingRules.count) rules, and \(browserManager.rewriteRules.count) rewrites to “\(folder.lastPathComponent)”."
            )
        } catch {
            presentSettingsMessage("Export failed", "Could not export your settings.\n\n\(error.localizedDescription)")
        }
    }

    /// Imports whichever of the three export files are present in a folder made by
    /// Export All (or by the per-page exports, which use the same file names).
    private func importAllFromFolder() {
        let panel = NSOpenPanel()
        panel.title = "Import Chowser Settings"
        panel.message = "Choose a folder created by Export All."
        panel.prompt = "Import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let names = Self.backupFileNames
        let fileManager = FileManager.default
        let browsersURL = folder.appendingPathComponent(names.browsers)
        let rulesURL = folder.appendingPathComponent(names.rules)
        let rewritesURL = folder.appendingPathComponent(names.rewrites)

        var lines: [String] = []
        var failures: [String] = []

        // Browsers first so imported rules can resolve their browsers.
        if fileManager.fileExists(atPath: browsersURL.path) {
            do {
                let summary = try browserManager.importBrowsers(from: browsersURL, skipExisting: browserManager.skipExistingImportedBrowsers)
                lines.append(Self.summaryLine("Browsers", summary))
            } catch {
                failures.append("Browsers: \(error.localizedDescription)")
            }
        }
        if fileManager.fileExists(atPath: rulesURL.path) {
            do {
                let summary = try browserManager.importRules(from: rulesURL, skipExisting: browserManager.skipExistingImportedRules)
                lines.append(Self.summaryLine("Rules", summary))
            } catch {
                failures.append("Rules: \(error.localizedDescription)")
            }
        }
        if fileManager.fileExists(atPath: rewritesURL.path) {
            do {
                let summary = try browserManager.importRewrites(from: rewritesURL, skipExisting: browserManager.skipExistingImportedRules)
                lines.append(Self.summaryLine("Rewrites", summary))
            } catch {
                failures.append("Rewrites: \(error.localizedDescription)")
            }
        }

        if lines.isEmpty && failures.isEmpty {
            presentSettingsMessage(
                "Nothing to import",
                "That folder doesn’t contain \(names.browsers), \(names.rules), or \(names.rewrites)."
            )
            return
        }

        var message = lines.joined(separator: "\n")
        if !failures.isEmpty {
            message += (message.isEmpty ? "" : "\n\n") + "Couldn’t import:\n" + failures.joined(separator: "\n")
        }
        presentSettingsMessage(failures.isEmpty ? "Import complete" : "Import finished with problems", message)
    }

    private static func summaryLine(_ name: String, _ summary: BrowserManager.ImportSummary) -> String {
        "\(name): \(summary.added) added, \(summary.updated) updated, \(summary.skipped + summary.invalid) skipped"
    }

    #if DIRECT_DISTRIBUTION
    private func importFromAppStoreInstall() {
        do {
            let summary = try browserManager.importFromAppStoreInstall()
            let lines = [("Browsers", summary.browsers), ("Rules", summary.rules), ("Rewrites", summary.rewrites)]
                .map { name, part in "\(name): \(part.added) added, \(part.updated) updated, \(part.skipped + part.invalid) skipped" }
            presentSettingsMessage("Imported from the App Store version", lines.joined(separator: "\n"))
        } catch {
            presentSettingsMessage(
                "Import failed",
                "Chowser couldn't read the App Store version's settings. If macOS asked to allow access to another app's data, choose Allow and try again. You can also export from the App Store version and import the files here.\n\n\(error.localizedDescription)"
            )
        }
    }
    #endif
}

/// Developer API (local MCP/HTTP server) controls: start/stop, bearer token, auto-start.
struct MCPServerSettingsRow: View {
    @State private var tokenCopied = false

    private let server = MCPServer.shared
    @Bindable private var manager = BrowserManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer API server")
                        .font(.system(size: 13, weight: .medium))

                    Text(verbatim: server.isRunning
                        ? "Running at http://localhost:\(String(server.port)). Only apps on this Mac can connect, with the token below."
                        : "Lets local tools and AI assistants manage your browsers and rules. Only apps on this Mac can connect.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button(server.isRunning ? "Stop" : "Start") {
                    if server.isRunning {
                        server.stop()
                    } else {
                        server.start()
                    }
                }
                .accessibilityIdentifier("settings.mcpServerToggle")
            }

            if server.isRunning {
                HStack(spacing: 8) {
                    Text(server.authToken)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("settings.mcpAuthToken")

                    Spacer(minLength: 0)

                    Button(tokenCopied ? "Copied" : "Copy Token", systemImage: tokenCopied ? "checkmark" : "doc.on.clipboard") {
                        copyToken()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(tokenCopied ? .green : .secondary)
                }
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start automatically at launch")
                        .font(.system(size: 12))
                    Text("Or from Terminal: defaults write in.sreerams.Chowser mcpAutoStartEnabled -bool true")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 16)
                Toggle("Start automatically at launch", isOn: $manager.mcpAutoStartEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("settings.mcpAutoStart")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(server.authToken, forType: .string)
        tokenCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            tokenCopied = false
        }
    }
}
