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

// MARK: - Inbox aging

enum FileAgingAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case archive
    case trash

    var id: String { rawValue }
}

struct CategoryAgingRule: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var categoryRaw: String
    var untouchedDays: Int
    var action: FileAgingAction
    var archiveFolderRelative: String

    static func fresh() -> CategoryAgingRule {
        CategoryAgingRule(
            id: UUID(),
            categoryRaw: "misc",
            untouchedDays: 30,
            action: .archive,
            archiveFolderRelative: "Archive"
        )
    }
}

// MARK: - Rule Finder tag policy

/// How a matched rule interacts with category-derived Finder tags (`FileSortCategory` defaults).
enum SortRuleFinderTagPolicy: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    /// Keep category defaults (global / profile / built-in), then apply ``InboxSortRule/addedTags``.
    case additive
    /// Replace the category-default layer with ``InboxSortRule/categoryDefaultReplacementTags``; profile custom tags and `addedTags` still apply after.
    case replaceCategoryDefault

    var id: String { rawValue }
}

// MARK: - Content match (OCR / receipt rules)

enum SortContentMatchKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case none
    case ocrText
    case receipt

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .none:
            return String(localized: "Any content", comment: "Sort rule: no content predicate.")
        case .ocrText:
            return String(localized: "Has readable text (OCR)", comment: "Sort rule content kind.")
        case .receipt:
            return String(localized: "Looks like receipt / invoice", comment: "Sort rule content kind.")
        }
    }
}

struct SortContentMatch: Codable, Equatable, Hashable, Sendable {
    var kind: SortContentMatchKind

    static let disabled = SortContentMatch(kind: .none)
}

// MARK: - Rule match action

/// What happens when an inbox rule matches (before automatic taxonomy sort).
enum SortRuleMatchAction: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case moveToDestination
    case moveToTrash
    case renameInPlace
    case zipToDestination

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .moveToDestination:
            return String(localized: "Move to folder", comment: "Rule action: move to destination path.")
        case .moveToTrash:
            return String(localized: "Move to Trash", comment: "Rule action.")
        case .renameInPlace:
            return String(localized: "Rename here only", comment: "Rule action: stay in inbox, rename.")
        case .zipToDestination:
            return String(localized: "Zip into folder", comment: "Rule action: zip file into destination.")
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
    /// Download origin: host glob per line, e.g. `*.stripe.com`, `figma.com`. Empty = any origin.
    var originDomains: [String]
    /// Content-based predicate (OCR / receipt). Evaluated after basic signals when not `.none`.
    var contentMatch: SortContentMatch
    /// Relative path under the inbox root (slashes for nested folders). Sanitized on use.
    var destinationRelativePath: String
    var renameStyle: SortRenameStyle
    /// Tokens: {date}, {stem}, {ext}, {n}, {origin}, {ocr}, {vendor}, {amount}
    var renameTemplate: String
    /// Effect when this rule matches (default: move into ``destinationRelativePath``).
    var matchAction: SortRuleMatchAction
    /// Finder tags merged when this rule matches (after category defaults and profile custom tags).
    var addedTags: [String]
    /// When ``finderTagPolicy`` is ``SortRuleFinderTagPolicy/replaceCategoryDefault``, replaces the category-default tag layer (comma list → array in UI).
    var finderTagPolicy: SortRuleFinderTagPolicy
    var categoryDefaultReplacementTags: [String]

    private enum CodingKeys: String, CodingKey {
        case id, isEnabled, name, matchExtensions, nameContains, fileKindFilter
        case minSizeBytes, maxSizeBytes, dateAddedPredicate, destinationRelativePath, renameStyle, renameTemplate
        case matchAction
        case addedTags
        case finderTagPolicy
        case categoryDefaultReplacementTags
        case originDomains, contentMatch
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
        matchAction = try c.decodeIfPresent(SortRuleMatchAction.self, forKey: .matchAction) ?? .moveToDestination
        addedTags = try c.decodeIfPresent([String].self, forKey: .addedTags) ?? []
        finderTagPolicy = try c.decodeIfPresent(SortRuleFinderTagPolicy.self, forKey: .finderTagPolicy) ?? .additive
        categoryDefaultReplacementTags = try c.decodeIfPresent([String].self, forKey: .categoryDefaultReplacementTags) ?? []
        originDomains = try c.decodeIfPresent([String].self, forKey: .originDomains) ?? []
        contentMatch = try c.decodeIfPresent(SortContentMatch.self, forKey: .contentMatch) ?? .disabled
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(name, forKey: .name)
        try c.encode(matchExtensions, forKey: .matchExtensions)
        try c.encode(nameContains, forKey: .nameContains)
        try c.encode(fileKindFilter, forKey: .fileKindFilter)
        try c.encodeIfPresent(minSizeBytes, forKey: .minSizeBytes)
        try c.encodeIfPresent(maxSizeBytes, forKey: .maxSizeBytes)
        try c.encodeIfPresent(dateAddedPredicate, forKey: .dateAddedPredicate)
        try c.encode(destinationRelativePath, forKey: .destinationRelativePath)
        try c.encode(renameStyle, forKey: .renameStyle)
        try c.encode(renameTemplate, forKey: .renameTemplate)
        try c.encode(matchAction, forKey: .matchAction)
        try c.encode(addedTags, forKey: .addedTags)
        try c.encode(finderTagPolicy, forKey: .finderTagPolicy)
        try c.encode(categoryDefaultReplacementTags, forKey: .categoryDefaultReplacementTags)
        try c.encode(originDomains, forKey: .originDomains)
        try c.encode(contentMatch, forKey: .contentMatch)
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
            originDomains: [],
            contentMatch: .disabled,
            destinationRelativePath: "Misc",
            renameStyle: .none,
            renameTemplate: "{date} {stem}{ext}",
            matchAction: .moveToDestination,
            addedTags: [],
            finderTagPolicy: .additive,
            categoryDefaultReplacementTags: []
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
        originDomains: [String] = [],
        contentMatch: SortContentMatch = .disabled,
        destinationRelativePath: String,
        renameStyle: SortRenameStyle,
        renameTemplate: String,
        matchAction: SortRuleMatchAction = .moveToDestination,
        addedTags: [String] = [],
        finderTagPolicy: SortRuleFinderTagPolicy = .additive,
        categoryDefaultReplacementTags: [String] = []
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
        self.originDomains = originDomains
        self.contentMatch = contentMatch
        self.destinationRelativePath = destinationRelativePath
        self.renameStyle = renameStyle
        self.renameTemplate = renameTemplate
        self.matchAction = matchAction
        self.addedTags = addedTags
        self.finderTagPolicy = finderTagPolicy
        self.categoryDefaultReplacementTags = categoryDefaultReplacementTags
    }

    /// Starter fields for a new rule when the user is triaging a file from Review.
    static func draftFromReviewFile(url: URL, order: Int) -> InboxSortRule {
        var rule = InboxSortRule.fresh(order: order)
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
