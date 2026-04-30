import SwiftUI
import UniformTypeIdentifiers
import AppKit
import UserNotifications

/// Hosts the organizer UI and bridges menu / external events.
struct ContentView: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @ObservedObject var vm: OrganizerViewModel

    init(vm: OrganizerViewModel) {
        self.vm = vm
    }

    var body: some View {
        OrganizerMainView(vm: vm)
            .environmentObject(prefs)
            .environmentObject(updater)
            .onReceive(NotificationCenter.default.publisher(for: .binkyOpenPanel)) { _ in
                openSortableFilesPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyOpenFiles)) { note in
                guard let urls = note.object as? [URL] else { return }
                Task {
                    await vm.sortIncomingFiles(urls, prefs: prefs)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyStartCompression)) { _ in
                Task {
                    await vm.runInteractiveDownloadsSweep(prefs: prefs)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyShowLastBatchSummary)) { _ in
                vm.showLastSortSummary()
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyCheckUpdates)) { _ in
                Task {
                    let result = await updater.check(manual: true)
                    presentManualUpdateResult(result, updater: updater)
                }
            }
    }

    private func openSortableFilesPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = prefs.downloadsSortRootDirectory()
        panel.prompt = String(localized: "Sort", comment: "Open panel button.")
        if panel.runModal() == .OK {
            Task {
                await vm.sortIncomingFiles(panel.urls, prefs: prefs)
            }
        }
    }
}

// MARK: - Manual update check alerts

@MainActor
private func presentManualUpdateResult(_ result: UpdateChecker.CheckResult,
                                       updater: UpdateChecker) {
    let alert = NSAlert()
    alert.alertStyle = .informational

    switch result {
    case .updateAvailable(let version):
        alert.messageText = String(localized: "A newer Binky is available.", comment: "Manual update alert title.")
        alert.informativeText = String(localized: "Version \(version) is out. You’re on \(currentAppVersion()). Want it?", comment: "Manual update alert; arguments are new and current version.")
        alert.addButton(withTitle: String(localized: "Install Update", comment: "Manual update alert."))
        alert.addButton(withTitle: String(localized: "What’s new", comment: "Manual update alert."))
        alert.addButton(withTitle: String(localized: "Maybe later", comment: "Manual update alert."))

        guard case .idle = updater.installState else { return }
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task { await updater.downloadAndInstall() }
        } else if response == .alertSecondButtonReturn, let url = updater.releaseURL {
            NSWorkspace.shared.open(url)
        }

    case .upToDate:
        alert.messageText = String(localized: "All caught up.", comment: "Manual update: no update available.")
        alert.informativeText = String(localized: "You’re on Binky \(currentAppVersion()) — the latest.", comment: "Manual update: up to date; argument is version.")
        alert.addButton(withTitle: String(localized: "Nice", comment: "Dismiss up-to-date alert."))
        alert.runModal()

    case .failed:
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn’t phone home.", comment: "Manual update: network error title.")
        alert.informativeText = String(localized: "Binky couldn’t reach GitHub. Probably the internet. Try again in a sec?", comment: "Manual update: network error detail.")
        alert.addButton(withTitle: String(localized: "OK", comment: "Alert dismiss."))
        alert.runModal()
    }
}

private func currentAppVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
}
