import Foundation

public enum WatchFolderPathResolver {

    public static func normalizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    /// Prefer resolving the security-scoped bookmark (survives renames); fall back to `storedPath` only when it still exists as a directory.
    public static func resolvedWatchDirectoryPath(bookmark: Data, storedPath: String) -> String? {
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
    public static func file(_ file: URL, isUnderRoot root: String) -> Bool {
        let r = normalizedPath(root)
        let f = normalizedPath(file.path)
        return f == r || f.hasPrefix(r + "/")
    }
}

public enum WatchRouting: Equatable, Sendable {
    /// Use global downloads/watch root; rules from global custom rules if enabled.
    case global
    /// File belongs to one or more routines sharing the same inbox root.
    case routine(inboxRoot: URL, routineIDs: [UUID])
}

/// Builds watch paths from enabled routines + optional global watch folder.
public struct WatchPipelineRegistry: Sendable {
    public let globalPath: String?
    public let routinePaths: [(UUID, String)]

    /// For tests and tooling.
    public init(globalPath: String?, routinePaths: [(UUID, String)]) {
        self.globalPath = globalPath
        self.routinePaths = routinePaths.sorted { $0.1.count > $1.1.count }
    }

    /// Longest matching routine root wins; all routines with that exact root apply (combined rules in preset order).
    public func routing(for file: URL) -> WatchRouting {
        for (_, root) in routinePaths {
            guard WatchFolderPathResolver.file(file, isUnderRoot: root) else { continue }
            let matchingIDs = routinePaths
                .filter { $0.1 == root }
                .map(\.0)
            let rootURL = URL(fileURLWithPath: root).standardizedFileURL
            return .routine(inboxRoot: rootURL, routineIDs: matchingIDs)
        }
        if let g = globalPath, WatchFolderPathResolver.file(file, isUnderRoot: g) {
            return .global
        }
        return .global
    }

    /// Distinct directory paths for FSEvents (deduped).
    public var watchedRootPaths: [String] {
        Self.allWatchedPaths(globalPath: globalPath, routinePaths: routinePaths)
    }

    public static func allWatchedPaths(globalPath: String?, routinePaths: [(UUID, String)]) -> [String] {
        var paths: [String] = []
        var norm = Set<String>()
        for (_, root) in routinePaths {
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
    public var presetPaths: [(UUID, String)] { routinePaths }
}
