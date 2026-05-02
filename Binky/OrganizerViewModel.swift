import AppKit
import Combine
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

    /// One-shot status line shown in the organizer (empty inbox, duplicate sort, filtering, etc.).
    @Published var transientBannerMessage: String?

    private var transientResetTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .binkySortRejectedBecauseBusy)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.flashTransientStatus(
                    String(localized: "Sh. Binky's already on it.", comment: "Organizer transient banner when a sort is requested while one runs.")
                )
            }
            .store(in: &cancellables)
    }

    func flashTransientStatus(_ message: String, durationSeconds: UInt64 = 3) {
        transientResetTask?.cancel()
        transientBannerMessage = message
        transientResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(durationSeconds))
            guard !Task.isCancelled else { return }
            transientBannerMessage = nil
        }
    }

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
        let revealRoot = prefs.activeSortSweepRootDirectory()
        if prefs.openFolderWhenDone {
            NSWorkspace.shared.open(revealRoot)
        }
        if prefs.playSoundEffects {
            NSSound(named: "Pop")?.play()
        }
        if prefs.notifyWhenDone {
            postSortSortOnlyNotification(outcome: outcome)
        }
        prefs.lastSortAlreadyHadCount = outcome.alreadyHadCount
        SortDailyDigestAccumulator.shared.record(outcome: outcome)
        pendingSortOutcome = prefs.showBatchSummaryDialog ? outcome : nil
    }

    private func postSortSortOnlyNotification(outcome: SortBatchOutcome) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Binky", comment: "Notification title.")
        content.body = String.localizedStringWithFormat(
            String(localized: "Moved %1$lld · Kept %2$lld · Skipped %3$lld", comment: "Sort notification; three counts."),
            Int64(outcome.movedCount),
            Int64(outcome.keptCount),
            Int64(outcome.skippedCount)
        )
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    func runInteractiveDownloadsSweep(prefs: BinkyPreferences) async {
        transientBannerMessage = nil
        guard !DownloadsSortOrchestrator.shared.isSorting else {
            flashTransientStatus(
                String(localized: "Sh. Binky's already on it.", comment: "Organizer transient banner when a sort is requested while one runs.")
            )
            return
        }
        let root = prefs.activeSortSweepRootDirectory()
        let files = DownloadsSortOrchestrator.collectSweepFiles(
            in: root,
            recursiveOneLevel: prefs.watchRecursiveOneLevel
        )
        guard !files.isEmpty else {
            flashTransientStatus(
                String(localized: "Inbox is quiet. Nothing to sort.", comment: "Organizer transient banner when Sweep finds no files.")
            )
            return
        }
        let outcome = await DownloadsSortOrchestrator.shared.sort(
            files: files,
            prefs: prefs,
            progress: SortProgressTracker.orchestratorClosure()
        )
        guard outcome.hasWork else { return }
        deliverCompletedSort(outcome, prefs: prefs)
    }

    /// Sort explicit files (drop, Open panel, Finder Services / right-click).
    ///
    /// - Files: must live under the active inbox root (kept from earlier behavior).
    /// - Folders: expand to their top-level files; the folder itself becomes the ad-hoc inbox
    ///   root for those files, even when it sits outside the watched inbox. Subfolders are not
    ///   descended — matches the Sweep model.
    func sortIncomingFiles(_ urls: [URL], prefs: BinkyPreferences) async {
        transientBannerMessage = nil
        let fm = FileManager.default
        let inboxRoot = prefs.activeSortSweepRootDirectory().standardizedFileURL
        let inboxPath = inboxRoot.path

        var files: [URL] = []
        var rootOverride: [URL: URL] = [:]
        var seen: Set<URL> = []

        for raw in urls {
            let std = raw.standardizedFileURL
            guard std.isFileURL else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: std.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                guard let entries = try? fm.contentsOfDirectory(
                    at: std,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for entry in entries {
                    let entryStd = entry.standardizedFileURL
                    var entryIsDir: ObjCBool = false
                    guard fm.fileExists(atPath: entryStd.path, isDirectory: &entryIsDir),
                          !entryIsDir.boolValue else { continue }
                    guard seen.insert(entryStd).inserted else { continue }
                    files.append(entryStd)
                    rootOverride[entryStd] = std
                }
            } else {
                let p = std.path
                guard p == inboxPath || p.hasPrefix(inboxPath + "/") else { continue }
                guard seen.insert(std).inserted else { continue }
                files.append(std)
            }
        }

        guard !files.isEmpty else {
            flashTransientStatus(
                String(localized: "Those aren’t in the inbox. Drop them in the watched folder first.", comment: "Organizer transient when dropped paths are outside the active inbox root.")
            )
            return
        }
        guard !DownloadsSortOrchestrator.shared.isSorting else {
            flashTransientStatus(
                String(localized: "Sh. Binky's already on it.", comment: "Organizer transient banner when a sort is requested while one runs.")
            )
            return
        }
        let outcome = await DownloadsSortOrchestrator.shared.sort(
            files: files,
            prefs: prefs,
            rootOverride: rootOverride,
            progress: SortProgressTracker.orchestratorClosure()
        )
        guard outcome.hasWork else { return }
        deliverCompletedSort(outcome, prefs: prefs)
    }

    /// Dry-run rows for active sweep root (sidebar Preview).
    func inboxPreviewEntries(prefs: BinkyPreferences) async -> [SortPreviewEntry] {
        let files = DownloadsSortOrchestrator.collectSweepFiles(
            in: prefs.activeSortSweepRootDirectory(),
            recursiveOneLevel: prefs.watchRecursiveOneLevel
        )
        return await DownloadsSortOrchestrator.shared.previewSort(
            files: files,
            prefs: prefs
        )
    }
}
