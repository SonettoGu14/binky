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
            return String(localized: "Quiet inbox. Nothing to report.", comment: "Daily digest empty.")
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

// MARK: - Daily fire (in-app timer so body reflects live totals)

@MainActor
enum SortDigestScheduler {
    private static var digestTimer: Timer?

    static func reschedule(prefs: BinkyPreferences) {
        digestTimer?.invalidate()
        digestTimer = nil
        guard prefs.dailyDigestEnabled else { return }

        let hour = max(0, min(23, prefs.dailyDigestHour))
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = 0
        let cal = Calendar.current
        guard let next = cal.nextDate(after: Date(), matching: dc, matchingPolicy: .nextTimePreservingSmallerComponents) else { return }

        digestTimer = Timer(fire: next, interval: 86_400, repeats: true) { _ in
            Task { @MainActor in
                deliverDigestNotification()
            }
        }
        if let digestTimer {
            RunLoop.main.add(digestTimer, forMode: .common)
        }
    }

    static func deliverDigestNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Binky", comment: "Notification title.")
        content.body = SortDailyDigestAccumulator.shared.consumeDigestBodyAndReset()
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }
}
