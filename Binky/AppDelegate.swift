import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticsReporter.shared.startMonitoring()
        UNUserNotificationCenter.current().delegate = self
        GlobalHotkeyManager.shared.syncFromDefaults()
        NewTagExpiryService.shared.start()
        UserDefaults.standard.register(defaults: [
            "ui.showMenuBarIcon": true,
            "ui.menuBarOnlyMode": false,
        ])
        BinkyActivationPolicy.normalizeMenuBarDefaultsAtLaunch()
        BinkyActivationPolicy.apply(menuBarOnly: UserDefaults.standard.bool(forKey: "ui.menuBarOnlyMode"))
        BinkyMenuBarController.shared.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DiagnosticsReporter.shared.clearSentinel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

    /// Accepts files and folders. Folders are expanded into their top-level files by
    /// ``OrganizerViewModel/sortIncomingFiles(_:prefs:)`` and treated as their own ad-hoc inbox.
    private func acceptedURLs(from urls: [URL]) -> [URL] {
        urls.filter { url in
            FileManager.default.fileExists(atPath: url.path)
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
