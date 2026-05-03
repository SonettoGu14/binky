import Foundation

enum WatchFolderPathResolver {

    static func normalizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    /// Prefer resolving the security-scoped bookmark (survives renames); fall back to `storedPath` only when it still exists as a directory.
    static func resolvedWatchDirectoryPath(bookmark: Data, storedPath: String) -> String? {
        if !bookmark.isEmpty {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    return normalizedPath(url.path)
                }
            }
        }
        let s = normalizedPath(storedPath)
        guard !s.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: s, isDirectory: &isDir), isDir.boolValue else { return nil }
        return s
    }

    /// Whether `file` sits under `root` (or equals it). Both paths are standardized.
    static func file(_ file: URL, isUnderRoot root: String) -> Bool {
        let r = normalizedPath(root)
        let f = normalizedPath(file.path)
        return f == r || f.hasPrefix(r + "/")
    }
}

enum WatchRouting: Equatable, Sendable {
    /// Use global downloads/watch root; rules from global custom rules if enabled.
    case global
    /// File belongs to one or more automations sharing the same inbox root.
    case automation(inboxRoot: URL, automationIDs: [UUID])
}

/// Builds watch paths from enabled automations + optional global watch folder.
struct WatchPipelineRegistry: Sendable {
    let globalPath: String?
    let automationPaths: [(UUID, String)]

    /// For tests and tooling; prefer ``init(prefs:)`` in app code.
    init(globalPath: String?, automationPaths: [(UUID, String)]) {
        self.globalPath = globalPath
        self.automationPaths = automationPaths.sorted { $0.1.count > $1.1.count }
    }

    init(prefs: BinkyPreferences) {
        let gpResolved: String? = {
            guard prefs.folderWatchEnabled else { return nil }
            if let resolved = WatchFolderPathResolver.resolvedWatchDirectoryPath(
                bookmark: prefs.watchedFolderBookmark,
                storedPath: prefs.watchedFolderPath
            ) {
                return resolved
            }
            let downloads = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
            return WatchFolderPathResolver.normalizedPath(downloads.path)
        }()

        var auto: [(UUID, String)] = []
        for a in prefs.savedPresets where a.isEnabled {
            guard let raw = WatchFolderPathResolver.resolvedWatchDirectoryPath(
                bookmark: a.watchFolderBookmark,
                storedPath: a.watchFolderPath
            ) else { continue }
            auto.append((a.id, raw))
        }

        self.init(globalPath: gpResolved, automationPaths: auto)
    }

    /// Longest matching automation root wins; all automations with that exact root apply (combined rules in preset order).
    func routing(for file: URL) -> WatchRouting {
        for (_, root) in automationPaths {
            guard WatchFolderPathResolver.file(file, isUnderRoot: root) else { continue }
            let matchingIDs = automationPaths
                .filter { $0.1 == root }
                .map(\.0)
            let rootURL = URL(fileURLWithPath: root).standardizedFileURL
            return .automation(inboxRoot: rootURL, automationIDs: matchingIDs)
        }
        if let g = globalPath, WatchFolderPathResolver.file(file, isUnderRoot: g) {
            return .global
        }
        return .global
    }

    /// Distinct directory paths for FSEvents (deduped).
    var watchedRootPaths: [String] {
        Self.allWatchedPaths(globalPath: globalPath, automationPaths: automationPaths)
    }

    static func allWatchedPaths(globalPath: String?, automationPaths: [(UUID, String)]) -> [String] {
        var paths: [String] = []
        var norm = Set<String>()
        for (_, root) in automationPaths {
            let n = WatchFolderPathResolver.normalizedPath(root)
            guard !n.isEmpty else { continue }
            if norm.insert(n).inserted { paths.append(root) }
        }
        if let g = globalPath, !g.isEmpty {
            let n = WatchFolderPathResolver.normalizedPath(g)
            if norm.insert(n).inserted { paths.append(g) }
        }
        return paths
    }

    /// Legacy helper: paths from unique presets only (for tests / migration).
    var presetPaths: [(UUID, String)] { automationPaths }
}

extension BinkyPreferences {

    /// Inbox layout root and automations contributing rules for files routed through folder watch.
    func sortContext(for fileURL: URL) -> (inboxRoot: URL, presets: [CompressionPreset]) {
        let reg = WatchPipelineRegistry(prefs: self)
        switch reg.routing(for: fileURL) {
        case .global:
            return (downloadsSortRootDirectory(), [])
        case .automation(let root, let ids):
            let idSet = Set(ids)
            let presets = savedPresets.filter { idSet.contains($0.id) }
            return (root, presets)
        }
    }
}
