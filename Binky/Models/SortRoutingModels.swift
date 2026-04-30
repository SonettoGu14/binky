import Foundation

// MARK: - Rename

enum SortRenameStyle: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case none
    case datePrefix
    case template

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .none:
            return String(localized: "Keep original name", comment: "Sort rule rename style.")
        case .datePrefix:
            return String(localized: "Prefix with date (yyyy-MM-dd)", comment: "Sort rule rename style.")
        case .template:
            return String(localized: "Custom pattern", comment: "Sort rule rename style.")
        }
    }
}

// MARK: - Date predicate (Date Added / fallback)

enum SortDateAddedPredicateKind: String, Codable, Hashable, Sendable {
    case none
    case newerThanDays
    case olderThanDays
}

struct SortDateAddedPredicate: Codable, Equatable, Sendable {
    var kind: SortDateAddedPredicateKind
    /// Ignored when kind is `.none`.
    var days: Int

    static let disabled = SortDateAddedPredicate(kind: .none, days: 0)
}

// MARK: - Kind filter (UTType-aligned)

enum SortFileKindFilter: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case any
    case image
    case movie
    case audio
    case archive
    case pdf
    case document

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .any:
            return String(localized: "Any kind", comment: "Sort rule kind filter.")
        case .image:
            return String(localized: "Images", comment: "Sort rule kind filter.")
        case .movie:
            return String(localized: "Video", comment: "Sort rule kind filter.")
        case .audio:
            return String(localized: "Audio", comment: "Sort rule kind filter.")
        case .archive:
            return String(localized: "Archives", comment: "Sort rule kind filter.")
        case .pdf:
            return String(localized: "PDF", comment: "Sort rule kind filter.")
        case .document:
            return String(localized: "Documents", comment: "Sort rule kind filter.")
        }
    }
}

// MARK: - User-defined inbox rule

struct InboxSortRule: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var isEnabled: Bool
    var name: String
    /// Lowercased extensions without leading dot; empty = match any extension.
    var matchExtensions: [String]
    /// Case-insensitive substring on full filename; empty = ignore.
    var nameContains: String
    var fileKindFilter: SortFileKindFilter
    var minSizeBytes: Int64?
    var maxSizeBytes: Int64?
    /// Compared against Date Added to folder when available, else creation date.
    var dateAddedPredicate: SortDateAddedPredicate?
    /// Relative path under the inbox root (slashes for nested folders). Sanitized on use.
    var destinationRelativePath: String
    var renameStyle: SortRenameStyle
    /// Tokens: {date}, {stem}, {ext}, {n}
    var renameTemplate: String
    /// Finder tags merged when this rule matches (after global semantic tags and profile tags).
    var addedTags: [String]

    private enum CodingKeys: String, CodingKey {
        case id, isEnabled, name, matchExtensions, nameContains, fileKindFilter
        case minSizeBytes, maxSizeBytes, dateAddedPredicate, destinationRelativePath, renameStyle, renameTemplate
        case addedTags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        name = try c.decode(String.self, forKey: .name)
        matchExtensions = try c.decode([String].self, forKey: .matchExtensions)
        nameContains = try c.decode(String.self, forKey: .nameContains)
        fileKindFilter = try c.decode(SortFileKindFilter.self, forKey: .fileKindFilter)
        minSizeBytes = try c.decodeIfPresent(Int64.self, forKey: .minSizeBytes)
        maxSizeBytes = try c.decodeIfPresent(Int64.self, forKey: .maxSizeBytes)
        dateAddedPredicate = try c.decodeIfPresent(SortDateAddedPredicate.self, forKey: .dateAddedPredicate)
        destinationRelativePath = try c.decode(String.self, forKey: .destinationRelativePath)
        renameStyle = try c.decode(SortRenameStyle.self, forKey: .renameStyle)
        renameTemplate = try c.decode(String.self, forKey: .renameTemplate)
        addedTags = try c.decodeIfPresent([String].self, forKey: .addedTags) ?? []
    }

    static func fresh(order: Int) -> InboxSortRule {
        InboxSortRule(
            id: UUID(),
            isEnabled: true,
            name: String(localized: "Rule \(order)", comment: "Default name for new inbox sort rule; argument is order index."),
            matchExtensions: [],
            nameContains: "",
            fileKindFilter: .any,
            minSizeBytes: nil,
            maxSizeBytes: nil,
            dateAddedPredicate: nil,
            destinationRelativePath: "Misc",
            renameStyle: .none,
            renameTemplate: "{date} {stem}{ext}",
            addedTags: []
        )
    }

    init(
        id: UUID,
        isEnabled: Bool,
        name: String,
        matchExtensions: [String],
        nameContains: String,
        fileKindFilter: SortFileKindFilter,
        minSizeBytes: Int64?,
        maxSizeBytes: Int64?,
        dateAddedPredicate: SortDateAddedPredicate?,
        destinationRelativePath: String,
        renameStyle: SortRenameStyle,
        renameTemplate: String,
        addedTags: [String] = []
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.matchExtensions = matchExtensions
        self.nameContains = nameContains
        self.fileKindFilter = fileKindFilter
        self.minSizeBytes = minSizeBytes
        self.maxSizeBytes = maxSizeBytes
        self.dateAddedPredicate = dateAddedPredicate
        self.destinationRelativePath = destinationRelativePath
        self.renameStyle = renameStyle
        self.renameTemplate = renameTemplate
        self.addedTags = addedTags
    }
}
