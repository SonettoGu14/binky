import Foundation

/// Machine-facing disposition for Preview / CLI (orthogonal to persisted ``SortDisposition`` on completed moves).
public enum SortPreviewPlanDisposition: String, Equatable, Sendable, Codable {
    case skippedTransient
    case skippedExcluded
    case skippedProtectedTag
    case skippedDuplicate
    case wouldTrash
    case wouldZip
    case wouldMove
    case keptInPlace
}

/// One row for **Preview sort** — no files are moved.
public struct SortPreviewEntry: Identifiable, Equatable, Sendable {
    public let id: UUID

    /// Standardized POSIX path for the source file (`file://` URLs map to `.path`).
    public let sourcePath: String

    public let proposedDestinationPath: String
    public let summary: String
    public let whyLine: String

    /// Category used for bucket / animation / routing summaries.
    public let category: FileSortCategory

    public let matchedRuleName: String?

    /// Tags the live sort pipeline would compose for this routing decision (skipped rows use `[]`).
    public let addedTags: [String]

    public let planDisposition: SortPreviewPlanDisposition

    public var sourceLastPathComponent: String {
        URL(fileURLWithPath: sourcePath).lastPathComponent
    }

    public init(
        id: UUID,
        sourcePath: String,
        proposedDestinationPath: String,
        summary: String,
        whyLine: String,
        category: FileSortCategory,
        matchedRuleName: String?,
        addedTags: [String],
        planDisposition: SortPreviewPlanDisposition
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.proposedDestinationPath = proposedDestinationPath
        self.summary = summary
        self.whyLine = whyLine
        self.category = category
        self.matchedRuleName = matchedRuleName
        self.addedTags = addedTags
        self.planDisposition = planDisposition
    }
}
