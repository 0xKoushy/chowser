import Foundation

/// Keeps each incoming link and its click context until routing or picker handling ends.
struct IncomingURLQueue {
    struct Entry: Equatable {
        let id: UUID
        let url: URL
        let sourceApp: String?
        let forceShowPicker: Bool
        let privateModeRequested: Bool

        init(
            url: URL, sourceApp: String?, forceShowPicker: Bool,
            privateModeRequested: Bool, id: UUID = UUID()
        ) {
            self.id = id
            self.url = url
            self.sourceApp = sourceApp
            self.forceShowPicker = forceShowPicker
            self.privateModeRequested = privateModeRequested
        }
    }

    private(set) var active: Entry?
    private var pending: [Entry] = []

    mutating func enqueue(_ entries: [Entry]) -> Entry? {
        pending.append(contentsOf: entries)
        return startNextIfIdle()
    }

    mutating func replaceActive(with entry: Entry) -> Entry? {
        guard active != nil else { return nil }
        active = entry
        return entry
    }

    mutating func finishActive() -> Entry? {
        guard active != nil else { return nil }
        active = nil
        return startNextIfIdle()
    }

    private mutating func startNextIfIdle() -> Entry? {
        guard active == nil, !pending.isEmpty else { return nil }
        active = pending.removeFirst()
        return active
    }
}
