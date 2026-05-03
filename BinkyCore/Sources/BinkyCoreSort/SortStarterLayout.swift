import BinkyCoreShared
import Foundation

/// Enumerate regular files suitable for organizer passes (CLI + tooling).
/// Matches the app sweep: immediate files in ``root``, plus one level deeper when `recursiveOneLevel` is true.
public enum SortSweepFilesCollection {

    /// Files directly under `root`, plus regular files one level inside immediate subfolders when `recursiveOneLevel` is true.
    public static func files(in root: URL, recursiveOneLevel: Bool, fileManager fm: FileManager = .default) -> [URL] {
        guard let urls = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [URL] = []
        for url in urls {
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if vals?.isDirectory != true {
                files.append(url.standardizedFileURL)
                continue
            }
            guard recursiveOneLevel else { continue }
            guard let inner = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for u in inner {
                if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
                    files.append(u.standardizedFileURL)
                }
            }
        }
        return files
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
