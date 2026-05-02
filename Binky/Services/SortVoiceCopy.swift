import Foundation

// MARK: - Session / history (aggregate)

extension SortBatchOutcome {
    /// Skipped-as-duplicate rows.
    var duplicateSkipEntryCount: Int {
        entries.filter { $0.disposition == .skippedDuplicate }.count
    }

    /// Files moved into the Duplicates bucket (same-bytes / near-match).
    var duplicateFolderMoveCount: Int {
        entries.filter { $0.disposition == .moved && $0.category == .duplicates }.count
    }

    /// “Already had” for chips and history: skips + duplicate-folder moves.
    var alreadyHadCount: Int {
        duplicateSkipEntryCount + duplicateFolderMoveCount
    }

    var receiptFiledCount: Int {
        entries.filter { $0.disposition == .moved && $0.category == .receipts }.count
    }

    /// One line for history rows: calm counts (see VOICE.md).
    var voiceSessionStatsLine: String {
        String.localizedStringWithFormat(
            String(
                localized: "%1$lld sorted · %2$lld already had · %3$lld receipts filed · %4$lld in review",
                comment: "Session stats for history/activity; four integer counts."
            ),
            Int64(movedCount),
            Int64(alreadyHadCount),
            Int64(receiptFiledCount),
            Int64(reviewQueuedCount)
        )
    }
}

// MARK: - Per-file “why” (summary sheet, preview)

extension SortBatchEntry {
    /// Short, user-facing explanation — prefer over raw `reason` in UI.
    func userFacingWhyDescription() -> String {
        switch disposition {
        case .skippedDuplicate:
            return String(localized: "Already got one.", comment: "Voice: duplicate skip.")
        case .skippedTransient:
            return String(localized: "Incomplete download — skipped for now.", comment: "Voice: transient skip.")
        case .skippedStableCheckTimeout:
            return String(localized: "Still changing — skipped this time.", comment: "Voice: stable timeout.")
        case .skippedExcluded:
            return String(localized: "On your ignore list.", comment: "Voice: excluded.")
        case .skippedError:
            return String(localized: "Something went wrong.", comment: "Voice: sort error.")
        case .kept:
            return String(localized: "Already in the right place.", comment: "Voice: kept in place.")
        case .moved:
            break
        }

        if category == .receipts {
            if let rule = matchedRuleName, !rule.isEmpty {
                return String.localizedStringWithFormat(
                    String(localized: "Sent by “%@”.", comment: "Voice: named rule; receipt path."),
                    rule
                )
            }
            return String(localized: "Looks like a receipt.", comment: "Voice: auto receipt routing.")
        }

        if category == .duplicates {
            return String(localized: "Already got one — filed here.", comment: "Voice: duplicate moved to folder.")
        }

        if category == .review {
            if let host = originHost, !host.isEmpty {
                return String.localizedStringWithFormat(
                    String(localized: "Needs a look · from %@.", comment: "Voice: review + host."),
                    host
                )
            }
            return String(localized: "Needs a look.", comment: "Voice: review folder.")
        }

        if let rule = matchedRuleName, !rule.isEmpty {
            if let host = originHost, !host.isEmpty {
                return String.localizedStringWithFormat(
                    String(localized: "Sent by “%1$@” · from %2$@.", comment: "Voice: rule + origin."),
                    rule,
                    host
                )
            }
            return String.localizedStringWithFormat(
                String(localized: "Sent by “%@”.", comment: "Voice: rule only."),
                rule
            )
        }

        if let host = originHost, !host.isEmpty {
            return String.localizedStringWithFormat(
                String(localized: "By file type · from %@.", comment: "Voice: taxonomy + host."),
                host
            )
        }

        return String(localized: "By file type.", comment: "Voice: automatic bucket.")
    }
}
