import AppKit

/// Controls whether Binky appears as a normal Dock app or menu-bar-only accessory.
enum BinkyActivationPolicy {
    /// When Dock is hidden, menu bar access must stay enabled.
    @MainActor
    static func normalizeMenuBarDefaultsAtLaunch() {
        let d = UserDefaults.standard
        if d.bool(forKey: "ui.menuBarOnlyMode"), !d.bool(forKey: "ui.showMenuBarIcon") {
            d.set(true, forKey: "ui.showMenuBarIcon")
        }
    }

    @MainActor
    static func apply(menuBarOnly: Bool) {
        _ = NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
    }
}
