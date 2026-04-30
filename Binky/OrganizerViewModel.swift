import AppKit
import Foundation
import SwiftUI
import UserNotifications

/// Main-window state for Downloads inbox sorting (replaces the compression queue).
@MainActor
final class OrganizerViewModel: ObservableObject {
    /// Latest automated / manual sort audit sheet.
    @Published var pendingSortOutcome: SortBatchOutcome?
    /// For **Last Sort Summary…** menu / shortcut.
    @Published var lastSortOutcome: SortBatchOutcome?

    func presentSortOutcome(_ outcome: SortBatchOutcome?) {
        pendingSortOutcome = outcome
    }

    func applySortOutcomeDismissalDefaults() {
        pendingSortOutcome = nil
    }

    func presentHistoricalSortOutcome(_ outcome: SortBatchOutcome) {
        pendingSortOutcome = outcome
    }

    func showLastSortSummary() {
        guard let base = lastSortOutcome else { return }
        pendingSortOutcome = base
    }

    /// Run after any successful sort with user-facing side effects.
    func deliverCompletedSort(_ outcome: SortBatchOutcome, prefs: BinkyPreferences) {
        lastSortOutcome = outcome
        if prefs.openFolderWhenDone {
            NSWorkspace.shared.open(prefs.downloadsSortRootDirectory())
        }
        if prefs.playSoundEffects {
            NSSound(named: "Pop")?.play()
        }
        if prefs.notifyWhenDone {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Binky", comment: "Notification title.")
            content.body = String.localizedStringWithFormat(
                String(localized: "Moved %1$lld · Kept %2$lld · Skipped %3$lld", comment: "Sort notification; three counts."),
                outcome.movedCount, outcome.keptCount, outcome.skippedCount
            )
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        }
        pendingSortOutcome = prefs.showBatchSummaryDialog ? outcome : nil
    }

    func runInteractiveDownloadsSweep(prefs: BinkyPreferences) async {
        let root = prefs.downloadsSortRootDirectory()
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var files: [URL] = []
        for url in urls {
            guard let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  vals.isDirectory == false else { continue }
            files.append(url)
        }
        guard !files.isEmpty else { return }
        let outcome = await DownloadsSortOrchestrator.shared.sort(files: files, prefs: prefs)
        guard outcome.hasWork else { return }
        deliverCompletedSort(outcome, prefs: prefs)
    }

    /// Sort explicit files (drop, Open panel, Finder Services). Skips items not under the active inbox root.
    func sortIncomingFiles(_ urls: [URL], prefs: BinkyPreferences) async {
        let root = prefs.downloadsSortRootDirectory().standardizedFileURL
        let rootPath = root.path
        let filtered = urls.map(\.standardizedFileURL).filter { url in
            guard url.isFileURL else { return false }
            let p = url.path
            return p == rootPath || p.hasPrefix(rootPath + "/")
        }
        guard !filtered.isEmpty else { return }
        let outcome = await DownloadsSortOrchestrator.shared.sort(files: filtered, prefs: prefs)
        guard outcome.hasWork else { return }
        deliverCompletedSort(outcome, prefs: prefs)
    }

    /// Dry-run rows for files at the top level of the inbox (Output tab “Preview” uses the same engine).
    func inboxPreviewEntries(prefs: BinkyPreferences) -> [SortPreviewEntry] {
        DownloadsSortOrchestrator.shared.previewInbox(prefs: prefs)
    }
}
