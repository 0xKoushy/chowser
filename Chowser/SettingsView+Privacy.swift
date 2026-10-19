import SwiftUI
import AppKit

extension SettingsView {
    /// Settings ▸ Privacy: the single network-lookups switch (link previews and short-link
    /// expansion), the short-link services and timeout it governs, and local tracking
    /// cleanup.
    var privacySection: some View {
        @Bindable var manager = browserManager

        return SettingsDetailScaffold(
            title: "Privacy",
            subtitle: "Choose what Chowser may look up online before opening a link.",
            systemImage: "hand.raised",
            scrollsContent: true,
            content: {
                VStack(alignment: .leading, spacing: 20) {
                    if !browserManager.hasSeenNetworkPrivacyUpgradeNotice {
                        networkPrivacyUpgradeNote
                    }

                    SettingsGroup("Online Lookups") {
                        SettingsRow(
                            title: "Look up link details online",
                            subtitle: "Lets Chowser fetch page titles for link previews and follow short links (like bit.ly) to find where they really go. Turn off to keep every link on this Mac. Previews also need Link Preview turned on in Picker."
                        ) {
                            Toggle("Look up link details online", isOn: $manager.networkLookupsEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityIdentifier("settings.behavior.networkLookupsToggle")
                        }
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        shortLinksGroup
                        timeoutGroup
                    }
                    .disabled(!manager.networkLookupsEnabled)
                    .opacity(manager.networkLookupsEnabled ? 1 : 0.55)

                    SettingsGroup("Activity") {
                        SettingsRow(
                            title: "Keep activity data",
                            subtitle: "Full history lists the links you open. Stats only keeps website names. Off records nothing and deletes what's stored. \(Self.activityPrivacyFooter)"
                        ) {
                            ActivityLevelControl(manager: manager)
                                .accessibilityIdentifier("settings.privacy.activityLevelPicker")
                        }
                    }

                    SettingsGroup("Cleanup") {
                        SettingsRow(
                            title: "Remove tracking parameters",
                            subtitle: "Strips utm_source, fbclid, gclid and similar from links before they open. Works offline."
                        ) {
                            Toggle("Remove tracking parameters", isOn: $manager.trackingCleanupEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .accessibilityIdentifier("settings.behavior.trackingCleanupToggle")
                        }
                    }
                }
            }
        )
        .onAppear {
            browserManager.markNetworkPrivacyUpgradeNoticeSeen()
        }
        .accessibilityIdentifier("settings.privacySection")
    }

    // MARK: - Upgrade notice

    private var networkPrivacyUpgradeNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "network.slash")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Online lookups are now off by default")
                    .font(.callout.weight(.semibold))
                Text("Short-link expansion and link previews used to run automatically. Turn them back on below if you want them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.behavior.networkPrivacyUpgradeNote")
    }

    // MARK: - Short links

    private static let builtInShortenerList = "t.co, bit.ly, tinyurl.com, is.gd, buff.ly, ow.ly, goo.gl, lnkd.in"

    private var shortLinksGroup: some View {
        let userHosts = browserManager.userShortenerHosts.sorted()

        return SettingsGroup("Short Links") {
            SettingsRow(
                title: "Expand links from these services",
                subtitle: "Chowser asks the service where the link points, then routes the real address. Always included: \(Self.builtInShortenerList)."
            ) {
                EmptyView()
            }

            ForEach(userHosts, id: \.self) { host in
                SettingsDivider()
                userShortenerHostRow(host)
            }

            SettingsDivider()

            addShortenerHostRow
        }
    }

    private func userShortenerHostRow(_ host: String) -> some View {
        HStack(spacing: 10) {
            Text(host)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Remove \(host)", systemImage: "minus.circle") {
                browserManager.removeUserShortenerHost(host)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove \(host)")
            .accessibilityIdentifier("settings.privacy.removeShortenerHost")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var addShortenerHostRow: some View {
        let trimmed = newShortenerHost.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(spacing: 10) {
            TextField("Shortener domain", text: $newShortenerHost, prompt: Text("short.example.com"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit(addShortenerHost)
                .accessibilityLabel("New shortener domain")
                .accessibilityIdentifier("settings.behavior.addShortenerHostField")

            Button("Add", action: addShortenerHost)
                .disabled(trimmed.isEmpty)
                .accessibilityIdentifier("settings.privacy.addShortenerHostButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func addShortenerHost() {
        let trimmed = newShortenerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        browserManager.addUserShortenerHost(trimmed)
        newShortenerHost = ""
    }

    // MARK: - Timeout

    private var timeoutGroup: some View {
        @Bindable var manager = browserManager
        let seconds = manager.shortlinkResolutionTimeout

        return SettingsGroup("Timeout") {
            SettingsRow(
                title: "Give up after",
                subtitle: "If a lookup takes longer, the original link is used."
            ) {
                HStack(spacing: 8) {
                    Slider(value: $manager.shortlinkResolutionTimeout, in: 0.5...5.0, step: 0.5)
                        .frame(width: 160)
                        .accessibilityLabel("Give up after")
                        .accessibilityValue("\(seconds.formatted(.number.precision(.fractionLength(1)))) seconds")
                    Text("\(seconds.formatted(.number.precision(.fractionLength(1)))) s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .accessibilityIdentifier("settings.behavior.shortlinkTimeout")
            }
        }
    }
}
