import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var globalPasteHotkeyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migratePDFMaxFileSizeIfNeeded()
        DiagnosticsReporter.shared.startMonitoring()
        UNUserNotificationCenter.current().delegate = self
        GlobalHotkeyManager.shared.syncFromDefaults()
        globalPasteHotkeyObserver = NotificationCenter.default.addObserver(
            forName: .binkyGlobalPasteHotkeyChanged,
            object: nil,
            queue: .main
        ) { _ in
            GlobalHotkeyManager.shared.syncFromDefaults()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticsReporter.shared.clearSentinel()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let runTeardown = {
            var iterations = 0
            while iterations < 16, NSApp.modalWindow != nil {
                NSApp.abortModal()
                iterations += 1
            }
            NotificationCenter.default.post(name: .binkyPrepareQuit, object: nil)
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
        }
        if Thread.isMainThread {
            runTeardown()
        } else {
            DispatchQueue.main.async(execute: runTeardown)
        }
        return .terminateLater
    }

    // MARK: - Open with Binky / drag onto Dock icon

    func application(_ application: NSApplication, open urls: [URL]) {
        let accepted = acceptedURLs(from: urls)
        guard !accepted.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .binkyOpenFiles, object: accepted)
    }

    // MARK: - Clipboard Compress menu command

    @objc func compressFromClipboard(_ sender: Any?) {
        NotificationCenter.default.post(name: .binkyPasteClipboard, object: nil)
    }

    // MARK: - Right-click → Services → Sort with Binky

    @objc func sortWithBinky(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        // Accept any file URL from Finder Services / Quick Actions (organizer routes unknown types to Review).
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              !urls.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .binkyOpenFiles, object: urls)
    }

    // MARK: - Helpers

    private func acceptedURLs(from urls: [URL]) -> [URL] {
        urls.filter { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
            return !isDir.boolValue
        }
    }

    /// Older builds allowed sub‑MB targets; clamp global PDF max size to 5–25 MB to match current presets.
    private func migratePDFMaxFileSizeIfNeeded() {
        let key = "pdfMaxFileSizeKB"
        let v = UserDefaults.standard.integer(forKey: key)
        guard v != 0 else { return }
        let clamped = clampPDFMaxFileSizeKB(v)
        if clamped != v {
            UserDefaults.standard.set(clamped, forKey: key)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Allow banners to appear even when Binky is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
