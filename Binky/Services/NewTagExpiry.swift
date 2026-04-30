import Foundation

/// Tracks sorted files that received the `"New"` Finder tag and strips it after a per-profile TTL.
@MainActor
final class NewTagExpiryService {

    static let shared = NewTagExpiryService()

    private struct Store: Codable {
        var entries: [Entry]
    }

    private struct Entry: Codable {
        /// Security-scoped bookmark to the file after sort.
        var bookmarkData: Data
        var appliedAt: Date
        /// Snapshot of profile setting when registered (days until expiry).
        var expiryDays: Int
    }

    private let fileURL: URL
    private var timer: Timer?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = support.appendingPathComponent("Binky", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("new_tag_expiry.json", isDirectory: false)
    }

    func start() {
        sweep()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweep() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Registers `file` for stripping `"New"` after `expiryDays` (ignored when ≤ 0).
    func register(file: URL, expiryDays: Int) {
        guard expiryDays > 0 else { return }
        guard let data = try? file.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }

        let store = loadStore()
        var nextEntries = store.entries
        nextEntries.removeAll { existing in
            existing.bookmarkData == data
        }
        nextEntries.append(Entry(bookmarkData: data, appliedAt: Date(), expiryDays: expiryDays))
        saveStore(Store(entries: nextEntries))
    }

    private func loadStore() -> Store {
        guard let raw = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Store.self, from: raw)
        else {
            return Store(entries: [])
        }
        return decoded
    }

    private func saveStore(_ store: Store) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func sweep() {
        let store = loadStore()
        guard !store.entries.isEmpty else { return }

        let now = Date()
        var kept: [Entry] = []

        for entry in store.entries {
            let maxAge = TimeInterval(entry.expiryDays) * 86400
            if now.timeIntervalSince(entry.appliedAt) < maxAge {
                kept.append(entry)
                continue
            }

            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: entry.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }

            FinderTagApplicator.remove(tagNames: ["New"], from: url)
        }

        if kept.count != store.entries.count {
            saveStore(Store(entries: kept))
        }
    }
}
