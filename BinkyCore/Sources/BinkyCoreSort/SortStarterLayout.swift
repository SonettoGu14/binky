import BinkyCoreShared
import Foundation

/// Files and optional loose directories to process in one sweep (matches app + CLI organizer passes).
public struct SortSweepWorkItems: Sendable {
    public var fileURLs: [URL]
    public var looseFolderURLs: [URL]

    public init(fileURLs: [URL], looseFolderURLs: [URL] = []) {
        self.fileURLs = fileURLs
        self.looseFolderURLs = looseFolderURLs
    }

    public init() {
        self.fileURLs = []
        self.looseFolderURLs = []
    }

    public var hasAnyWork: Bool { !fileURLs.isEmpty || !looseFolderURLs.isEmpty }
}

/// Enumerate regular files suitable for organizer passes (CLI + tooling).
/// Matches the app sweep: immediate files in ``root``, plus one level deeper when `recursiveOneLevel` is true.
public enum SortSweepFilesCollection {

    /// Files directly under `root`, plus regular files one level inside immediate subfolders when `recursiveOneLevel` is true.
    public static func files(in root: URL, recursiveOneLevel: Bool, fileManager fm: FileManager = .default) -> [URL] {
        workItems(in: root, recursiveOneLevel: recursiveOneLevel, moveLooseFolders: false, fileManager: fm).fileURLs
    }

    /// Full sweep: loose files, optional loose folders to relocate as units, and `.app` bundles as file-phase items.
    public static func workItems(
        in root: URL,
        recursiveOneLevel: Bool,
        moveLooseFolders: Bool,
        fileManager fm: FileManager = .default
    ) -> SortSweepWorkItems {
        let rootStd = root.standardizedFileURL
        let builtIns = FileSortCategory.builtinDestinationDirectoryNamesLowercased
        guard let urls = try? fm.contentsOfDirectory(at: rootStd, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return SortSweepWorkItems()
        }

        var looseFolders: [URL] = []
        var opaqueFolderPaths: Set<String> = []

        if moveLooseFolders {
            for url in urls {
                let std = url.standardizedFileURL
                let vals = try? std.resourceValues(forKeys: [.isDirectoryKey])
                guard vals?.isDirectory == true else { continue }
                let name = std.lastPathComponent
                if name.hasPrefix(".") { continue }
                let lower = name.lowercased()
                if builtIns.contains(lower) { continue }
                if std.pathExtension.lowercased() == "app" { continue }
                looseFolders.append(std)
                opaqueFolderPaths.insert(std.path)
            }
        }

        var files: [URL] = []
        for url in urls {
            let std = url.standardizedFileURL
            let vals = try? std.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = vals?.isDirectory == true

            if !isDir {
                files.append(std)
                continue
            }

            if std.pathExtension.lowercased() == "app" {
                files.append(std)
                continue
            }

            if opaqueFolderPaths.contains(std.path) {
                continue
            }

            guard recursiveOneLevel else { continue }
            guard let inner = try? fm.contentsOfDirectory(at: std, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for u in inner {
                if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
                    files.append(u.standardizedFileURL)
                }
            }
        }

        return SortSweepWorkItems(fileURLs: files, looseFolderURLs: looseFolders)
    }
}

/// Default folders under each inbox root.
public enum StarterDestinations {

    public static func directory(for cat: FileSortCategory, root: URL) -> URL {
        root.appendingPathComponent(cat.downloadsSubfolder, isDirectory: true)
    }

    public static func ensure(downloadsRoot root: URL) {
        let fm = FileManager.default
        FileSortCategory.allCases.forEach { cat in
            try? fm.createDirectory(at: directory(for: cat, root: root), withIntermediateDirectories: true)
        }
    }
}

/// Finder-style uniqueness for destination filenames (shared across UI, aging, CLI).
public enum SortCollision {

    nonisolated public static func uniquify(destinationDirectory folder: URL, preferredFilename name: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        let ext = URL(fileURLWithPath: name).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var n = 2
        repeat {
            let next = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            candidate = folder.appendingPathComponent(next)
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }
}
