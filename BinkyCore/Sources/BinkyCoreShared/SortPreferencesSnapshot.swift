import Foundation

/// Frozen prefs and routing for one sort pass — safe to use from ``Task.detached``.
public struct SortPreferencesSnapshot: Sendable {
    public let excludeExtensions: Set<String>
    public let excludeNameFragments: [String]
    public let sortCustomRulesEnabled: Bool
    public let sortRoutingRules: [SortRule]
    public let sortAppendNewSemanticTagEnabled: Bool
    public let assignFinderTagsOnSortEnabled: Bool
    public let finderTagDefaultsByCategory: [String: [String]]
    public let globalInboxRoot: URL
    public let watchRegistry: WatchPipelineRegistry
    public let presetsByID: [UUID: CompressionPreset]
    public let sortDuplicateMode: SortDuplicateHandlingMode
    public let sortSmartScreenshotNamesEnabled: Bool
    public let sortDetectReceiptsEnabled: Bool
    public let watchRecursiveOneLevel: Bool
    /// Preset / routine order (for combining rules when multiple routines share a folder).
    public let savedPresetOrder: [UUID]
    /// Lowercased Finder tags — files tagged with any of these are never sorted.
    public let globalSkipTagSet: Set<String>
    public let slowMode: Bool

    public init(
        excludeExtensions: Set<String>,
        excludeNameFragments: [String],
        sortCustomRulesEnabled: Bool,
        sortRoutingRules: [SortRule],
        sortAppendNewSemanticTagEnabled: Bool,
        assignFinderTagsOnSortEnabled: Bool,
        finderTagDefaultsByCategory: [String: [String]],
        globalInboxRoot: URL,
        watchRegistry: WatchPipelineRegistry,
        presetsByID: [UUID: CompressionPreset],
        sortDuplicateMode: SortDuplicateHandlingMode,
        sortSmartScreenshotNamesEnabled: Bool,
        sortDetectReceiptsEnabled: Bool,
        watchRecursiveOneLevel: Bool,
        savedPresetOrder: [UUID],
        globalSkipTagSet: Set<String>,
        slowMode: Bool
    ) {
        self.excludeExtensions = excludeExtensions
        self.excludeNameFragments = excludeNameFragments
        self.sortCustomRulesEnabled = sortCustomRulesEnabled
        self.sortRoutingRules = sortRoutingRules
        self.sortAppendNewSemanticTagEnabled = sortAppendNewSemanticTagEnabled
        self.assignFinderTagsOnSortEnabled = assignFinderTagsOnSortEnabled
        self.finderTagDefaultsByCategory = finderTagDefaultsByCategory
        self.globalInboxRoot = globalInboxRoot
        self.watchRegistry = watchRegistry
        self.presetsByID = presetsByID
        self.sortDuplicateMode = sortDuplicateMode
        self.sortSmartScreenshotNamesEnabled = sortSmartScreenshotNamesEnabled
        self.sortDetectReceiptsEnabled = sortDetectReceiptsEnabled
        self.watchRecursiveOneLevel = watchRecursiveOneLevel
        self.savedPresetOrder = savedPresetOrder
        self.globalSkipTagSet = globalSkipTagSet
        self.slowMode = slowMode
    }
}

/// What to do when a file matches an existing hash (or near-duplicate image).
public enum SortDuplicateHandlingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case moveToDuplicates
    case moveToTrash

    public var id: String { rawValue }
}
