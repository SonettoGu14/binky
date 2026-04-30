import Foundation

/// Central place for "what happens to the original file after a successful compress."
enum OriginalsHandler {

    /// Move to trash, move to backup folder, or leave in place.
    /// - Returns: URL where the original can be recovered from (Trash or backup path), or `nil` when nothing was moved.
    @discardableResult
    static func dispose(originalAt url: URL, action: OriginalsAction, backupFolder: URL?) throws -> URL? {
        switch action {
        case .keep:
            return nil
        case .trash:
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            return resulting as URL?
        case .backup:
            guard let folder = backupFolder else {
                throw OriginalsHandlerError.missingBackupFolder
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = uniqueDestination(in: folder, for: url)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    /// When **Replace original** is on, the source may need to leave its path so the output can take its name.
    /// If the user chose **Keep** originals, we only remove the source when `outputURL` is the same path
    /// (otherwise the write would fail). When output goes elsewhere (e.g. Desktop vs Dropbox), the source stays.
    /// Trash and Backup use the same paths as normal disposal.
    /// - Returns: Recovery URL when the original was moved, or `nil`.
    @discardableResult
    static func disposeForReplace(
        originalAt url: URL,
        outputURL: URL,
        action: OriginalsAction,
        backupFolder: URL?
    ) throws -> URL? {
        let collides = url.standardizedFileURL.path == outputURL.standardizedFileURL.path
        switch action {
        case .keep:
            if collides { return try dispose(originalAt: url, action: .trash, backupFolder: nil) }
            return nil
        case .trash:
            return try dispose(originalAt: url, action: .trash, backupFolder: nil)
        case .backup:
            return try dispose(originalAt: url, action: .backup, backupFolder: backupFolder)
        }
    }

    /// PDF/video temp export writes to a temp file then moves to `finalURL`. The source at `originalAt` must leave
    /// its path first. Uses the same originals policy as normal disposal; for **Keep**, moves to Trash so undo can restore.
    /// - Returns: Recovery URL for the original file.
    static func disposeSourceBeforeTempSwap(
        originalAt url: URL,
        action: OriginalsAction,
        backupFolder: URL?
    ) throws -> URL? {
        switch action {
        case .keep:
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try dispose(originalAt: url, action: .trash, backupFolder: nil)
        case .trash:
            return try dispose(originalAt: url, action: .trash, backupFolder: nil)
        case .backup:
            return try dispose(originalAt: url, action: .backup, backupFolder: backupFolder)
        }
    }
}

enum OriginalsHandlerError: LocalizedError {
    case missingBackupFolder

    var errorDescription: String? {
        switch self {
        case .missingBackupFolder:
            return "Backup folder is not set or could not be accessed."
        }
    }
}

// MARK: - Unique name (Finder-style "name (1).ext")

extension OriginalsHandler {
    /// Picks `name.ext`, then `name (1).ext`, `name (2).ext`, … until unused in `folder`.
    static func uniqueDestination(in folder: URL, for original: URL) -> URL {
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let stem = "\(base) (\(n))"
            candidate = folder.appendingPathComponent(stem).appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
