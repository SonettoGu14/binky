import Foundation

enum CompressionUndoError: LocalizedError {
    case outputMissing
    case recoveryMissing
    case destinationBlocked(URL)
    case moveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .outputMissing:
            return String(localized: "The compressed file is no longer at its saved location.", comment: "Undo error.")
        case .recoveryMissing:
            return String(localized: "The original file is no longer in the Trash or backup folder.", comment: "Undo error.")
        case .destinationBlocked(let url):
            return String.localizedStringWithFormat(
                String(localized: "Something else is already at %@.", comment: "Undo error; argument is a path."),
                url.path
            )
        case .moveFailed(let err):
            return err.localizedDescription
        }
    }
}

enum CompressionUndo {
    /// Reverses a successful compression using the captured snapshot.
    static func undo(snapshot: CompressionUndoSnapshot) throws {
        let fm = FileManager.default
        let out = snapshot.outputURL.standardizedFileURL
        let src = snapshot.sourceURL.standardizedFileURL

        if snapshot.isURLDownloadSource {
            if fm.fileExists(atPath: out.path) {
                try fm.removeItem(at: out)
            }
            return
        }

        if let recovery = snapshot.originalRecoveryURL?.standardizedFileURL {
            guard fm.fileExists(atPath: recovery.path) else {
                throw CompressionUndoError.recoveryMissing
            }
            guard fm.fileExists(atPath: out.path) else {
                throw CompressionUndoError.outputMissing
            }

            let samePath = out.path == src.path
            if samePath {
                let compressedInTrash = try trashOrRemove(at: out)
                defer {
                    if let t = compressedInTrash { try? fm.removeItem(at: t) }
                }
                try fm.moveItem(at: recovery, to: src)
            } else {
                _ = try trashOrRemove(at: out)
                if fm.fileExists(atPath: src.path) {
                    throw CompressionUndoError.destinationBlocked(src)
                }
                try fm.moveItem(at: recovery, to: src)
            }
            return
        }

        guard fm.fileExists(atPath: src.path) else {
            throw CompressionUndoError.recoveryMissing
        }
        guard out.path != src.path else { return }
        guard fm.fileExists(atPath: out.path) else {
            throw CompressionUndoError.outputMissing
        }
        try fm.removeItem(at: out)
    }

    /// Moves to Trash when possible so the user can recover if something goes wrong; otherwise removes.
    private static func trashOrRemove(at url: URL) throws -> URL? {
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            return resulting as URL?
        } catch {
            try FileManager.default.removeItem(at: url)
            return nil
        }
    }
}
