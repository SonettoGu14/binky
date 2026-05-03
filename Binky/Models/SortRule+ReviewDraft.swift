import Foundation

extension SortRule {
    /// Starter fields for a new rule when the user is triaging a file from Review.
    static func draftFromReviewFile(url: URL, order: Int) -> SortRule {
        var rule = SortRule.fresh(order: order)
        rule.name = String(localized: "From Review", comment: "Default name for rule created from Review triage.")
        let ext = url.pathExtension.lowercased().replacingOccurrences(of: ".", with: "")
        if !ext.isEmpty {
            rule.matchExtensions = [ext]
        }
        if let host = WhereFromsReader.primaryOriginHost(forFileAt: url), !host.isEmpty {
            rule.originDomains = [host]
        }
        rule.destinationRelativePath = FileSortCategory.misc.downloadsSubfolder
        return rule
    }
}
