import Foundation

class DomainFrequencyTracker {
    static let shared = DomainFrequencyTracker()

    private let userDefaultsKey = "DomainFrequencyStats"
    private let maxEntries = 100
    private let defaults: UserDefaults
    /// Serial so a `clear()` can never be overtaken by an older in-flight write.
    private let writeQueue = DispatchQueue(label: "in.sreerams.Chowser.DomainFrequencyTracker", qos: .utility)

    private var cachedStats: [String: [String: Int]] = [:]

    /// False when the Activity level is Off: nothing is recorded and no suggestions are made.
    var isRecordingEnabled = true

    init(defaults: UserDefaults = AppEnvironment.makeDefaultStore()) {
        self.defaults = defaults
        if AppEnvironment.shouldClearDataOnLaunch {
            defaults.removeObject(forKey: userDefaultsKey)
        }
        cachedStats = loadFromDefaults()
    }

    /// Records a click for a domain and browser combination.
    func record(domain: String, browserBundleID: String) {
        guard isRecordingEnabled else { return }
        var domainStats = cachedStats[domain] ?? [:]
        domainStats[browserBundleID] = (domainStats[browserBundleID] ?? 0) + 1
        cachedStats[domain] = domainStats

        if cachedStats.count > maxEntries {
            if let firstKey = cachedStats.keys.first {
                cachedStats.removeValue(forKey: firstKey)
            }
        }

        let snapshot = cachedStats
        writeQueue.async { [defaults, userDefaultsKey] in
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: userDefaultsKey)
            }
        }
    }

    /// Returns click counts per browser bundle ID for a given domain.
    func stats(for domain: String) -> [String: Int] {
        guard isRecordingEnabled else { return [:] }
        return cachedStats[domain.lowercased()] ?? [:]
    }

    /// Deletes all recorded click data.
    func clear() {
        cachedStats = [:]
        writeQueue.async { [defaults, userDefaultsKey] in
            defaults.removeObject(forKey: userDefaultsKey)
        }
    }

    private func loadFromDefaults() -> [String: [String: Int]] {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let stats = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else {
            return [:]
        }
        return stats
    }
}
