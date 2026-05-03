import Foundation
import UserNotifications

// MARK: - Rolling stats

@MainActor
final class SortDailyDigestAccumulator {
    static let shared = SortDailyDigestAccumulator()

    private var sortedMoves = 0
    private var reviewCount = 0
    private var duplicateSkips = 0
    private var receiptMoves = 0
    private var agingMoves = 0

    private init() {}

    func record(outcome: SortBatchOutcome) {
        sortedMoves += outcome.movedCount
        reviewCount += outcome.reviewQueuedCount
        for e in outcome.entries {
            if e.disposition == .skippedDuplicate {
                duplicateSkips += 1
            }
            if e.category == .receipts, e.disposition == .moved {
                receiptMoves += 1
            }
        }
    }

    func recordAgingArchived(count: Int) {
        agingMoves += count
    }

    func consumeDigestBodyAndReset() -> String {
        defer {
            sortedMoves = 0
            reviewCount = 0
            duplicateSkips = 0
            receiptMoves = 0
            agingMoves = 0
        }
        if sortedMoves == 0, reviewCount == 0, duplicateSkips == 0, receiptMoves == 0, agingMoves == 0 {
            return String(localized: "Quiet folders. Nothing to report.", comment: "Daily digest empty.")
        }
        return String.localizedStringWithFormat(
            String(
                localized: "Today: %1$lld sorted · %2$lld review · %3$lld dupes skipped · %4$lld receipts · %5$lld archived. Quietly handled.",
                comment: "Daily digest; five counts."
            ),
            Int64(sortedMoves),
            Int64(reviewCount),
            Int64(duplicateSkips),
            Int64(receiptMoves),
            Int64(agingMoves)
        )
    }
}

// MARK: - Timers (daily + weekly)

private final class SortDigestPrefsCapsule: @unchecked Sendable {
    weak var prefs: BinkyPreferences?

    func readHistory() -> [SessionRecord]? {
        guard let prefs else { return nil }
        return prefs.sessionHistory
    }
}

private let sortDigestCapsule = SortDigestPrefsCapsule()

/// In-app timers so notifications stay local (no daemon).
@MainActor
enum SortDigestScheduler {
    private static var digestTimer: Timer?
    private static var weeklyTimer: Timer?

    static func reschedule(prefs: BinkyPreferences) {
        sortDigestCapsule.prefs = prefs

        digestTimer?.invalidate()
        digestTimer = nil
        weeklyTimer?.invalidate()
        weeklyTimer = nil

        scheduleDailyIfNeeded(prefs: prefs)
        scheduleWeeklyIfNeeded(prefs: prefs)
    }

    private static func scheduleDailyIfNeeded(prefs: BinkyPreferences) {
        guard prefs.dailyDigestEnabled else { return }

        let hour = max(0, min(23, prefs.dailyDigestHour))
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = 0
        let cal = Calendar.current
        guard let next = cal.nextDate(after: Date(), matching: dc, matchingPolicy: .nextTimePreservingSmallerComponents) else { return }

        digestTimer = Timer(fire: next, interval: 86_400, repeats: true) { _ in
            Task { @MainActor in
                deliverDailyDigestNotification()
            }
        }
        if let digestTimer {
            RunLoop.main.add(digestTimer, forMode: .common)
        }
    }

    private static func scheduleWeeklyIfNeeded(prefs: BinkyPreferences) {
        guard prefs.weeklyDigestEnabled else { return }
        let weekday = clampWeekday(prefs.weeklyDigestWeekday)
        var dc = DateComponents()
        dc.weekday = weekday
        dc.hour = 9
        dc.minute = 0
        let cal = Calendar.current
        guard let next = cal.nextDate(after: Date(), matching: dc, matchingPolicy: .nextTimePreservingSmallerComponents) else { return }

        weeklyTimer = Timer(fire: next, interval: 604_800, repeats: true) { _ in
            Task { @MainActor in
                deliverWeeklyDigestNotification()
            }
        }
        if let weeklyTimer {
            RunLoop.main.add(weeklyTimer, forMode: .common)
        }
    }

    private static func clampWeekday(_ raw: Int) -> Int {
        min(max(raw, 1), 7)
    }

    static func deliverDailyDigestNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Binky", comment: "Notification title.")
        content.body = SortDailyDigestAccumulator.shared.consumeDigestBodyAndReset()
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    static func deliverWeeklyDigestNotification() {
        guard let history = sortDigestCapsule.readHistory(),
              let model = WeeklyDigestShareModel.build(from: history)
        else { return }
        guard model.filesProcessed > 0 || model.movesCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Binky", comment: "Notification title.")
        content.body = String.localizedStringWithFormat(
            String(
                localized: "%1$lld files sorted · %2$lld moves · %3$lld runs (last week). Tap Binky for the share card.",
                comment: "Weekly digest notification summary."
            ),
            Int64(model.filesProcessed),
            Int64(model.movesCount),
            Int64(model.sessionCount)
        )
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }
}
