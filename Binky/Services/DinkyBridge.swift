import AppKit
import Foundation

/// Detects Dinky (`com.dinky.app`) and opens files or folders in it for compression or watch-folder setup.
enum DinkyBridge {
    static let bundleID = "com.dinky.app"

    static let marketingURL = URL(string: "https://dinkyapp.com")!

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Opens the given file URLs in Dinky (one-time handoff).
    @discardableResult
    static func openFiles(_ urls: [URL], completion: ((Bool) -> Void)? = nil) -> Bool {
        open(urls, completion: completion)
    }

    /// Opens a folder in Dinky so the user can add it as a watch folder there.
    @discardableResult
    static func openFolder(_ folderURL: URL, completion: ((Bool) -> Void)? = nil) -> Bool {
        open([folderURL], completion: completion)
    }

    @discardableResult
    private static func open(_ urls: [URL], completion: ((Bool) -> Void)? = nil) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            if let completion { DispatchQueue.main.async { completion(false) } }
            return false
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: cfg, completionHandler: { _, error in
            DispatchQueue.main.async {
                completion?(error == nil)
            }
        })
        return true
    }

    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif",
        "tif", "tiff", "bmp",
        "pdf",
        "mp4", "mov", "m4v", "avi", "mkv", "webm",
    ]

    static func compressibleURLs(from urls: [URL]) -> [URL] {
        urls.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
    }

    static func uniqueFolders(containing urls: [URL]) -> [URL] {
        Array(Set(urls.map { $0.deletingLastPathComponent() }))
            .sorted { $0.path < $1.path }
    }
}
