import Combine
import Foundation

@MainActor
final class ChangelogStore: ObservableObject {
    static let lastSeenVersionKey = "changelog.lastSeenVersion"

    @Published private(set) var lastSeenVersion: String?

    private let defaults: UserDefaults
    private let currentVersion: String
    private let entries: [ChangelogEntry]

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String? = nil,
        entries: [ChangelogEntry] = ChangelogCatalog.entries
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion ?? Self.bundleVersion
        self.entries = entries
        lastSeenVersion = defaults.string(forKey: Self.lastSeenVersionKey)
    }

    func pendingPresentation() -> ChangelogPresentation? {
        let persistedVersion = defaults.string(forKey: Self.lastSeenVersionKey)
        if persistedVersion != lastSeenVersion {
            lastSeenVersion = persistedVersion
        }

        guard let currentEntry = entries.first(where: { $0.version == currentVersion }) else {
            return nil
        }
        guard lastSeenVersion != currentVersion else { return nil }

        guard
            let lastSeenVersion,
            let seen = AppReleaseVersion(lastSeenVersion),
            let current = AppReleaseVersion(currentVersion)
        else {
            return ChangelogPresentation(entries: [currentEntry])
        }

        guard seen < current else { return nil }
        let missedEntries = entries.filter { entry in
            guard let version = AppReleaseVersion(entry.version) else { return false }
            return seen < version && version <= current
        }
        guard !missedEntries.isEmpty else { return nil }
        return ChangelogPresentation(entries: missedEntries)
    }

    func markSeen(version: String) {
        guard !version.isEmpty else { return }
        defaults.set(version, forKey: Self.lastSeenVersionKey)
        lastSeenVersion = version
    }

    func markCurrentVersionSeen() {
        guard entries.contains(where: { $0.version == currentVersion }) else { return }
        markSeen(version: currentVersion)
    }

    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
