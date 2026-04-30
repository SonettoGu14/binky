import AppKit

/// Minimal menu bar controls: sort, pause/resume watch, show main window, Settings.
@MainActor
final class BinkyMenuBarController: NSObject, NSMenuDelegate {
    static let shared = BinkyMenuBarController()

    private var statusItem: NSStatusItem?

    func refresh() {
        let defaults = UserDefaults.standard
        let enabled: Bool = {
            if defaults.object(forKey: "ui.showMenuBarIcon") == nil { return true }
            return defaults.bool(forKey: "ui.showMenuBarIcon")
        }()

        guard enabled else {
            tearDown()
            return
        }

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.toolTip = "Binky"
            item.button?.image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Binky")
            item.button?.image?.isTemplate = true
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
        if let menu = statusItem?.menu {
            menuNeedsUpdate(menu)
        }
    }

    private func tearDown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let sort = NSMenuItem(
            title: String(localized: "Sort Now", comment: "Menu bar command."),
            action: #selector(sortNow),
            keyEquivalent: ""
        )
        sort.target = self
        menu.addItem(sort)

        let paused = UserDefaults.standard.bool(forKey: "folderWatch.paused")
        let pauseItem = NSMenuItem(
            title: paused
                ? String(localized: "Resume watching", comment: "Menu bar command.")
                : String(localized: "Pause watching", comment: "Menu bar command."),
            action: #selector(togglePauseWatching),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let show = NSMenuItem(
            title: String(localized: "Show Binky", comment: "Menu bar command."),
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        show.target = self
        menu.addItem(show)

        let settings = NSMenuItem(
            title: String(localized: "Settings…", comment: "Menu bar command."),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        let history = NSMenuItem(
            title: String(localized: "History…", comment: "Menu bar command."),
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        history.target = self
        menu.addItem(history)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "Quit Binky", comment: "Menu bar command."),
            action: #selector(terminateApp),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openHistory() {
        NotificationCenter.default.post(name: .binkyShowHistory, object: nil)
        GlobalHotkeyManager.activateMainWindow()
    }

    @objc private func terminateApp() {
        NSApp.terminate(nil)
    }

    @objc private func sortNow() {
        NotificationCenter.default.post(name: .binkyStartCompression, object: nil)
    }

    @objc private func togglePauseWatching() {
        let key = "folderWatch.paused"
        let next = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(next, forKey: key)
        NotificationCenter.default.post(name: .binkyFolderWatchPauseChanged, object: nil)
    }

    @objc private func showMainWindow() {
        GlobalHotkeyManager.activateMainWindow()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // In SwiftUI apps, calling `showSettingsWindow:` directly can log
        // "Please use SettingsLink for opening the Settings scene."
        // `showPreferencesWindow:` opens the same Settings scene without that warning.
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
