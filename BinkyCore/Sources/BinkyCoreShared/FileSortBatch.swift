import Foundation

public enum FileSortCategory: String, CaseIterable, Codable, Sendable {
    case images, pdf, video, audio, documents, archives, apps, screenshots, misc, review, duplicates, receipts

    public var downloadsSubfolder: String {
        switch self {
        case .images: return "Images"
        case .pdf, .documents: return "Documents"
        case .video, .audio: return "Media"
        case .archives: return "Archives"
        case .apps: return "Apps"
        case .screenshots: return "Screenshots"
        case .misc: return "Misc"
        case .review: return "Review"
        case .duplicates: return "Duplicates"
        case .receipts: return "Receipts"
        }
    }

    public var semanticTagHint: String {
        switch self {
        case .review: return "Review"
        case .misc: return "Temporary"
        case .apps: return "Installer"
        case .archives: return "Archive"
        case .pdf, .documents: return "Receipt"
        case .duplicates: return "Duplicate"
        case .receipts: return "Receipt"
        default: return "New"
        }
    }

    public var sortAnimationBucket: SortAnimationBucket {
        switch self {
        case .images, .screenshots: return .images
        case .video: return .videos
        case .pdf, .audio, .documents, .archives, .apps, .misc, .review, .duplicates, .receipts: return .documents
        }
    }
}

public enum SortDisposition: String, Codable, Sendable {
    case moved, kept
    case skippedTransient, skippedStableCheckTimeout, skippedError, skippedExcluded
    case skippedDuplicate
}

public struct SortBatchEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let sourcePath: String
    public let destinationPath: String?
    public let category: FileSortCategory
    public let disposition: SortDisposition
    public let reason: String
    public let matchedRuleName: String?
    public let originHost: String?

    enum CodingKeys: String, CodingKey {
        case id, sourcePath, destinationPath, category, disposition, reason, matchedRuleName, originHost
    }

    public init(
        id: UUID,
        sourcePath: String,
        destinationPath: String?,
        category: FileSortCategory,
        disposition: SortDisposition,
        reason: String,
        matchedRuleName: String?,
        originHost: String? = nil
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.category = category
        self.disposition = disposition
        self.reason = reason
        self.matchedRuleName = matchedRuleName
        self.originHost = originHost
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourcePath = try c.decode(String.self, forKey: .sourcePath)
        destinationPath = try c.decodeIfPresent(String.self, forKey: .destinationPath)
        category = try c.decode(FileSortCategory.self, forKey: .category)
        disposition = try c.decode(SortDisposition.self, forKey: .disposition)
        reason = try c.decode(String.self, forKey: .reason)
        matchedRuleName = try c.decodeIfPresent(String.self, forKey: .matchedRuleName)
        originHost = try c.decodeIfPresent(String.self, forKey: .originHost)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sourcePath, forKey: .sourcePath)
        try c.encodeIfPresent(destinationPath, forKey: .destinationPath)
        try c.encode(category, forKey: .category)
        try c.encode(disposition, forKey: .disposition)
        try c.encode(reason, forKey: .reason)
        try c.encodeIfPresent(matchedRuleName, forKey: .matchedRuleName)
        try c.encodeIfPresent(originHost, forKey: .originHost)
    }
}
