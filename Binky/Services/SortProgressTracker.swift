import Foundation
import BinkyCoreShared
import BinkyCoreSort

// MARK: - Orchestrator callbacks

enum SortRunState: String, Sendable {
    case running
    case paused
    case stopping
}

/// One pulse of animation tied to a real `fileStarted` event.
struct SortAnimationPulse: Equatable, Sendable {
    let id: UUID
    let bucket: SortAnimationBucket
}

struct ActiveSortItem: Identifiable, Equatable {
    let id: UUID
    let path: String
    let displayName: String
}

/// Published sort progress + `NotificationCenter` posts for menu bar integration.
@MainActor
final class SortProgressTracker: ObservableObject {
    static let shared = SortProgressTracker()

    /// Posted when sorting progress changes. See `notification*` keys below.
    static let notificationIsActiveKey = "sortProgress.isActive"
    static let notificationTotalKey = "sortProgress.total"
    static let notificationCompletedKey = "sortProgress.completed"
    static let notificationFractionKey = "sortProgress.fraction"
    static let notificationSubtitleKey = "sortProgress.subtitle"
    static let notificationRunStateKey = "sortProgress.runState"

    /// Matches energy throttle / inter-file sleep threshold in `EnergyConditions`.
    static var bigSortEnergyCoalesceThreshold: Int { SortEnergy.bigBatchFileCount }

    @Published private(set) var isActive = false
    @Published private(set) var total: Int = 0
    @Published private(set) var completed: Int = 0
    @Published private(set) var currentItems: [ActiveSortItem] = []
    @Published private(set) var runState: SortRunState = .running
    /// Full pause for thermal `.critical` or Low Power Mode while sorting.
    @Published private(set) var energyHoldKind: SortEnergyHoldKind = .none
    /// Drives real-data bucket animation in `OrganizerEmptyStateView`; updated on each `fileStarted`.
    @Published private(set) var latestAnimationPulse: SortAnimationPulse?

    /// Coalesce `binkySortProgressChanged` for large batches (MainActor).
    private var coalesceProgressNotifications = false
    private var coalescePostWorkItem: DispatchWorkItem?

    /// Wall-clock moment the current batch became active — used to keep the progress UI visible
    /// long enough for tiny sorts to register visually.
    private var beganAt: Date?
    private var pendingMinimumVisibleEndWorkItem: DispatchWorkItem?

    /// Minimum time the progress chrome stays "active" after `.batchStarted` so Sort Now never
    /// feels like it skipped straight from click → done.
    private static let minimumVisibleDuration: TimeInterval = 0.9

    var fraction: Double {
        guard isActive, total > 0 else { return 0 }
        let c = Double(completed)
        let t = Double(total)
        return min(max(c / t, 0), 1)
    }

    /// Current file shown in banners (during `fileStarted … fileFinished`).
    private var processingDisplayName: String? {
        currentItems.last?.displayName
    }

    /// Caption under / beside the bar (shown in organizer).
    /// Uses interpolated `String(localized:)` — avoids printf/catalog format drift traps.
    var bannerCaption: String {
        if isActive {
            switch energyHoldKind {
            case .thermal:
                return String(localized: "Paused — letting things cool off.", comment: "Sort caption when thermal state is critical.")
            case .lowPower:
                return String(localized: "Paused — Low Power Mode.", comment: "Sort caption when macOS Low Power Mode is on.")
            case .none:
                break
            }
        }
        if isActive, runState == .stopping {
            return String(localized: "Stopping after this file…", comment: "Sort caption while stop is requested and current item is finishing.")
        }
        if isActive, runState == .paused {
            let base = subtitleForCountsOnly()
            if base.isEmpty {
                return String(localized: "Paused", comment: "Sort caption while paused.")
            }
            return String(localized: "Paused — \(base)", comment: "Sort caption while paused with batch progress.")
        }
        return subtitleForBannerOrNotification()
    }

    /// Menu bar tooltip while sorting.
    func menuBarTooltip() -> String {
        guard isActive else { return String(localized: "Binky", comment: "Menu bar status item tooltip (idle).") }
        switch energyHoldKind {
        case .thermal:
            return String(localized: "Binky — Paused (cooling down)", comment: "Menu bar tooltip when sort paused for thermal.")
        case .lowPower:
            return String(localized: "Binky — Paused (Low Power Mode)", comment: "Menu bar tooltip when sort paused for Low Power Mode.")
        case .none:
            break
        }
        if runState == .paused {
            let base = subtitleForCountsOnly()
            if base.isEmpty {
                return String(localized: "Binky — Paused", comment: "Menu bar tooltip: sorting paused.")
            }
            return String(localized: "Binky — Paused (\(base))", comment: "Menu bar tooltip: paused with counts.")
        }
        if runState == .stopping {
            return String(localized: "Binky — Stopping…", comment: "Menu bar tooltip: stop requested for current sort.")
        }
        guard total > 0 else {
            return String(localized: "Binky — Sorting…", comment: "Menu bar tooltip: sorting generic.")
        }
        let ordinal = max(min(completed + 1, total), 1)
        if let name = processingDisplayName {
            let localized = String(
                localized: "Binky — Sorting \(ordinal) of \(total) (\(name))",
                comment: "Menu bar tooltip: ordinal, total, filename."
            )
            return Self.resilientCaption(primary: localized) {
                "Binky — \(ordinal) / \(total) · \(name)"
            }
        }
        let localized = String(
            localized: "Binky — Sorting \(ordinal) of \(total)",
            comment: "Menu bar tooltip with counts."
        )
        return Self.resilientCaption(primary: localized) {
            "Binky — \(ordinal) / \(total)"
        }
    }

    /// Subtitle bundled in notifications and read by observers that don't use `bannerCaption` directly.
    private func subtitleForBannerOrNotification() -> String {
        guard isActive, total > 0 else { return "" }
        let ordinal = max(min(completed + 1, total), 1)
        if let name = processingDisplayName {
            let localized = String(
                localized: "\(ordinal) of \(total) — \(name)",
                comment: "Organizer sort banner caption: ordinal, total, filename."
            )
            return Self.resilientCaption(primary: localized) {
                "\(ordinal) of \(total) — \(name)"
            }
        }
        let localized = String(
            localized: "\(ordinal) of \(total)",
            comment: "Organizer sort banner caption: counts only."
        )
        return Self.resilientCaption(primary: localized) {
            "\(ordinal) of \(total)"
        }
    }

    private func subtitleForCountsOnly() -> String {
        guard isActive, total > 0 else { return "" }
        let ordinal = max(min(completed + 1, total), 1)
        let localized = String(
            localized: "\(ordinal) of \(total)",
            comment: "Sort progress counts only subtitle."
        )
        return Self.resilientCaption(primary: localized) {
            "\(ordinal) of \(total)"
        }
    }

    /// If localization yields an unusable empty string (shouldn't happen), use a readable fallback — never traps.
    private static func resilientCaption(primary: String, fallback: () -> String) -> String {
        if primary.isEmpty { return fallback() }
        return primary
    }

    private init() {}

    func begin(batchTotal: Int) {
        pendingMinimumVisibleEndWorkItem?.cancel()
        pendingMinimumVisibleEndWorkItem = nil

        if batchTotal <= 0 {
            beganAt = nil
            resetToIdle(postNotification: true)
            return
        }
        // Always clear prior batch remnants before activating (covers interrupt / late events).
        currentItems = []
        completed = 0
        total = batchTotal
        isActive = true
        runState = .running
        energyHoldKind = .none
        coalesceProgressNotifications = batchTotal >= Self.bigSortEnergyCoalesceThreshold
        coalescePostWorkItem?.cancel()
        coalescePostWorkItem = nil
        latestAnimationPulse = nil
        beganAt = Date()
        postSnapshotFlush()
    }

    func startFile(path: String, displayName: String, animationBucket: SortAnimationBucket) {
        guard isActive else { return }
        currentItems.removeAll(where: { $0.path == path })
        currentItems.append(ActiveSortItem(id: UUID(), path: path, displayName: displayName))
        latestAnimationPulse = SortAnimationPulse(id: UUID(), bucket: animationBucket)
        postSnapshotCoalesced()
    }

    func finishFile(path: String) {
        guard isActive else { return }
        coalescePostWorkItem?.cancel()
        coalescePostWorkItem = nil
        // Keep the last processed filename visible until the next file starts so
        // the sheet doesn't bounce to a generic "Next file starting…" state.
        if total > 0 {
            completed = min(completed + 1, total)
        }
        if coalesceProgressNotifications, completed < total {
            postSnapshotCoalesced()
        } else {
            postSnapshotFlush()
        }
    }

    func end() {
        guard isActive else { return }

        pendingMinimumVisibleEndWorkItem?.cancel()
        pendingMinimumVisibleEndWorkItem = nil

        let start = beganAt ?? .distantPast
        let elapsed = Date().timeIntervalSince(start)
        let remaining = Self.minimumVisibleDuration - elapsed

        if remaining > 0 {
            let work = DispatchWorkItem { [weak self] in
                self?.performEndCleanup()
            }
            pendingMinimumVisibleEndWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
        } else {
            performEndCleanup()
        }
    }

    private func performEndCleanup() {
        pendingMinimumVisibleEndWorkItem?.cancel()
        pendingMinimumVisibleEndWorkItem = nil
        beganAt = nil
        isActive = false
        currentItems.removeAll()
        runState = .running
        energyHoldKind = .none
        coalesceProgressNotifications = false
        coalescePostWorkItem?.cancel()
        coalescePostWorkItem = nil
        latestAnimationPulse = nil
        if total > 0 {
            completed = min(completed, total)
        }
        postSnapshotFlush()
        zeroCountsWhileIdle()
    }

    func setRunState(_ state: SortRunState) {
        guard isActive else { return }
        guard runState != state else { return }
        runState = state
        postSnapshotFlush()
    }

    func setEnergyHold(_ kind: SortEnergyHoldKind) {
        guard isActive else { return }
        energyHoldKind = kind
        postSnapshotFlush()
    }

    func clearEnergyHold() {
        energyHoldKind = .none
        postSnapshotFlush()
    }

    /// Keeps fraction at 0 between batches (`isActive` is already false).
    private func zeroCountsWhileIdle() {
        guard !isActive else { return }
        total = 0
        completed = 0
    }

    private func resetToIdle(postNotification shouldPost: Bool) {
        pendingMinimumVisibleEndWorkItem?.cancel()
        pendingMinimumVisibleEndWorkItem = nil
        beganAt = nil
        isActive = false
        total = 0
        completed = 0
        currentItems = []
        runState = .running
        energyHoldKind = .none
        coalesceProgressNotifications = false
        coalescePostWorkItem?.cancel()
        coalescePostWorkItem = nil
        latestAnimationPulse = nil
        if shouldPost {
            postSnapshotFlush()
        }
    }

    func apply(event: SortProgressEvent) {
        switch event {
        case .batchStarted(let n):
            begin(batchTotal: n)
        case .fileStarted(let path, let name, let bucket):
            guard isActive else { return }
            startFile(path: path, displayName: name, animationBucket: bucket)
        case .fileFinished(let path):
            guard isActive else { return }
            finishFile(path: path)
        case .batchEnded:
            end()
        }
    }

    private func postSnapshot() {
        NotificationCenter.default.post(
            name: .binkySortProgressChanged,
            object: nil,
            userInfo: [
                SortProgressTracker.notificationIsActiveKey: isActive,
                SortProgressTracker.notificationTotalKey: total,
                SortProgressTracker.notificationCompletedKey: completed,
                SortProgressTracker.notificationFractionKey: fraction,
                SortProgressTracker.notificationSubtitleKey: bannerCaption,
                SortProgressTracker.notificationRunStateKey: runState.rawValue,
            ]
        )
    }

    private func postSnapshotCoalesced() {
        guard coalesceProgressNotifications else {
            postSnapshot()
            return
        }
        coalescePostWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.postSnapshot()
        }
        coalescePostWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func postSnapshotFlush() {
        coalescePostWorkItem?.cancel()
        coalescePostWorkItem = nil
        postSnapshot()
    }

    /// Passed to `DownloadsSortOrchestrator.sort(... progress:)`.
    nonisolated static func orchestratorClosure() -> @Sendable (SortProgressEvent) -> Void {
        { event in
            Task { @MainActor in
                SortProgressTracker.shared.apply(event: event)
            }
        }
    }
}
