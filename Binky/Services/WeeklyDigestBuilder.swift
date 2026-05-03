import Foundation

/// Roll-up counts for social sharing or weekly notifications.
struct WeeklyDigestShareModel: Identifiable {
    let id = UUID()
    let weekAnchor: Date
    /// Sort sessions decoded from history in range.
    let sessionCount: Int
    /// File rows processed (`SortBatchOutcome.entries`).
    let filesProcessed: Int
    /// Files actually moved (`disposition == .moved`).
    let movesCount: Int
    /// Top categories by entry count after `moved`-only tally (fallback: all entries).
    let topCategories: [(FileSortCategory, Int)]

    static func build(from history: [SessionRecord], trailingDays: Int = 7, now: Date = Date()) -> WeeklyDigestShareModel? {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, trailingDays), to: now) else { return nil }

        var sessionCount = 0
        var filesProcessed = 0
        var movesCount = 0
        var categoryTallyMoved: [FileSortCategory: Int] = [:]
        var categoryTallyAll: [FileSortCategory: Int] = [:]

        for record in history where record.timestamp >= cutoff {
            guard let data = record.batchSummaryData,
                  let outcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: data)
            else { continue }

            sessionCount += 1
            filesProcessed += outcome.entries.count

            let movedEntries = outcome.entries.filter { $0.disposition == .moved }
            movesCount += movedEntries.count
            let primarySource = movedEntries.isEmpty ? outcome.entries : movedEntries

            for e in primarySource {
                categoryTallyMoved[e.category, default: 0] += 1
                categoryTallyAll[e.category, default: 0] += 1
            }
        }

        guard sessionCount > 0 || filesProcessed > 0 || movesCount > 0 else { return nil }

        let source = categoryTallyMoved.values.reduce(0, +) > 0 ? categoryTallyMoved : categoryTallyAll
        let top = source.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }

        return WeeklyDigestShareModel(
            weekAnchor: now,
            sessionCount: sessionCount,
            filesProcessed: filesProcessed,
            movesCount: movesCount,
            topCategories: top
        )
    }
}
