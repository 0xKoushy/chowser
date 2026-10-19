import Foundation

/// How much Chowser remembers about the links it handles. Everything stays on this Mac.
enum ActivityLevel: String, CaseIterable, Identifiable, Decodable {
    case full
    case statsOnly
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Full history"
        case .statsOnly: return "Stats only"
        case .off: return "Off"
        }
    }

    /// Lowering the level deletes data the new level no longer allows.
    func isLowerThan(_ other: ActivityLevel) -> Bool {
        rank < other.rank
    }

    private var rank: Int {
        switch self {
        case .full: return 2
        case .statsOnly: return 1
        case .off: return 0
        }
    }
}

struct LinkHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// The cleaned URL (after rewrites, unshortening and cleanup). Reduced to scheme + host
    /// when the Activity level is "Stats only".
    let url: URL
    let sourceBundleID: String?
    let outcome: Outcome

    enum Outcome: Codable, Equatable {
        case browser(bundleID: String, profile: String?, viaRule: String?)
        case native(handlerBundleID: String)
        /// The picker closed without a choice (Esc, click-away).
        case dismissed
    }
}

/// Local log of every link Chowser received and what happened to it. Stored as a JSON file in
/// Application Support (inside the container in the App Store build), never sent anywhere.
@MainActor @Observable
final class LinkHistory {
    static let maxEntries = 500
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    static let shared = LinkHistory(
        fileURL: AppEnvironment.linkHistoryFileURLOverride ?? defaultFileURL,
        immediateWrite: false
    )

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Chowser/link-history.json", isDirectory: false)
    }

    /// Newest first.
    private(set) var entries: [LinkHistoryEntry] = []
    private(set) var level: ActivityLevel = .full

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let immediateWrite: Bool
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    init(fileURL: URL, immediateWrite: Bool = true) {
        self.fileURL = fileURL
        self.immediateWrite = immediateWrite

        if AppEnvironment.shouldClearDataOnLaunch {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: corruptFileURL)
        }
        load()
    }

    /// Records one handled link. Writes nothing for private-mode opens or when the level is Off.
    func record(
        url: URL,
        source: String?,
        outcome: LinkHistoryEntry.Outcome,
        isPrivate: Bool = false,
        date: Date = Date()
    ) {
        guard !isPrivate, level != .off else { return }
        let storedURL = level == .full ? url : Self.reducedToHost(url)
        guard let storedURL else { return }
        // The same link dismissed again (e.g. a reopen that was ignored) adds nothing new.
        if outcome == .dismissed, let last = entries.first, last.outcome == .dismissed, last.url == storedURL {
            return
        }

        entries.insert(
            LinkHistoryEntry(id: UUID(), date: date, url: storedURL, sourceBundleID: source, outcome: outcome),
            at: 0
        )
        prune(now: date)
        scheduleSave()
    }

    /// Applies a new level. Lowering it deletes what the new level no longer allows:
    /// "Stats only" strips URLs to their host, "Off" deletes the whole history.
    func setLevel(_ newLevel: ActivityLevel) {
        level = newLevel
        switch newLevel {
        case .full:
            break
        case .statsOnly:
            try? FileManager.default.removeItem(at: corruptFileURL)
            entries = entries.compactMap { entry in
                Self.reducedToHost(entry.url).map {
                    LinkHistoryEntry(id: entry.id, date: entry.date, url: $0, sourceBundleID: entry.sourceBundleID, outcome: entry.outcome)
                }
            }
            scheduleSave()
        case .off:
            clear()
        }
    }

    func clear() {
        pendingSave?.cancel()
        pendingSave = nil
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: corruptFileURL)
    }

    /// Where an unreadable history file is kept for inspection. It holds full URLs, so it is
    /// deleted along with the history whenever the level drops or the history is cleared.
    var corruptFileURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
    }

    func flushPendingSave() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        save()
    }

    /// The most recent link the user lost, for `chowser://reopen`. Nil when that link was
    /// opened again after being dismissed.
    var lastDismissed: LinkHistoryEntry? {
        guard let index = entries.firstIndex(where: { $0.outcome == .dismissed }) else { return nil }
        let entry = entries[index]
        return entries[..<index].contains { $0.url == entry.url } ? nil : entry
    }

    static func reducedToHost(_ url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        return components.url
    }

    /// Entries stay in recording order (newest first); sorting by date would let one entry
    /// stamped by a wrong clock stick at the top as "the last link".
    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        entries = Array(entries.filter { $0.date >= cutoff }.prefix(Self.maxEntries))
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? Self.decoder.decode([LinkHistoryEntry].self, from: data) else {
            // Keep an unreadable file for inspection instead of overwriting it on the next record.
            try? FileManager.default.removeItem(at: corruptFileURL)
            try? FileManager.default.moveItem(at: fileURL, to: corruptFileURL)
            AppLogger.error("LinkHistory", "History file could not be read; moved aside")
            return
        }
        entries = decoded.sorted { $0.date > $1.date }
        prune(now: Date())
    }

    private func save() {
        guard level != .off, let data = try? Self.encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func scheduleSave() {
        guard !immediateWrite else { save(); return }
        pendingSave?.cancel()
        var item: DispatchWorkItem!
        item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingSave === item else { return }
                self.pendingSave = nil
                self.save()
            }
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
