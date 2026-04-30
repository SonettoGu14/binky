import Foundation
import ServiceManagement
import os.log

/// Wraps `SMAppService.mainApp` so the rest of the app can toggle "Launch at login"
/// without having to know the registration ceremony or interpret status codes.
///
/// `SMAppService.mainApp` is the modern (macOS 13+) replacement for the old
/// `LSSharedFileList` / login items API. The system handles the launchd glue and
/// surfaces a System Settings → General → Login Items entry under our bundle
/// identifier — there is no helper bundle to ship.
enum LaunchAtLoginManager {
    private static let log = Logger(subsystem: "com.binky.app", category: "LaunchAtLogin")

    /// `true` when the system is configured to launch Binky at login for the current user.
    /// Reads live from `SMAppService` so it stays in sync if the user toggles the
    /// item from System Settings.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `true` if the user has revoked or never approved the login item — useful to
    /// nudge them to System Settings instead of silently failing.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers or unregisters the main app as a login item. Returns `true` on
    /// success. Failures are logged; callers should re-read `isEnabled` to refresh UI.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
            return true
        } catch {
            log.error("Failed to \(enabled ? "register" : "unregister", privacy: .public) login item: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Opens the Login Items pane so the user can grant approval if the system
    /// flagged our service as `.requiresApproval`.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
