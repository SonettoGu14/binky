import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Tier stub

enum BinkySubscriptionTier: String, Codable, Sendable {
    case free, plus

    static var current: BinkySubscriptionTier {
        UserDefaults.standard.bool(forKey: "binky.plusUnlocked") ? .plus : .free
    }
}

// MARK: - Orchestrator

/// Matches guards from sorting passes — processes visible filesystem snapshots consistently everywhere ``StarterDestinations`` prepares buckets once upstream ``StarterDestinations.ensure(downloadsRoot:)``.
@MainActor
final class DownloadsSortOrchestrator {
    private enum SortControlState {
        case running
        case paused
        case stopRequested
    }

    static let shared = DownloadsSortOrchestrator()

    nonisolated static func uniquify(destinationDirectory folder: URL, preferredFilename name: String) -> URL {
        SortCollision.uniquify(destinationDirectory: folder, preferredFilename: name)
    }

    /// `(destination,isOriginalSource)`
    private(set) var lastUndoPairs: [(URL, URL)] = []

    /// ID of the outcome from the last finished `sort` pass.
    private(set) var lastCompletedSortID: UUID?

    private(set) var isSorting: Bool = false
    private var sortControlState: SortControlState = .running
    private var sortRunGate: SortRunGate?

    var canPause: Bool {
        isSorting && sortControlState == .running
    }

    var canResume: Bool {
        isSorting && sortControlState == .paused
    }

    var canStop: Bool {
        isSorting && sortControlState != .stopRequested
    }

    func pauseCurrentSort() {
        guard canPause else { return }
        sortControlState = .paused
        sortRunGate?.setPaused()
        SortProgressTracker.shared.setRunState(.paused)
    }

    func resumeCurrentSort() {
        guard canResume else { return }
        sortControlState = .running
        sortRunGate?.setRunning()
        SortProgressTracker.shared.setRunState(.running)
    }

    func stopCurrentSort() {
        guard canStop else { return }
        sortControlState = .stopRequested
        sortRunGate?.setStopRequested()
        SortProgressTracker.shared.setRunState(.stopping)
    }

    private static func emptyOutcome() -> SortBatchOutcome {
        SortBatchOutcome(id: UUID(), started: Date(), elapsed: 0, entries: [])
    }

    func previewSort(files urls: [URL], prefs: BinkyPreferences, rootOverride: [URL: URL] = [:]) async -> [SortPreviewEntry] {
        prefs.reconcileFolderBookmarksIfNeeded()
        let snapshot = prefs.makeSortPreferencesSnapshot()
        let normalizedOverride: [URL: URL] = Dictionary(
            rootOverride.map { ($0.key.standardizedFileURL, $0.value.standardizedFileURL) },
            uniquingKeysWith: { first, _ in first }
        )
        return await SortPreviewPlanner.preview(files: urls, snapshot: snapshot, rootOverride: normalizedOverride)
    }

    /// Files directly under `root`, plus regular files one level inside immediate subfolders when `recursiveOneLevel` is true.
    nonisolated static func collectSweepFiles(in root: URL, recursiveOneLevel: Bool, fileManager fm: FileManager = .default) -> [URL] {
        guard let urls = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [URL] = []
        for url in urls {
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if vals?.isDirectory != true {
                files.append(url.standardizedFileURL)
                continue
            }
            guard recursiveOneLevel else { continue }
            guard let inner = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for u in inner {
                if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
                    files.append(u.standardizedFileURL)
                }
            }
        }
        return files
    }

    /// Top-level files in each active inbox folder (global watch root + unique preset watch roots).
    static func topLevelInboxFiles(prefs: BinkyPreferences) -> [URL] {
        prefs.reconcileFolderBookmarksIfNeeded()
        let fm = FileManager.default
        let recursive = prefs.watchRecursiveOneLevel
        var rootPaths: Set<String> = []
        rootPaths.insert(prefs.downloadsSortRootDirectory().path)

        let reg = WatchPipelineRegistry(prefs: prefs)
        for (_, path) in reg.presetPaths {
            let normalized = WatchFolderPathResolver.normalizedPath(path)
            guard !normalized.isEmpty else { continue }
            rootPaths.insert(normalized)
        }

        var collected: [URL] = []
        for path in rootPaths {
            let root = URL(fileURLWithPath: path)
            collected.append(contentsOf: collectSweepFiles(in: root, recursiveOneLevel: recursive, fileManager: fm))
        }
        return collected
    }

    func previewInbox(prefs: BinkyPreferences) async -> [SortPreviewEntry] {
        await previewSort(files: Self.topLevelInboxFiles(prefs: prefs), prefs: prefs)
    }

    private func urlsEligibleForSortPass(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var ordered: [URL] = []
        for raw in urls {
            let standardized = raw.standardizedFileURL
            guard standardized.isFileURL else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            ordered.append(standardized)
        }
        return ordered
    }

    func sort(
        files urls: [URL],
        prefs: BinkyPreferences,
        rootOverride: [URL: URL] = [:],
        progress: (@Sendable (SortProgressEvent) -> Void)? = nil
    ) async -> SortBatchOutcome {
        guard !isSorting else {
            NotificationCenter.default.post(name: .binkySortRejectedBecauseBusy, object: nil)
            return Self.emptyOutcome()
        }

        let flock = SortCrossProcessLock()
        guard flock.tryLock() else {
            NotificationCenter.default.post(name: .binkySortRejectedBecauseBusy, object: nil)
            return Self.emptyOutcome()
        }
        defer { flock.unlock() }

        isSorting = true
        sortControlState = .running
        SortProgressTracker.shared.setRunState(.running)

        let gate = SortRunGate()
        sortRunGate = gate

        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: String(localized: "Binky is sorting files.", comment: "Process activity reason while sorting watched-folder files.")
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            sortRunGate?.endSession()
            sortRunGate = nil
            isSorting = false
            sortControlState = .running
        }

        let startedAt = Date()
        prefs.reconcileFolderBookmarksIfNeeded()
        let snapshot = prefs.makeSortPreferencesSnapshot()

        let normalizedOverride: [URL: URL] = Dictionary(
            rootOverride.map { ($0.key.standardizedFileURL, $0.value.standardizedFileURL) },
            uniquingKeysWith: { first, _ in first }
        )

        let uniqueRoots = Set(urls.map { url -> URL in
            let std = url.standardizedFileURL
            return normalizedOverride[std] ?? prefs.sortContext(for: std).inboxRoot
        })
        for root in uniqueRoots {
            StarterDestinations.ensure(downloadsRoot: root)
        }

        let workURLs = urlsEligibleForSortPass(urls)
        progress?(.batchStarted(total: workURLs.count))
        defer {
            progress?(.batchEnded)
        }

        let hooks = SortWorkHooks(
            onEnergyHold: { kind in
                Task { @MainActor in SortProgressTracker.shared.setEnergyHold(kind) }
            },
            onEnergyHoldClear: {
                Task { @MainActor in SortProgressTracker.shared.clearEnergyHold() }
            },
            registerNewTagExpiry: { url, days in
                await MainActor.run {
                    NewTagExpiryService.shared.register(file: url, expiryDays: days)
                }
            }
        )

        let loopResult = await Task.detached(priority: .utility) { [workURLs, snapshot, normalizedOverride, gate, progress, hooks] in
            await SortWork.runSortWorkLoop(
                workURLs: workURLs,
                snapshot: snapshot,
                rootOverride: normalizedOverride,
                gate: gate,
                progress: progress,
                hooks: hooks
            )
        }.value

        let rows = loopResult.rows
        let tagWriteFailures = loopResult.tagWriteFailures

        let elapsed = Date().timeIntervalSince(startedAt)
        lastUndoPairs = rows
            .filter { $0.disposition == SortDisposition.moved }
            .compactMap { row in
                guard let dst = row.destinationPath else { return nil }
                return (URL(fileURLWithPath: dst), URL(fileURLWithPath: row.sourcePath))
            }

        var warnings: [String] = []
        if tagWriteFailures > 0 {
            let msg =
                tagWriteFailures == 1
                ? String(localized: "Finder tags didn’t stick for one file — the sort still landed.", comment: "Sort ancillary warning; single-file tag failure.")
                : String(
                    localized: "Finder tags didn’t stick for \(tagWriteFailures) files — the sort still landed.",
                    comment: "Sort ancillary warning; multiple tag failures. Argument is integer count."
                )
            warnings.append(msg)
        }

        let outcome = SortBatchOutcome(id: UUID(), started: startedAt, elapsed: elapsed, entries: rows, ancillaryWarnings: warnings)
        lastCompletedSortID = outcome.id
        prefs.appendSortOutcomeRecord(outcome)
        return outcome
    }

    func undoMovesReversingSort(_ pairs: [(destination: URL, source: URL)], clearPinnedUndoIfOutcomeID outcomeID: UUID?) async -> UndoMovesSummary {
        let fm = FileManager.default
        var failures = 0
        let attempted = pairs.count
        for pair in pairs.reversed() {
            guard fm.fileExists(atPath: pair.destination.path) else {
                failures += 1
                continue
            }
            do {
                try fm.moveItem(at: pair.destination, to: pair.source)
            } catch {
                failures += 1
            }
        }
        if let outcomeID, outcomeID == lastCompletedSortID, failures == 0, attempted > 0 {
            lastUndoPairs = []
        }
        return UndoMovesSummary(attempted: attempted, failures: failures)
    }

    func undoMostRecentPinnedBatchMoves() async -> UndoMovesSummary {
        let mapped = lastUndoPairs.map { (destination: $0.0, source: $0.1) }
        let summary = await undoMovesReversingSort(mapped, clearPinnedUndoIfOutcomeID: nil)
        lastUndoPairs = []
        return summary
    }
}

// MARK: — Trust-focused sheet

struct SortOutcomeSheet: View {

    let outcome: SortBatchOutcome
    var onRevealDestination: (SortBatchEntry) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onTransientStatus: ((String) -> Void)?

    init(
        outcome: SortBatchOutcome,
        onRevealDestination: @escaping (SortBatchEntry) -> Void = { _ in },
        onUndo: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        onTransientStatus: ((String) -> Void)? = nil
    ) {
        self.outcome = outcome
        self.onRevealDestination = onRevealDestination
        self.onUndo = onUndo
        self.onDismiss = onDismiss
        self.onTransientStatus = onTransientStatus
    }

    @EnvironmentObject private var prefs: BinkyPreferences
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sortProgress = SortProgressTracker.shared
    @State private var undoFootnote: String?

    private var titleString: String {
        if let preset = outcome.matchedRoutine(in: prefs.savedPresets) {
            return String.localizedStringWithFormat(
                String(localized: "Sorted “%@”", comment: "Sort summary title; arg is routine name."),
                preset.name
            )
        }
        return String(localized: "Move / review summary", comment: "Automated sort audit title; fallback when no routine matches.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(titleString)
                .font(.title2)

            HStack(spacing: 12) {
                statChip(title: String(localized: "Moved", comment: "Sort audit"), value: outcome.movedCount, systemImage: "folder")
                statChip(title: String(localized: "Kept", comment: "Sort audit"), value: outcome.keptCount, systemImage: "checkmark.circle")
                statChip(title: String(localized: "Skipped", comment: "Sort audit"), value: outcome.skippedCount, systemImage: "minus.circle")
                statChip(title: String(localized: "Review folder", comment: "Sort audit queue"), value: outcome.reviewQueuedCount, systemImage: "questionmark.circle")
            }

            ForEach(Array(outcome.ancillaryWarnings.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(outcome.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: entry.sourcePath).lastPathComponent)
                                .font(.headline)
                            Text(entry.userFacingWhyDescription())
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let dest = entry.destinationPath {
                                Button(String(localized: "Reveal in Finder", comment: "Sort audit")) {
                                    NSWorkspace.shared.selectFile(dest, inFileViewerRootedAtPath: URL(fileURLWithPath: dest).deletingLastPathComponent().path)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 320)

            dinkySection

            HStack {
                Button(role: .cancel, action: { onDismiss(); dismiss() }) {
                    Text(String(localized: "Close", comment: "Sort audit sheet dismiss."))
                }
                Button(String(localized: "Undo moves", comment: "Sort audit")) {
                    undoFootnote = nil
                    Task {
                        let summary = await DownloadsSortOrchestrator.shared.undoMovesReversingSort(
                            outcome.reversibleMoves,
                            clearPinnedUndoIfOutcomeID: outcome.id
                        )
                        if summary.failures > 0 {
                            undoFootnote = String(
                                localized: "\(summary.failures) of \(summary.attempted) moves couldn’t be undone — files may have moved or been renamed.",
                                comment: "Sort sheet undo partial failure footer. Arguments are counts."
                            )
                        } else if summary.attempted > 0 {
                            onUndo()
                            dismiss()
                            onDismiss()
                        }
                    }
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(outcome.reversibleMoves.isEmpty || sortProgress.isActive)
                Spacer()
            }

            if let undoFootnote {
                Text(undoFootnote)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(String(localized: "Undo moves puts files back where they were before this sort.", comment: "Sort sheet footer."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 520)
    }

    @ViewBuilder
    private var dinkySection: some View {
        let movedURLs: [URL] = outcome.entries.compactMap { e in
            guard e.disposition == SortDisposition.moved, let d = e.destinationPath else { return nil }
            return URL(fileURLWithPath: d)
        }
        let compressible = DinkyBridge.compressibleURLs(from: movedURLs)
        if compressible.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text(String(localized: "Dinky", comment: "Sort sheet: Dinky handoff section title."))
                    .font(.subheadline.weight(.semibold))
                if DinkyBridge.isInstalled {
                    Button(String.localizedStringWithFormat(String(localized: "Send %lld files to Dinky", comment: "Sort sheet: handoff button; file count."), Int64(compressible.count))) {
                        let msg = String(localized: "Dinky couldn’t open these — try installing or reopening it.", comment: "Organizer transient when Dinky app handoff fails.")
                        _ = DinkyBridge.openFiles(compressible) { ok in
                            guard !ok else { return }
                            Task { @MainActor in onTransientStatus?(msg) }
                        }
                    }
                    let folders = DinkyBridge.uniqueFolders(containing: compressible)
                    ForEach(folders, id: \.path) { folder in
                        Button {
                            let msg = String(localized: "Couldn’t open that folder in Dinky.", comment: "Organizer transient when Dinky folder handoff fails.")
                            _ = DinkyBridge.openFolder(folder) { ok in
                                guard !ok else { return }
                                Task { @MainActor in onTransientStatus?(msg) }
                            }
                        } label: {
                            Text(String.localizedStringWithFormat(String(localized: "Watch “%@” in Dinky →", comment: "Sort sheet: watch chain; folder name."), folder.lastPathComponent))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(binkyTintColor)
                    }
                } else {
                    Link(String(localized: "Compress these with Dinky ↗", comment: "Sort sheet: marketing link when Dinky not installed."), destination: DinkyBridge.marketingURL)
                        .font(.caption)
                }
            }
        }
    }

    private func statChip(title: String, value: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.monospacedDigit())
                .bold()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.35)))
    }
}

// MARK: - Watch folder coordinator (runs without main window)

/// Keeps Downloads watch-folder FSEvents and sorting alive even when the main window is closed.
@MainActor
final class WatchSortCoordinator {
    private let prefs: BinkyPreferences
    private let viewModel: OrganizerViewModel
    private let watcher = FolderWatcher()
    private var subscriptions = Set<AnyCancellable>()

    private var ingestTask: Task<Void, Never>?
    private var queuedIncoming: Set<URL> = []
    private var debounceBurstStart: Date?
    private var lastIncomingArrival: Date?
    private var rulesResortTask: Task<Void, Never>?

    init(prefs: BinkyPreferences, viewModel: OrganizerViewModel) {
        self.prefs = prefs
        self.viewModel = viewModel

        watcher.onNewFiles = { [weak self] incoming in
            self?.enqueueIncomingForDebouncedSort(incoming)
        }

        restartWatcherIfNeeded()

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                prefs.reconcileFolderBookmarksIfNeeded()
                restartWatcherIfNeeded()
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(140), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.restartWatcherIfNeeded() }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .binkyFolderWatchPauseChanged)
            .sink { [weak self] _ in self?.restartWatcherIfNeeded() }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .binkyRoutingRulesDidChange)
            .sink { [weak self] _ in self?.scheduleResortAfterRulesChanged() }
            .store(in: &subscriptions)
    }

    func restartWatcherIfNeeded() {
        prefs.reconcileFolderBookmarksIfNeeded()

        guard !prefs.folderWatchPaused else {
            watcher.stop()
            return
        }

        let registry = WatchPipelineRegistry(prefs: prefs)
        let paths = registry.watchedRootPaths
        guard !paths.isEmpty else {
            watcher.stop()
            return
        }
        watcher.start(paths: paths)
    }

    private func enqueueIncomingForDebouncedSort(_ incoming: [URL]) {
        let dedup = incoming.map(\.standardizedFileURL).filter(\.isFileURL)
        guard !dedup.isEmpty else { return }
        let now = Date()
        if debounceBurstStart == nil { debounceBurstStart = now }
        lastIncomingArrival = now
        queuedIncoming.formUnion(dedup)
        ingestTask?.cancel()
        ingestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while DownloadsSortOrchestrator.shared.isSorting {
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { return }
            }

            let debounceQuiet: TimeInterval = 0.8
            let burstCeiling: TimeInterval = 1.5

            while !Task.isCancelled {
                let nowTick = Date()
                guard let last = self.lastIncomingArrival, let burstStart = self.debounceBurstStart else { break }
                let quietDeadline = last.addingTimeInterval(debounceQuiet)
                let capDeadline = burstStart.addingTimeInterval(burstCeiling)
                let fireDate = min(quietDeadline, capDeadline)
                if nowTick >= fireDate { break }
                let waitSec = fireDate.timeIntervalSince(nowTick)
                let ns = UInt64(min(max(waitSec, 0.02), 1.0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
            if Task.isCancelled { return }

            let batch = Array(self.queuedIncoming)
            self.queuedIncoming.removeAll()
            self.debounceBurstStart = nil
            self.lastIncomingArrival = nil
            guard !batch.isEmpty else { return }
            while EnergyConditions.shared.shouldPauseFully {
                if Task.isCancelled {
                    self.queuedIncoming.formUnion(batch)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else {
                self.queuedIncoming.formUnion(batch)
                return
            }
            let outcome = await DownloadsSortOrchestrator.shared.sort(
                files: batch,
                prefs: prefs,
                progress: SortProgressTracker.orchestratorClosure()
            )
            guard outcome.hasWork else { return }
            viewModel.deliverCompletedSort(outcome, prefs: prefs)
        }
    }

    private func scheduleResortAfterRulesChanged() {
        guard prefs.sortAutoRunWhenRulesChange else { return }
        rulesResortTask?.cancel()
        rulesResortTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self.performResortAcrossWatchedInboxesAfterRulesChanged()
        }
    }

    private func performResortAcrossWatchedInboxesAfterRulesChanged() async {
        guard prefs.sortAutoRunWhenRulesChange else { return }
        guard prefs.folderWatchEnabled, !prefs.folderWatchPaused else { return }
        prefs.reconcileFolderBookmarksIfNeeded()

        while DownloadsSortOrchestrator.shared.isSorting {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard !Task.isCancelled else { return }

        let files = DownloadsSortOrchestrator.topLevelInboxFiles(prefs: prefs)
        guard !files.isEmpty else { return }

        let outcome = await DownloadsSortOrchestrator.shared.sort(
            files: files,
            prefs: prefs,
            progress: SortProgressTracker.orchestratorClosure()
        )
        guard outcome.hasWork else { return }
        viewModel.deliverCompletedSort(outcome, prefs: prefs)
    }
}
