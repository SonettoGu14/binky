import AppKit
import Foundation

enum ClipboardImport {
    case localFile(URL)
    case remoteURL(URL)
}

enum ClipboardImporter {
    /// Same rules as drag-and-drop: local file, raw image bytes, or an `https` link to a direct media file.
    static func importFromClipboard() -> ClipboardImport? {
        let pb = NSPasteboard.general

        // Prefer a file URL (user did Copy in Finder) — no re-encoding needed
        let fileOpts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: fileOpts) as? [URL],
           let url = urls.first,
           MediaTypeDetector.detect(url) != nil {
            return .localFile(url)
        }

        // Fallback: raw image bytes (screenshot, browser copy, etc.)
        // Prefer PNG over TIFF — smaller temp file, lossless, widely supported by our encoders
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            let ext = pb.data(forType: .png) != nil ? "png" : "tiff"
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("binky_paste_\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try? data.write(to: tmp, options: .atomic)
            return .localFile(tmp)
        }

        // `NSURL` on pasteboard (Safari address bar, etc.) — may be `https` or `file`
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL], let u = urls.first {
            if u.isFileURL, MediaTypeDetector.detect(u) != nil {
                return .localFile(u)
            }
            if let s = u.scheme?.lowercased(), s == "http" || s == "https" {
                return .remoteURL(u)
            }
        }

        // Plain text URL (first line only)
        if let s = pb.string(forType: .string),
           let url = firstHTTPURL(in: s) {
            return .remoteURL(url)
        }

        return nil
    }

    /// First `http(s)` URL on the first line of `text` (paste one link at a time).
    static func firstHTTPURL(in text: String) -> URL? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: trimmed), let s = u.scheme?.lowercased(), s == "http" || s == "https" else { return nil }
        return u
    }

    /// True when `importFromClipboard()` would return a value.
    static func isClipboardImportable() -> Bool {
        importFromClipboard() != nil
    }
}
