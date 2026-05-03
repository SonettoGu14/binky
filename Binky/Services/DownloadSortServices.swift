import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tier stub

enum BinkySubscriptionTier: String, Codable, Sendable {
    case free, plus

    static var current: BinkySubscriptionTier {
        UserDefaults.standard.bool(forKey: "binky.plusUnlocked") ? .plus : .free
    }
}

// MARK: - Semantic destinations + starter folders

enum FileSortCategory: String, CaseIterable, Codable, Sendable {
    case images, pdf, video, audio, documents, archives, apps, screenshots, misc, review, duplicates, receipts

    var downloadsSubfolder: String {
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

    /// Optional Finder-tag hint appended when tagging is enabled.
    var semanticTagHint: String {
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

    /// Three-bucket visuals for organizer empty-state animation. Non-image/video routes to `documents`.
    var sortAnimationBucket: SortAnimationBucket {
        switch self {
        case .images, .screenshots: return .images
        case .video: return .videos
        case .pdf, .audio, .documents, .archives, .apps, .misc, .review, .duplicates, .receipts: return .documents
        }
    }
}

enum SortDisposition: String, Codable, Sendable {
    case moved, kept
    case skippedTransient, skippedStableCheckTimeout, skippedError, skippedExcluded
    case skippedDuplicate
}

struct SortBatchEntry: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let sourcePath: String
    let destinationPath: String?
    let category: FileSortCategory
    let disposition: SortDisposition
    let reason: String
    /// Present when a user-defined inbox rule chose the destination.
    let matchedRuleName: String?
    /// Primary download source host from `kMDItemWhereFroms`, if any.
    let originHost: String?

    enum CodingKeys: String, CodingKey {
        case id, sourcePath, destinationPath, category, disposition, reason, matchedRuleName, originHost
    }

    init(
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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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

struct SortBatchOutcome: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let started: Date
    let elapsed: TimeInterval
    let entries: [SortBatchEntry]
    /// Secondary messages (Finder tag failures, offline tools, etc.) — not persisted as audit rows.
    var ancillaryWarnings: [String]

    var movedCount: Int { entries.filter { $0.disposition == .moved }.count }
    var keptCount: Int { entries.filter { $0.disposition == .kept }.count }

    var skippedCount: Int {
        entries.count(where: {
            switch $0.disposition {
            case .skippedTransient, .skippedStableCheckTimeout, .skippedError, .skippedExcluded, .skippedDuplicate: return true
            default: return false
            }
        })
    }

    /// Review folder moves (confidence path).
    var reviewQueuedCount: Int {
        entries.filter { $0.disposition == .moved && $0.category == .review }.count
    }

    /// True whenever we produced any audit rows (including skips).
    var hasWork: Bool { !entries.isEmpty }

    var reversibleMoves: [(destination: URL, source: URL)] {
        entries.compactMap {
            guard $0.disposition == .moved, let dst = $0.destinationPath else { return nil }
            return (URL(fileURLWithPath: dst), URL(fileURLWithPath: $0.sourcePath))
        }
    }

    init(id: UUID, started: Date, elapsed: TimeInterval, entries: [SortBatchEntry], ancillaryWarnings: [String] = []) {
        self.id = id
        self.started = started
        self.elapsed = elapsed
        self.entries = entries
        self.ancillaryWarnings = ancillaryWarnings
    }

    enum CodingKeys: String, CodingKey {
        case id, started, elapsed, entries, ancillaryWarnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        started = try c.decode(Date.self, forKey: .started)
        elapsed = try c.decode(TimeInterval.self, forKey: .elapsed)
        entries = try c.decode([SortBatchEntry].self, forKey: .entries)
        ancillaryWarnings = try c.decodeIfPresent([String].self, forKey: .ancillaryWarnings) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(started, forKey: .started)
        try c.encode(elapsed, forKey: .elapsed)
        try c.encode(entries, forKey: .entries)
        if !ancillaryWarnings.isEmpty {
            try c.encode(ancillaryWarnings, forKey: .ancillaryWarnings)
        }
    }
}

extension SortBatchOutcome {
    /// Most likely originating watch root, derived by tallying which automation path is the longest
    /// matching prefix of each entry's source. Robust to sweeps that pull from subfolders.
    func matchedAutomation(in presets: [CompressionPreset]) -> CompressionPreset? {
        guard !entries.isEmpty else { return nil }
        var tally: [UUID: (preset: CompressionPreset, hits: Int, length: Int)] = [:]

        for entry in entries {
            let sourcePath = URL(fileURLWithPath: entry.sourcePath).standardizedFileURL.path
            var localBest: (preset: CompressionPreset, length: Int)?
            for preset in presets {
                let raw = preset.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                let normalized = URL(fileURLWithPath: raw).standardizedFileURL.path
                guard sourcePath == normalized || sourcePath.hasPrefix(normalized + "/") else { continue }
                if localBest == nil || normalized.count > localBest!.length {
                    localBest = (preset, normalized.count)
                }
            }
            if let lb = localBest {
                if var existing = tally[lb.preset.id] {
                    existing.hits += 1
                    tally[lb.preset.id] = existing
                } else {
                    tally[lb.preset.id] = (lb.preset, 1, lb.length)
                }
            }
        }

        return tally.values.max { lhs, rhs in
            if lhs.hits != rhs.hits { return lhs.hits < rhs.hits }
            return lhs.length < rhs.length
        }?.preset
    }

    /// Folder to reveal when the user wants to "Show in Finder" the place this sort acted on.
    func sourceRootURL(in presets: [CompressionPreset]) -> URL? {
        if let preset = matchedAutomation(in: presets),
           !preset.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: preset.watchFolderPath).standardizedFileURL
        }
        guard let firstSource = entries.first?.sourcePath else { return nil }
        return URL(fileURLWithPath: firstSource).deletingLastPathComponent()
    }
}

// MARK: - Transient filenames

private let suspiciousSuffixes: [String] = [
    ".crdownload", ".download", ".part", ".partial",
    "~", ".tmp", ".temp",
]

private func looksTransientIncomplete(_ url: URL) -> Bool {
    let n = url.lastPathComponent.lowercased()
    if n == ".ds_store" { return false }
    if n.hasPrefix(".") { return true }
    return suspiciousSuffixes.contains(where: { n.hasSuffix($0) })
}

// MARK: - Stability waits

private func waitUntilStable(
    at url: URL,
    maxSeconds: Double = 120,
    continueCheck: (() async -> Bool)? = nil
) async -> Bool {
    let fm = FileManager.default
    var lastBytes: Int64?
    var lastMod: Date?
    var unchangedHits = 0
    let end = Date().addingTimeInterval(maxSeconds)

    while Date() < end {
        if let continueCheck, await continueCheck() == false {
            return false
        }
        guard fm.fileExists(atPath: url.path) else { return false }
        do {
            let v = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let sz = Int64(v.fileSize ?? -1)
            let m = v.contentModificationDate
            if sz == lastBytes, m == lastMod {
                unchangedHits += 1
                if unchangedHits >= 2 {
                    try await Task.sleep(nanoseconds: 600_000_000)
                    return true
                }
            } else {
                unchangedHits = 0
            }
            lastBytes = sz
            lastMod = m
            try await Task.sleep(nanoseconds: 380_000_000)
        } catch {
            return false
        }
    }
    return false
}

/// Skips the multi-second stability poll when the file clearly finished landing (not a fresh download).
private func fileLooksStableWithoutPolling(url: URL) -> Bool {
    guard !looksTransientIncomplete(url) else { return false }
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else { return false }
    guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey]),
          let modified = vals.contentModificationDate else {
        return false
    }
    let anchor = vals.addedToDirectoryDate.map { max($0, modified) } ?? modified
    return Date().timeIntervalSince(anchor) >= 3
}

// MARK: - Classification

private func screenshotHeuristic(_ url: URL) -> Bool {
    let base = url.deletingPathExtension().lastPathComponent.lowercased()
    return base.contains("screen shot") || base.contains("screenshot") || base.hasPrefix("screenshot ")
}

enum FileClassification {

    /// Unknown → Review for trust-first behavior.
    static func categorize(url: URL) -> FileSortCategory {
        let ext = url.pathExtension.lowercased()

        if looksTransientIncomplete(url) { return .review }

        let archives: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]
        let images: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif"]
        let videos: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv"]
        let audio: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg"]
        let documentsNoPDF: Set<String> = ["doc", "docx", "rtf", "txt", "md", "pages", "key", "numbers", "ppt", "pptx", "xls", "xlsx", "csv", "json", "html", "xml", "swift"]
        /// PDF treated separately unless screenshot-like name.
        if ext == "pdf" {
            return screenshotHeuristic(url) ? .screenshots : .pdf
        }
        if ext == "dmg" || ext == "pkg" { return .apps }
        if archives.contains(ext) { return .archives }

        let utOptional = UTType(filenameExtension: ext)
        let utMatchesImage = utOptional?.conforms(to: .image) ?? false

        switch true {
        case utMatchesImage, images.contains(ext):
            return screenshotHeuristic(url) ? .screenshots : .images
        case utOptional?.conforms(to: .movie) == true || utOptional?.conforms(to: .video) == true || videos.contains(ext):
            return .video
        case utOptional?.conforms(to: .audio) == true || audio.contains(ext):
            return .audio
        case documentsNoPDF.contains(ext):
            return .documents
        case ext.isEmpty:
            return .review
        default:
            return .review
        }
    }
}

// MARK: - Finder tags (optional)

/// Applies Finder-visible tags via the `com.apple.metadata:_kMDItemUserTags` extended attribute,
/// avoiding Swift overlays that declare `NSURLResourceValues.tagNames` accessors only on macOS 26+.
enum FinderTagApplicator {

    private static let xattrName = "com.apple.metadata:_kMDItemUserTags"

    /// Finder-visible tag display names on a file (from xattr), for rule matching / exclusions.
    static func readTagNames(for url: URL) -> [String] {
        normalizedTagStrings(existingPlistData(onPath: url.path))
    }

    /// - Returns: Whether the xattr write succeeded (or was a no-op merge).
    @discardableResult
    static func merge(_ newTags: [String], onto url: URL) -> Bool {
        let trimmed = newTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return true }

        let path = url.path

        let existingNormalized = normalizedTagStrings(existingPlistData(onPath: path))
        let merged = Array(Set(existingNormalized).union(trimmed)).sorted()

        guard let data = try? PropertyListSerialization.data(fromPropertyList: merged, format: .binary, options: 0),
              merged != existingNormalized || existingPlistData(onPath: path) == nil
        else { return true }

        var ok = false
        path.withCString { cPath in
            data.withUnsafeBytes { ptr in
                guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else {
                    ok = false
                    return
                }
                let rc = Darwin.setxattr(cPath, xattrName, base, data.count, 0, 0)
                ok = (rc == 0)
            }
        }
        return ok
    }

    /// Removes tag names (case-insensitive) from Finder tags, rewriting the xattr as a simple string list.
    static func remove(tagNames: Set<String>, from url: URL) {
        guard !tagNames.isEmpty else { return }
        let lower = Set(tagNames.map { $0.lowercased() })
        let path = url.path
        let existing = normalizedTagStrings(existingPlistData(onPath: path))
        let filtered = existing.filter { tag in
            let fragment = (tag.components(separatedBy: "\n").first ?? tag)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !lower.contains(fragment.lowercased())
        }
        guard filtered.count != existing.count else { return }

        if filtered.isEmpty {
            _ = path.withCString { Darwin.removexattr($0, xattrName, 0) }
            return
        }

        guard let data = try? PropertyListSerialization.data(fromPropertyList: filtered, format: .binary, options: 0)
        else { return }

        path.withCString { cPath in
            data.withUnsafeBytes { ptr in
                let buf = UnsafeRawPointer(ptr.bindMemory(to: UInt8.self).baseAddress!)
                let _ = Darwin.setxattr(cPath, xattrName, buf, data.count, 0, 0)
            }
        }
    }

    private static func existingPlistData(onPath path: String) -> Data? {
        let need = path.withCString { getxattr($0, xattrName, nil, 0, 0, 0) }
        guard need > 0 else { return nil }
        var raw = Data(count: need)
        let written = raw.withUnsafeMutableBytes { blob in
            path.withCString { getxattr($0, xattrName, blob.bindMemory(to: UInt8.self).baseAddress!, need, 0, 0) }
        }
        guard written == need else { return nil }
        return raw
    }

    private static func normalizedTagStrings(_ data: Data?) -> [String] {
        guard let data else { return [] }
        let plistOpt: Any? = try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainers], format: nil)
        guard let obj = plistOpt else { return [] }
        switch obj {
        case let strings as [String]:
            return strings.map { String($0) }
        case let arr as NSArray:
            /// Modern Finder plist entries can bundle display text + Finder color identifiers in small dictionaries.
            return arr.flatMap(Self.tagStringFragments(fromTaggedPlistEntry:)).filter { !$0.isEmpty }
        default:
            return []
        }
    }

    private static func tagStringFragments(fromTaggedPlistEntry entry: Any) -> [String] {
        if let s = entry as? String { return [s.components(separatedBy: "\n").first ?? s] }
        if let dict = entry as? [String: Any] {
            for key in candidateTagDictionaryKeys {
                if let s = dict[key] as? String, !s.isEmpty { return [s.components(separatedBy: "\n").first ?? s] }
            }
        }
        return []
    }

    /// Keys sometimes present for serialized Finder-tag rows (varies by OS revision).
    private static let candidateTagDictionaryKeys: [String] = [
        "kMDItemUserTags",
        "NSDisplayString",
        "displayString",
        "tag",
        "_kMDItemUserTags",
        "NSTaggedFilenameKey",
    ]
}

private enum PostSortShortcutRunner {
    static func run(shortcutName: String, fileURL: URL) {
        let trimmed = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        let encName = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        let text = fileURL.absoluteString
        let encText = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        guard let url = URL(string: "shortcuts://run-shortcut?name=\(encName)&input=text&text=\(encText)") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Sort snapshot + detached loop (energy-aware)

/// Frozen prefs and routing for one sort pass — safe to use from ``Task.detached``.
struct SortPreferencesSnapshot: Sendable {
    let excludeExtensions: Set<String>
    let excludeNameFragments: [String]
    let sortCustomRulesEnabled: Bool
    let sortRoutingRules: [SortRule]
    let sortAppendNewSemanticTagEnabled: Bool
    let assignFinderTagsOnSortEnabled: Bool
    let finderTagDefaultsByCategory: [String: [String]]
    let globalInboxRoot: URL
    let watchRegistry: WatchPipelineRegistry
    let presetsByID: [UUID: CompressionPreset]
    let sortDuplicateMode: SortDuplicateHandlingMode
    let sortSmartScreenshotNamesEnabled: Bool
    let sortDetectReceiptsEnabled: Bool
    let watchRecursiveOneLevel: Bool
    /// Preset / automation order (for combining rules when multiple automations share a folder).
    let savedPresetOrder: [UUID]
    /// Lowercased Finder tags — files tagged with any of these are never sorted.
    let globalSkipTagSet: Set<String>
    /// When `true`, the work loop processes files one at a time with a per-file delay so the user
    /// can read along in the progress UI. Defaults to `false`.
    let slowMode: Bool
}

/// What to do when a file matches an existing hash (or near-duplicate image).
enum SortDuplicateHandlingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case moveToDuplicates
    case moveToTrash

    var id: String { rawValue }
}

private extension BinkyPreferences {
    @MainActor
    func makeSortPreferencesSnapshot() -> SortPreferencesSnapshot {
        var byPresetID: [UUID: CompressionPreset] = [:]
        for p in savedPresets {
            byPresetID[p.id] = p
        }
        return SortPreferencesSnapshot(
            excludeExtensions: sortExcludeExtensionsNormalized(),
            excludeNameFragments: sortExcludeNameFragmentsNormalized(),
            sortCustomRulesEnabled: sortCustomRulesEnabled,
            sortRoutingRules: sortRoutingRules,
            sortAppendNewSemanticTagEnabled: sortAppendNewSemanticTagEnabled,
            assignFinderTagsOnSortEnabled: assignFinderTagsOnSortEnabled,
            finderTagDefaultsByCategory: sortFinderTagDefaultsByCategory,
            globalInboxRoot: downloadsSortRootDirectory(),
            watchRegistry: WatchPipelineRegistry(prefs: self),
            presetsByID: byPresetID,
            sortDuplicateMode: SortDuplicateHandlingMode(rawValue: sortDuplicateModeRaw) ?? .off,
            sortSmartScreenshotNamesEnabled: sortSmartScreenshotNamesEnabled,
            sortDetectReceiptsEnabled: sortDetectReceiptsEnabled,
            watchRecursiveOneLevel: watchRecursiveOneLevel,
            savedPresetOrder: savedPresets.map(\.id),
            globalSkipTagSet: Set(
                globalSkipTags
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            ),
            slowMode: sortSlowModeEnabled
        )
    }
}

private func sortInboxContext(for fileURL: URL, snapshot: SortPreferencesSnapshot) -> (inboxRoot: URL, presets: [CompressionPreset]) {
    let reg = snapshot.watchRegistry
    switch reg.routing(for: fileURL) {
    case .global:
        return (snapshot.globalInboxRoot, [])
    case .automation(let root, let ids):
        let idSet = Set(ids)
        let presets = snapshot.savedPresetOrder.compactMap { snapshot.presetsByID[$0] }.filter { idSet.contains($0.id) }
        return (root, presets)
    }
}

private func isRasterImageExtensionForSort(_ ext: String) -> Bool {
    ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"].contains(ext)
}

private func isURLExcludedForSort(url: URL, snapshot: SortPreferencesSnapshot) -> Bool {
    let ext = url.pathExtension.lowercased()
    if !snapshot.excludeExtensions.isEmpty, snapshot.excludeExtensions.contains(ext) {
        return true
    }
    let base = url.lastPathComponent
    for fragment in snapshot.excludeNameFragments {
        guard !fragment.isEmpty else { continue }
        if base.localizedCaseInsensitiveContains(fragment) {
            return true
        }
    }
    return false
}

private func activeSortRulesForSnapshot(snapshot: SortPreferencesSnapshot, presets: [CompressionPreset]) -> [SortRule] {
    let combined = presets.flatMap(\.sortRules)
    if !combined.isEmpty {
        return combined
    }
    return snapshot.sortCustomRulesEnabled ? snapshot.sortRoutingRules : []
}

private func composedFinderTagsForSort(
    snapshot: SortPreferencesSnapshot,
    naturalCategory: FileSortCategory,
    presets: [CompressionPreset],
    matchedRule: SortRule?
) -> [String] {
    FinderTagComposer.compose(
        naturalCategory: naturalCategory,
        globalDefaults: snapshot.finderTagDefaultsByCategory,
        preset: presets.first,
        matchedRule: matchedRule,
        appendNewSemanticTag: snapshot.sortAppendNewSemanticTagEnabled
    )
}

private func fileURLMatchesGlobalSkipTags(_ url: URL, snapshot: SortPreferencesSnapshot) -> Bool {
    guard !snapshot.globalSkipTagSet.isEmpty else { return false }
    let tags = FinderTagApplicator.readTagNames(for: url)
    return tags.contains { snapshot.globalSkipTagSet.contains($0.lowercased()) }
}

private func combinedTagFanoutPriority(presets: [CompressionPreset]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for p in presets {
        for t in p.tagFanoutPriority {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let k = trimmed.lowercased()
            if seen.insert(k).inserted {
                out.append(trimmed)
            }
        }
    }
    return out
}

private func newTagExpiryDays(from presets: [CompressionPreset]) -> Int {
        presets.first(where: { $0.newTagExpiryDays > 0 })?.newTagExpiryDays ?? 0
}

private func postSortShortcutName(from presets: [CompressionPreset]) -> String {
    for p in presets {
        let t = p.postSortShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
    }
    return ""
}

private func destinationDisplayLabelForSort(root: URL, destinationDir: URL) -> String {
    let rootPath = root.path
    let destPath = destinationDir.path
    guard destPath.hasPrefix(rootPath) else { return destinationDir.lastPathComponent }
    let tail = String(destPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return tail.isEmpty ? destinationDir.lastPathComponent : tail
}

private func localizedMoveReasonForSort(matchedRuleName: String?, destinationDir: URL, inboxRoot: URL) -> String {
    let label = destinationDisplayLabelForSort(root: inboxRoot, destinationDir: destinationDir)
    if let matchedRuleName {
        return String.localizedStringWithFormat(
            String(localized: "Moved into “%1$@” (rule “%2$@”).", comment: "Sort audit when a custom rule matched."),
            label,
            matchedRuleName
        )
    }
    return String.localizedStringWithFormat(
        String(localized: "Moved into “%@”.", comment: "Sort audit reason; formatted folder name."),
        label
    )
}

private final class SortRunGate: @unchecked Sendable {
    private enum ControlState {
        case running
        case paused
        case stopRequested
    }

    private let lock = NSLock()
    private var control: ControlState = .running
    private var sessionActive = true

    func setRunning() {
        lock.lock()
        control = .running
        lock.unlock()
    }

    func setPaused() {
        lock.lock()
        control = .paused
        lock.unlock()
    }

    func setStopRequested() {
        lock.lock()
        control = .stopRequested
        lock.unlock()
    }

    func stopRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return control == .stopRequested
    }

    func endSession() {
        lock.lock()
        sessionActive = false
        lock.unlock()
    }

    func continueWhenSortPermitsProgress() async -> Bool {
        while true {
            let (c, active) = snapshot()
            if !active { return false }
            if c == .paused {
                try? await Task.sleep(for: .milliseconds(130))
                if Task.isCancelled { return false }
                continue
            }
            return c != .stopRequested
        }
    }

    private func snapshot() -> (ControlState, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (control, sessionActive)
    }
}

// MARK: - Parallel sort helpers

private struct SortIndexedFileResult: Sendable {
    let rows: [SortBatchEntry]
    let tagWriteFailures: Int
}

private actor SortRenameCounterActor {
    private var value = 1

    func nextValue(forRenameStyle style: SortRenameStyle) -> Int {
        let out = value
        if style != .none { value += 1 }
        return out
    }
}

/// Serializes uniquify + move into the same destination folder across concurrent sort tasks.
private final class PerDestinationUniquifyGate: @unchecked Sendable {
    private let master = NSLock()
    private var locks: [String: NSLock] = [:]

    func sync<R>(directory: URL, _ body: () throws -> R) rethrows -> R {
        let key = directory.standardizedFileURL.path
        master.lock()
        let lock: NSLock
        if let existing = locks[key] {
            lock = existing
        } else {
            let fresh = NSLock()
            locks[key] = fresh
            lock = fresh
        }
        master.unlock()
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private enum SortZipViaDitto {
    /// Creates a zip at `zipDestinationURL` from `sourceFile`, then removes the source file on success.
    static func zipReplacingSource(file sourceFile: URL, zipDestinationURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: zipDestinationURL.path) {
            try fm.removeItem(at: zipDestinationURL)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", sourceFile.path, zipDestinationURL.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(
                domain: "BinkySortZip",
                code: Int(p.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Couldn’t create zip archive."]
            )
        }
        try fm.removeItem(at: sourceFile)
    }
}

private enum SortWork {
    nonisolated static func applyEnergyThrottleBetweenFiles(batchSize: Int) async {
        if !EnergyConditions.shared.shouldPauseFully {
            if batchSize < SortEnergy.bigBatchFileCount {
                let sleepNanos = EnergyConditions.shared.interFileSleepNanos(batchSize: batchSize)
                if sleepNanos == 0 { return }
                try? await Task.sleep(nanoseconds: sleepNanos)
                return
            }
            await Task.yield()
            let sleepNanos = EnergyConditions.shared.interFileSleepNanos(batchSize: batchSize)
            if sleepNanos > 0 {
                try? await Task.sleep(nanoseconds: sleepNanos)
            }
            return
        }
        let holdKind = EnergyConditions.shared.energyHoldKindForProgressUI()
        await MainActor.run {
            SortProgressTracker.shared.setEnergyHold(holdKind)
        }
        await EnergyConditions.shared.waitUntilOK()
        await MainActor.run {
            SortProgressTracker.shared.clearEnergyHold()
        }
        let sleepNanos = EnergyConditions.shared.interFileSleepNanos(batchSize: batchSize)
        if sleepNanos > 0 {
            try? await Task.sleep(nanoseconds: sleepNanos)
        }
    }

    /// Runs the per-file pipeline off the main actor. Progress closure is ``Sendable`` and safe to call from here.
    /// `rootOverride` lets the caller pin specific files to an ad-hoc inbox root (e.g. a right-clicked folder).
    nonisolated static func runSortWorkLoop(
        workURLs: [URL],
        snapshot: SortPreferencesSnapshot,
        rootOverride: [URL: URL],
        gate: SortRunGate,
        progress: (@Sendable (SortProgressEvent) -> Void)?
    ) async -> (rows: [SortBatchEntry], tagWriteFailures: Int) {
        guard !workURLs.isEmpty else { return (rows: [], tagWriteFailures: 0) }
        let batchSize = workURLs.count
        let destGate = PerDestinationUniquifyGate()
        let renameCounter = SortRenameCounterActor()
        // Slow mode forces sequential processing so each file's progress UI is readable.
        let maxConcurrent = snapshot.slowMode
            ? 1
            : min(8, max(1, ProcessInfo.processInfo.processorCount))
        let runOne: @Sendable (URL) async -> SortIndexedFileResult = { standardized in
            let fm = FileManager.default
            var rows: [SortBatchEntry] = []
            var tagWriteFailures = 0

            guard await gate.continueWhenSortPermitsProgress() else {
                return SortIndexedFileResult(rows: [], tagWriteFailures: 0)
            }
            let pathKey = standardized.path
            let displayName = standardized.lastPathComponent
            var didReportFileStarted = false
            defer {
                if didReportFileStarted {
                    progress?(.fileFinished(path: pathKey))
                }
            }

            func emitFileStarted(categoryForAnimation: FileSortCategory) {
                progress?(.fileStarted(path: pathKey, displayName: displayName, animationBucket: categoryForAnimation.sortAnimationBucket))
                didReportFileStarted = true
            }

            if looksTransientIncomplete(standardized) {
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                emitFileStarted(categoryForAnimation: .review)
                rows.append(SortBatchEntry(
                    id: UUID(), sourcePath: standardized.path, destinationPath: nil, category: .review, disposition: .skippedTransient,
                    reason: String(localized: "Temporary download artifact — skipping until finalized.", comment: "Sort log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            guard await gate.continueWhenSortPermitsProgress() else {
                return SortIndexedFileResult(rows: [], tagWriteFailures: 0)
            }
            let stableOK: Bool
            if fileLooksStableWithoutPolling(url: standardized) {
                stableOK = true
            } else {
                stableOK = await waitUntilStable(at: standardized, continueCheck: {
                    await gate.continueWhenSortPermitsProgress()
                })
            }
            guard stableOK else {
                if gate.stopRequested() {
                    return SortIndexedFileResult(rows: [], tagWriteFailures: 0)
                }
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                emitFileStarted(categoryForAnimation: .review)
                rows.append(SortBatchEntry(
                    id: UUID(), sourcePath: standardized.path, destinationPath: nil, category: .review, disposition: .skippedStableCheckTimeout,
                    reason: String(localized: "File never stabilized before timeout.", comment: "Sort log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            guard await gate.continueWhenSortPermitsProgress() else {
                return SortIndexedFileResult(rows: [], tagWriteFailures: 0)
            }
            if isURLExcludedForSort(url: standardized, snapshot: snapshot) {
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                emitFileStarted(categoryForAnimation: .misc)
                rows.append(SortBatchEntry(
                    id: UUID(), sourcePath: standardized.path, destinationPath: nil, category: .misc, disposition: .skippedExcluded,
                    reason: String(localized: "Skipped — file matches your ignore list.", comment: "Sort log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            if fileURLMatchesGlobalSkipTags(standardized, snapshot: snapshot) {
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                emitFileStarted(categoryForAnimation: .misc)
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: .misc,
                    disposition: .skippedExcluded,
                    reason: String(localized: "Skipped — file has a protected Finder tag.", comment: "Sort log: global skip tag."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            let signals = SortRulesEvaluator.loadSignals(url: standardized)
                ?? SortRulesEvaluator.FileSignals(
                    ext: standardized.pathExtension.lowercased(),
                    baseName: standardized.lastPathComponent,
                    byteSize: 0,
                    addedToDirectoryDate: nil,
                    creationDate: nil,
                    modificationDate: nil,
                    originHosts: WhereFromsReader.originHosts(forFileAt: standardized)
                )

            let fileTags = FinderTagApplicator.readTagNames(for: standardized)

            let originHost = signals.originHosts.first

            let (defaultRoot, presets) = sortInboxContext(for: standardized, snapshot: snapshot)
            let inboxRoot = rootOverride[standardized] ?? defaultRoot
            let activeRules = activeSortRulesForSnapshot(snapshot: snapshot, presets: presets)

            var pendingFileDigest: (sha256: String, perceptual: UInt64?, isImage: Bool)?
            if snapshot.sortDuplicateMode != .off {
                do {
                    let digestTry = try FileHashStore.shared.digestFile(at: standardized)
                    let lookup = FileHashStore.shared.lookup(
                        sha256: digestTry.sha256,
                        perceptual: digestTry.perceptual,
                        isImage: digestTry.isImage
                    )
                    if lookup.isByteDuplicate || lookup.isNearImageDuplicate {
                        emitFileStarted(categoryForAnimation: .duplicates)
                        let dupReason = String(
                            localized: "Duplicate of a file Binky has seen before — skipping per your settings.",
                            comment: "Sort log duplicate."
                        )
                        if snapshot.sortDuplicateMode == .moveToTrash {
                            do {
                                try fm.trashItem(at: standardized, resultingItemURL: nil)
                                rows.append(SortBatchEntry(
                                    id: UUID(),
                                    sourcePath: standardized.path,
                                    destinationPath: nil,
                                    category: .duplicates,
                                    disposition: .skippedDuplicate,
                                    reason: dupReason,
                                    matchedRuleName: nil,
                                    originHost: originHost
                                ))
                            } catch {
                                rows.append(SortBatchEntry(
                                    id: UUID(),
                                    sourcePath: standardized.path,
                                    destinationPath: nil,
                                    category: .duplicates,
                                    disposition: .skippedError,
                                    reason: error.localizedDescription,
                                    matchedRuleName: nil,
                                    originHost: originHost
                                ))
                            }
                        } else {
                            let dupDir = StarterDestinations.directory(for: .duplicates, root: inboxRoot)
                            do {
                                let dest: URL = try destGate.sync(directory: dupDir) {
                                    try fm.createDirectory(at: dupDir, withIntermediateDirectories: true)
                                    let destInner = DownloadsSortOrchestrator.uniquify(
                                        destinationDirectory: dupDir,
                                        preferredFilename: standardized.lastPathComponent
                                    )
                                    try fm.moveItem(at: standardized, to: destInner)
                                    return destInner
                                }
                                FileHashStore.shared.recordSortedFile(
                                    url: dest,
                                    sha256: digestTry.sha256,
                                    byteSize: signals.byteSize,
                                    perceptual: digestTry.perceptual,
                                    isImage: digestTry.isImage
                                )
                                rows.append(SortBatchEntry(
                                    id: UUID(),
                                    sourcePath: standardized.path,
                                    destinationPath: dest.path,
                                    category: .duplicates,
                                    disposition: .moved,
                                    reason: dupReason,
                                    matchedRuleName: nil,
                                    originHost: originHost
                                ))
                            } catch {
                                rows.append(SortBatchEntry(
                                    id: UUID(),
                                    sourcePath: standardized.path,
                                    destinationPath: nil,
                                    category: .duplicates,
                                    disposition: .skippedError,
                                    reason: error.localizedDescription,
                                    matchedRuleName: nil,
                                    originHost: originHost
                                ))
                            }
                        }
                        await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                        return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
                    }
                    pendingFileDigest = (digestTry.sha256, digestTry.perceptual, digestTry.isImage)
                } catch {
                    pendingFileDigest = nil
                }
            }

            let taxonomyCategory = FileClassification.categorize(url: standardized)
            let ext = signals.ext
            let isImageFile = isRasterImageExtensionForSort(ext)
            let needsInspection =
                (snapshot.sortDetectReceiptsEnabled && (ext == "pdf" || isImageFile))
                || SortRulesEvaluator.anyRuleRequiresContentInspection(activeRules)
                || (snapshot.sortSmartScreenshotNamesEnabled && taxonomyCategory == .screenshots && isImageFile)

            let inspection: ContentInspector.ContentInspectionResult = if needsInspection {
                await ContentInspector.inspect(
                    for: standardized,
                    signals: signals,
                    snapshot: snapshot,
                    contentIdentitySHA256: pendingFileDigest?.sha256
                )
            } else {
                ContentInspector.emptyInspection
            }

            let contentInput = SortRulesEvaluator.ContentRuleMatchInput(
                hasSignificantOCR: inspection.hasSignificantOCR,
                isReceiptLike: inspection.isReceiptLike
            )
            let matchedRule = SortRulesEvaluator.firstMatchingRule(in: activeRules, signals: signals, content: contentInput, fileTags: fileTags)

            if let rule = matchedRule, rule.matchAction == .moveToTrash {
                emitFileStarted(categoryForAnimation: .misc)
                let trashReason = String.localizedStringWithFormat(
                    String(localized: "Trashed (rule “%@”).", comment: "Sort log when rule sends file to Trash."),
                    rule.name
                )
                do {
                    try fm.trashItem(at: standardized, resultingItemURL: nil)
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: nil,
                        category: .misc,
                        disposition: .moved,
                        reason: trashReason,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                } catch {
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: nil,
                        category: .misc,
                        disposition: .skippedError,
                        reason: error.localizedDescription,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                }
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            if let rule = matchedRule, rule.matchAction == .extractAndTrash {
                emitFileStarted(categoryForAnimation: .archives)
                let category = SortRulesEvaluator.customRuleTagCategory
                let destinationDir = SortRulesEvaluator.destinationDirectory(rule: rule, category: category, inboxRoot: inboxRoot)
                let extractReason = String.localizedStringWithFormat(
                    String(localized: "Extracted archive (rule “%@”).", comment: "Sort log extract rule."),
                    rule.name
                )
                do {
                    _ = try destGate.sync(directory: destinationDir) {
                        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                    }
                    try ArchiveExtractionService.extract(source: standardized, destinationDirectory: destinationDir)
                    try fm.trashItem(at: standardized, resultingItemURL: nil)
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: destinationDir.path,
                        category: category,
                        disposition: .moved,
                        reason: extractReason,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                } catch {
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: nil,
                        category: category,
                        disposition: .skippedError,
                        reason: error.localizedDescription,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                }
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            if let rule = matchedRule, rule.matchAction == .installFromDMG {
                emitFileStarted(categoryForAnimation: .apps)
                let category = FileSortCategory.apps
                let appsDest: URL = {
                    if let p = presets.first {
                        return p.resolvedApplicationsInstallDirectory()
                    }
                    return FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Applications", isDirectory: true)
                        .standardizedFileURL
                }()
                let installReason = String.localizedStringWithFormat(
                    String(localized: "Installed from disk image (rule “%@”).", comment: "Sort log DMG install."),
                    rule.name
                )
                do {
                    let installed = try DMGInstallerService.installApps(fromDmg: standardized, applicationsDestination: appsDest)
                    try fm.trashItem(at: standardized, resultingItemURL: nil)
                    let destPath = installed.first?.path ?? appsDest.path
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: destPath,
                        category: category,
                        disposition: .moved,
                        reason: installReason,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                } catch {
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: nil,
                        category: category,
                        disposition: .skippedError,
                        reason: error.localizedDescription,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                }
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            let useReceiptAutoRoute =
                matchedRule == nil
                && snapshot.sortDetectReceiptsEnabled
                && inspection.isReceiptLike
                && (ext == "pdf" || isImageFile)

            let category: FileSortCategory
            let destinationDir: URL
            var preferredFilename: String
            let ruleName: String?
            let naturalCategoryForTags: FileSortCategory
            let dominantOCRSlug: String? = inspection.dominantOCRLine.flatMap {
                let s = SortRulesEvaluator.slugifyForRenameToken(from: $0, maxLen: 60)
                return s.isEmpty ? nil : s
            }

            if let rule = matchedRule, rule.matchAction != .moveToTrash {
                category = SortRulesEvaluator.customRuleTagCategory
                if rule.matchAction == .renameInPlace {
                    destinationDir = standardized.deletingLastPathComponent().standardizedFileURL
                } else if rule.matchAction == .tagFanout {
                    destinationDir = SortRulesEvaluator.tagFanoutDestinationDirectory(
                        rule: rule,
                        inboxRoot: inboxRoot,
                        fileTags: fileTags,
                        priority: combinedTagFanoutPriority(presets: presets)
                    )
                } else {
                    destinationDir = SortRulesEvaluator.destinationDirectory(rule: rule, category: category, inboxRoot: inboxRoot)
                }
                let rc = await renameCounter.nextValue(forRenameStyle: rule.renameStyle)
                preferredFilename = SortRulesEvaluator.renamedFilename(
                    originalURL: standardized,
                    rule: rule,
                    renameCounter: rc,
                    originHost: originHost,
                    ocrSlug: dominantOCRSlug,
                    vendorSlug: inspection.vendorSlug,
                    amountSlug: inspection.amountSlug
                )
                ruleName = rule.name
                naturalCategoryForTags = taxonomyCategory
            } else if useReceiptAutoRoute {
                category = .receipts
                let vendorFolder = inspection.vendorSlug ?? "Receipt"
                destinationDir = StarterDestinations.directory(for: .receipts, root: inboxRoot)
                    .appendingPathComponent(vendorFolder, isDirectory: true)
                let df = ISO8601DateFormatter()
                df.formatOptions = [.withFullDate]
                let dateStr = df.string(from: Date())
                let amt = inspection.amountSlug ?? "0.00"
                preferredFilename = "\(vendorFolder) — \(dateStr) — \(amt).\(ext)"
                ruleName = nil
                naturalCategoryForTags = .receipts
            } else {
                category = taxonomyCategory
                destinationDir = StarterDestinations.directory(for: category, root: inboxRoot)
                preferredFilename = standardized.lastPathComponent
                if category == .screenshots, snapshot.sortSmartScreenshotNamesEnabled, isImageFile,
                   let smart = await ContentInspector.preferredSmartScreenshotName(
                    fileURL: standardized,
                    naturalCategory: category,
                    snapshot: snapshot,
                    signals: signals,
                    contentIdentitySHA256: pendingFileDigest?.sha256
                   ) {
                    preferredFilename = smart
                }
                ruleName = nil
                naturalCategoryForTags = taxonomyCategory
            }

            emitFileStarted(categoryForAnimation: category)

            if standardized.deletingLastPathComponent().standardizedFileURL == destinationDir.standardizedFileURL,
               standardized.lastPathComponent == preferredFilename {
                rows.append(SortBatchEntry(
                    id: UUID(), sourcePath: standardized.path, destinationPath: standardized.path, category: category, disposition: .kept,
                    reason: String(localized: "Already sorted into this destination.", comment: "Sort log."),
                    matchedRuleName: ruleName,
                    originHost: originHost
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            if let rule = matchedRule, rule.matchAction == .zipToDestination {
                let zipStem = standardized.deletingPathExtension().lastPathComponent
                let zipPreferred = "\(zipStem).zip"
                let zipReason = String.localizedStringWithFormat(
                    String(localized: "Zipped into “%1$@” (rule “%2$@”).", comment: "Sort log zip rule."),
                    destinationDisplayLabelForSort(root: inboxRoot, destinationDir: destinationDir),
                    rule.name
                )
                do {
                    let zipURL: URL = try destGate.sync(directory: destinationDir) {
                        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                        return DownloadsSortOrchestrator.uniquify(destinationDirectory: destinationDir, preferredFilename: zipPreferred)
                    }
                    try SortZipViaDitto.zipReplacingSource(file: standardized, zipDestinationURL: zipURL)
                    if snapshot.assignFinderTagsOnSortEnabled {
                        let okTag = FinderTagApplicator.merge(
                            composedFinderTagsForSort(snapshot: snapshot, naturalCategory: naturalCategoryForTags, presets: presets, matchedRule: matchedRule),
                            onto: zipURL
                        )
                        if !okTag {
                            tagWriteFailures += 1
                        }
                    }
                    if snapshot.assignFinderTagsOnSortEnabled, snapshot.sortAppendNewSemanticTagEnabled,
                       newTagExpiryDays(from: presets) > 0 {
                        await MainActor.run {
                            NewTagExpiryService.shared.register(file: zipURL, expiryDays: newTagExpiryDays(from: presets))
                        }
                    }
                    let shortcut = postSortShortcutName(from: presets)
                    if !shortcut.isEmpty {
                        await MainActor.run {
                            PostSortShortcutRunner.run(shortcutName: shortcut, fileURL: zipURL)
                        }
                    }
                    if let digest = pendingFileDigest {
                        FileHashStore.shared.recordSortedFile(
                            url: zipURL,
                            sha256: digest.sha256,
                            byteSize: signals.byteSize,
                            perceptual: digest.perceptual,
                            isImage: digest.isImage
                        )
                    }
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: zipURL.path,
                        category: category,
                        disposition: .moved,
                        reason: zipReason,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                } catch {
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: nil,
                        category: category,
                        disposition: .skippedError,
                        reason: error.localizedDescription,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                }
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            let target: URL
            do {
                target = try destGate.sync(directory: destinationDir) {
                    try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                    return DownloadsSortOrchestrator.uniquify(destinationDirectory: destinationDir, preferredFilename: preferredFilename)
                }
            } catch {
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: category,
                    disposition: .skippedError,
                    reason: error.localizedDescription,
                    matchedRuleName: ruleName,
                    originHost: originHost
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            do {
                try fm.moveItem(at: standardized, to: target)

                if snapshot.assignFinderTagsOnSortEnabled {
                    let okTag = FinderTagApplicator.merge(
                        composedFinderTagsForSort(snapshot: snapshot, naturalCategory: naturalCategoryForTags, presets: presets, matchedRule: matchedRule),
                        onto: target
                    )
                    if !okTag {
                        tagWriteFailures += 1
                    }
                }

                if snapshot.assignFinderTagsOnSortEnabled, snapshot.sortAppendNewSemanticTagEnabled,
                   newTagExpiryDays(from: presets) > 0 {
                    await MainActor.run {
                        NewTagExpiryService.shared.register(file: target, expiryDays: newTagExpiryDays(from: presets))
                    }
                }

                let shortcut = postSortShortcutName(from: presets)
                if !shortcut.isEmpty {
                    await MainActor.run {
                        PostSortShortcutRunner.run(shortcutName: shortcut, fileURL: target)
                    }
                }

                if let digest = pendingFileDigest {
                    FileHashStore.shared.recordSortedFile(
                        url: target,
                        sha256: digest.sha256,
                        byteSize: signals.byteSize,
                        perceptual: digest.perceptual,
                        isImage: digest.isImage
                    )
                }

                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: target.path,
                    category: category,
                    disposition: .moved,
                    reason: localizedMoveReasonForSort(matchedRuleName: ruleName, destinationDir: destinationDir, inboxRoot: inboxRoot),
                    matchedRuleName: ruleName,
                    originHost: originHost
                ))

            } catch {
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: category,
                    disposition: .skippedError,
                    reason: error.localizedDescription,
                    matchedRuleName: ruleName,
                    originHost: originHost
                ))
            }

            await applyEnergyThrottleBetweenFiles(batchSize: batchSize)
            return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
        }

        var mergedRows: [SortBatchEntry] = []
        var mergedTagFails = 0
        let n = batchSize
        var slots: [SortIndexedFileResult?] = Array(repeating: nil, count: n)
        // 700ms reads as deliberate without feeling sluggish. Synced with `progress?(.fileStarted)`
        // animations so each file's bucket icon has time to flash.
        let slowModeNanos: UInt64 = 700_000_000
        await withTaskGroup(of: (Int, SortIndexedFileResult).self) { group in
            var nextIndex = 0
            for _ in 0..<min(maxConcurrent, n) {
                let idx = nextIndex
                nextIndex += 1
                let url = workURLs[idx]
                group.addTask {
                    let r = await runOne(url)
                    return (idx, r)
                }
            }
            for await (idx, res) in group {
                slots[idx] = res
                if snapshot.slowMode, nextIndex < n {
                    try? await Task.sleep(nanoseconds: slowModeNanos)
                    guard await gate.continueWhenSortPermitsProgress() else { continue }
                }
                if nextIndex < n {
                    let j = nextIndex
                    nextIndex += 1
                    let url = workURLs[j]
                    group.addTask {
                        let r = await runOne(url)
                        return (j, r)
                    }
                }
            }
        }
        for i in 0..<n {
            if let s = slots[i] {
                mergedRows.append(contentsOf: s.rows)
                mergedTagFails += s.tagWriteFailures
            }
        }
        return (mergedRows, mergedTagFails)
    }
}

// MARK: - Physical layout helpers

enum StarterDestinations {
    static func directory(for cat: FileSortCategory, root: URL) -> URL {
        root.appendingPathComponent(cat.downloadsSubfolder, isDirectory: true)
    }

    static func ensure(downloadsRoot root: URL) {
        let fm = FileManager.default
        FileSortCategory.allCases.forEach { cat in
            try? fm.createDirectory(at: directory(for: cat, root: root), withIntermediateDirectories: true)
        }
    }
}

// MARK: - Orchestrator

/// Summary of undoing a stored list of `(destination, source)` pairs (reverses sort moves).
struct UndoMovesSummary: Sendable {
    let attempted: Int
    let failures: Int
}

@MainActor
final class DownloadsSortOrchestrator {
    private enum SortControlState {
        case running
        case paused
        case stopRequested
    }

    static let shared = DownloadsSortOrchestrator()

    nonisolated static func uniquify(destinationDirectory folder: URL, preferredFilename name: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        let ext = URL(fileURLWithPath: name).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var n = 2
        repeat {
            let next = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            candidate = folder.appendingPathComponent(next)
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    /// `(destination,isOriginalSource)`
    private(set) var lastUndoPairs: [(URL, URL)] = []

    /// ID of the outcome from the last finished `sort` pass (for clearing pinned undo when the summary sheet undoes that same batch).
    private(set) var lastCompletedSortID: UUID?

    /// Only one sort pass at a time — concurrent entry points queue or no-op (see single-flight `sort`).
    private(set) var isSorting: Bool = false
    private var sortControlState: SortControlState = .running
    private var sortRunGate: SortRunGate?

    var canPause: Bool {
        isSorting && sortControlState == .running
    }

    var canResume: Bool {
        isSorting && sortControlState == .paused
    }

    var canStop: Bool {
        isSorting && sortControlState != .stopRequested
    }

    func pauseCurrentSort() {
        guard canPause else { return }
        sortControlState = .paused
        sortRunGate?.setPaused()
        SortProgressTracker.shared.setRunState(.paused)
    }

    func resumeCurrentSort() {
        guard canResume else { return }
        sortControlState = .running
        sortRunGate?.setRunning()
        SortProgressTracker.shared.setRunState(.running)
    }

    func stopCurrentSort() {
        guard canStop else { return }
        sortControlState = .stopRequested
        sortRunGate?.setStopRequested()
        SortProgressTracker.shared.setRunState(.stopping)
    }

    /// Empty outcome for early returns (no-op / busy); `hasWork == false`.
    private static func emptyOutcome() -> SortBatchOutcome {
        SortBatchOutcome(id: UUID(), started: Date(), elapsed: 0, entries: [])
    }

    /// Shows where files would land **without** waiting on stability or moving anything.
    /// `rootOverride` pins specific files to an ad-hoc inbox root (e.g. a right-clicked folder
    /// that should act as its own one-shot inbox). Keys are matched against each file's
    /// `standardizedFileURL`.
    func previewSort(files urls: [URL], prefs: BinkyPreferences, rootOverride: [URL: URL] = [:]) async -> [SortPreviewEntry] {
        prefs.reconcileFolderBookmarksIfNeeded()
        let fm = FileManager.default
        var renameCounter = 1
        var out: [SortPreviewEntry] = []

        for raw in urls {
            let standardized = raw.standardizedFileURL
            guard standardized.isFileURL else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir), !isDir.boolValue else { continue }

            if looksTransientIncomplete(standardized) {
                let sum = String(localized: "Skipped — looks like an incomplete download.", comment: "Sort preview row.")
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourceLastPathComponent: standardized.lastPathComponent,
                    proposedDestinationPath: "—",
                    summary: sum,
                    whyLine: String(localized: "Incomplete download — skipped for now.", comment: "Preview why: transient.")
                ))
                continue
            }

            if SortRulesEvaluator.isExcluded(url: standardized, prefs: prefs) {
                let sum = String(localized: "Excluded — matches your ignore list.", comment: "Sort preview row.")
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourceLastPathComponent: standardized.lastPathComponent,
                    proposedDestinationPath: "—",
                    summary: sum,
                    whyLine: String(localized: "On your ignore list.", comment: "Preview why: excluded.")
                ))
                continue
            }

            let snapshot = prefs.makeSortPreferencesSnapshot()

            if fileURLMatchesGlobalSkipTags(standardized, snapshot: snapshot) {
                let sum = String(localized: "Skipped — protected Finder tag.", comment: "Sort preview row.")
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourceLastPathComponent: standardized.lastPathComponent,
                    proposedDestinationPath: "—",
                    summary: sum,
                    whyLine: String(localized: "This file has a tag on your “never sort” list.", comment: "Preview why: skip tag.")
                ))
                continue
            }

            let signals = SortRulesEvaluator.loadSignals(url: standardized)
                ?? SortRulesEvaluator.FileSignals(
                    ext: standardized.pathExtension.lowercased(),
                    baseName: standardized.lastPathComponent,
                    byteSize: 0,
                    addedToDirectoryDate: nil,
                    creationDate: nil,
                    modificationDate: nil,
                    originHosts: WhereFromsReader.originHosts(forFileAt: standardized)
                )

            let fileTags = FinderTagApplicator.readTagNames(for: standardized)

            let (defaultRoot, presets) = sortInboxContext(for: standardized, snapshot: snapshot)
            let inboxRoot = rootOverride[standardized] ?? defaultRoot
            let activeRules = activeSortRulesForSnapshot(snapshot: snapshot, presets: presets)

            var pendingDigestSHA: String?
            if snapshot.sortDuplicateMode != .off {
                if let digestTry = try? FileHashStore.shared.digestFile(at: standardized) {
                    pendingDigestSHA = digestTry.sha256
                    let lookup = FileHashStore.shared.lookup(
                        sha256: digestTry.sha256,
                        perceptual: digestTry.perceptual,
                        isImage: digestTry.isImage
                    )
                    if lookup.isByteDuplicate || lookup.isNearImageDuplicate {
                        let destLabel: String
                        switch snapshot.sortDuplicateMode {
                        case .off:
                            destLabel = "—"
                        case .moveToTrash:
                            destLabel = String(localized: "Trash", comment: "Sort preview duplicate.")
                        case .moveToDuplicates:
                            destLabel = destinationDisplayLabelForSort(
                                root: inboxRoot,
                                destinationDir: StarterDestinations.directory(for: .duplicates, root: inboxRoot)
                            )
                        }
                        let sum = String(localized: "Duplicate — would skip per your settings.", comment: "Sort preview.")
                        out.append(SortPreviewEntry(
                            id: UUID(),
                            sourceLastPathComponent: standardized.lastPathComponent,
                            proposedDestinationPath: destLabel,
                            summary: sum,
                            whyLine: String(localized: "Already got one.", comment: "Preview why: duplicate.")
                        ))
                        continue
                    }
                }
            }

            let taxonomyCategory = FileClassification.categorize(url: standardized)
            let ext = signals.ext
            let isImageFile = isRasterImageExtensionForSort(ext)
            let needsInspection =
                (snapshot.sortDetectReceiptsEnabled && (ext == "pdf" || isImageFile))
                || SortRulesEvaluator.anyRuleRequiresContentInspection(activeRules)
                || (snapshot.sortSmartScreenshotNamesEnabled && taxonomyCategory == .screenshots && isImageFile)

            let inspection: ContentInspector.ContentInspectionResult
            if needsInspection {
                inspection = await ContentInspector.inspect(
                    for: standardized,
                    signals: signals,
                    snapshot: snapshot,
                    contentIdentitySHA256: pendingDigestSHA
                )
            } else {
                inspection = ContentInspector.emptyInspection
            }

            let contentInput = SortRulesEvaluator.ContentRuleMatchInput(
                hasSignificantOCR: inspection.hasSignificantOCR,
                isReceiptLike: inspection.isReceiptLike
            )
            let matchedRule = SortRulesEvaluator.firstMatchingRule(in: activeRules, signals: signals, content: contentInput, fileTags: fileTags)
            let originHost = signals.originHosts.first

            if let rule = matchedRule, rule.matchAction == .moveToTrash {
                let trashSummary = String.localizedStringWithFormat(
                    String(localized: "Rule “%@” → Trash", comment: "Sort preview row: rule sends file to Trash."),
                    rule.name
                )
                let whyTrash: String
                if rule.contentMatch.kind != .none {
                    whyTrash = String.localizedStringWithFormat(
                        String(localized: "Matched by content · rule “%@”.", comment: "Preview why: trash via content rule."),
                        rule.name
                    )
                } else if let host = originHost, !host.isEmpty, !rule.originDomains.isEmpty {
                    whyTrash = String.localizedStringWithFormat(
                        String(localized: "Rule “%1$@” · from %2$@.", comment: "Preview why: trash rule + origin."),
                        rule.name,
                        host
                    )
                } else {
                    whyTrash = String.localizedStringWithFormat(
                        String(localized: "Rule “%@”.", comment: "Preview why: named trash rule."),
                        rule.name
                    )
                }
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourceLastPathComponent: standardized.lastPathComponent,
                    proposedDestinationPath: String(localized: "Trash", comment: "Sort preview: destination is Trash."),
                    summary: trashSummary,
                    whyLine: whyTrash
                ))
                continue
            }

            let useReceiptAutoRoute =
                matchedRule == nil
                && snapshot.sortDetectReceiptsEnabled
                && inspection.isReceiptLike
                && (ext == "pdf" || isImageFile)

            let dominantOCRSlug: String? = inspection.dominantOCRLine.flatMap {
                let s = SortRulesEvaluator.slugifyForRenameToken(from: $0, maxLen: 60)
                return s.isEmpty ? nil : s
            }

            let category: FileSortCategory
            let destinationDir: URL
            var preferredFilename: String

            if let rule = matchedRule, rule.matchAction != .moveToTrash {
                category = SortRulesEvaluator.customRuleTagCategory
                if rule.matchAction == .renameInPlace {
                    destinationDir = standardized.deletingLastPathComponent().standardizedFileURL
                } else if rule.matchAction == .tagFanout {
                    destinationDir = SortRulesEvaluator.tagFanoutDestinationDirectory(
                        rule: rule,
                        inboxRoot: inboxRoot,
                        fileTags: fileTags,
                        priority: combinedTagFanoutPriority(presets: presets)
                    )
                } else {
                    destinationDir = SortRulesEvaluator.destinationDirectory(rule: rule, category: category, inboxRoot: inboxRoot)
                }
                preferredFilename = SortRulesEvaluator.renamedFilename(
                    originalURL: standardized,
                    rule: rule,
                    renameCounter: renameCounter,
                    originHost: originHost,
                    ocrSlug: dominantOCRSlug,
                    vendorSlug: inspection.vendorSlug,
                    amountSlug: inspection.amountSlug
                )
                if rule.renameStyle != .none { renameCounter += 1 }
            } else if useReceiptAutoRoute {
                category = .receipts
                let vendorFolder = inspection.vendorSlug ?? "Receipt"
                destinationDir = StarterDestinations.directory(for: .receipts, root: inboxRoot)
                    .appendingPathComponent(vendorFolder, isDirectory: true)
                let df = ISO8601DateFormatter()
                df.formatOptions = [.withFullDate]
                let dateStr = df.string(from: Date())
                let amt = inspection.amountSlug ?? "0.00"
                preferredFilename = "\(vendorFolder) — \(dateStr) — \(amt).\(ext)"
            } else {
                category = taxonomyCategory
                destinationDir = StarterDestinations.directory(for: category, root: inboxRoot)
                preferredFilename = standardized.lastPathComponent
                if category == .screenshots, snapshot.sortSmartScreenshotNamesEnabled, isImageFile,
                   let smart = await ContentInspector.preferredSmartScreenshotName(
                    fileURL: standardized,
                    naturalCategory: category,
                    snapshot: snapshot,
                    signals: signals,
                    contentIdentitySHA256: pendingDigestSHA
                   ) {
                    preferredFilename = smart
                }
            }

            if let rule = matchedRule, rule.matchAction == .zipToDestination {
                let zipStem = standardized.deletingPathExtension().lastPathComponent
                let zipPreferred = "\(zipStem).zip"
                let zipTarget = Self.uniquify(destinationDirectory: destinationDir, preferredFilename: zipPreferred)
                let label = destinationDisplayLabel(root: inboxRoot, destinationDir: destinationDir)
                let summary = String.localizedStringWithFormat(
                    String(localized: "Rule “%1$@” · zip → %2$@", comment: "Sort preview; zip rule."),
                    rule.name,
                    label
                )
                let whyLine: String
                if rule.contentMatch.kind != .none {
                    whyLine = String.localizedStringWithFormat(
                        String(localized: "Matched by content · sent by “%@”.", comment: "Preview why: content rule."),
                        rule.name
                    )
                } else if let host = originHost, !host.isEmpty, !rule.originDomains.isEmpty {
                    whyLine = String.localizedStringWithFormat(
                        String(localized: "Sent by “%1$@” · from %2$@.", comment: "Preview why: rule + origin."),
                        rule.name,
                        host
                    )
                } else {
                    whyLine = String.localizedStringWithFormat(
                        String(localized: "Sent by “%@”.", comment: "Preview why: named rule."),
                        rule.name
                    )
                }
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourceLastPathComponent: standardized.lastPathComponent,
                    proposedDestinationPath: zipTarget.path,
                    summary: summary,
                    whyLine: whyLine
                ))
                continue
            }

            if standardized.deletingLastPathComponent().standardizedFileURL == destinationDir.standardizedFileURL,
               standardized.lastPathComponent == preferredFilename {
                let sum = String(localized: "Already in place — no move.", comment: "Sort preview row.")
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourceLastPathComponent: standardized.lastPathComponent,
                    proposedDestinationPath: destinationDir.path,
                    summary: sum,
                    whyLine: String(localized: "Already in the right place.", comment: "Preview why: no move.")
                ))
                continue
            }

            let target = Self.uniquify(destinationDirectory: destinationDir, preferredFilename: preferredFilename)
            let label = destinationDisplayLabel(root: inboxRoot, destinationDir: destinationDir)
            let summary: String
            if let rule = matchedRule {
                if rule.matchAction == .renameInPlace {
                    summary = String.localizedStringWithFormat(
                        String(localized: "Rule “%1$@” · rename here → %2$@", comment: "Sort preview; rename-in-place rule."),
                        rule.name,
                        target.lastPathComponent
                    )
                } else {
                    summary = String.localizedStringWithFormat(
                        String(localized: "Rule “%1$@” → %2$@", comment: "Sort preview; rule name and destination."),
                        rule.name,
                        label
                    )
                }
            } else if useReceiptAutoRoute {
                summary = String.localizedStringWithFormat(
                    String(localized: "Receipt → %1$@", comment: "Sort preview; receipt destination."),
                    label
                )
            } else {
                summary = String.localizedStringWithFormat(
                    String(localized: "Automatic sort → %1$@", comment: "Sort preview; destination label."),
                    label
                )
            }

            let whyLine: String
            if let rule = matchedRule {
                if rule.contentMatch.kind != .none {
                    whyLine = String.localizedStringWithFormat(
                        String(localized: "Matched by content · sent by “%@”.", comment: "Preview why: content rule."),
                        rule.name
                    )
                } else if let host = originHost, !host.isEmpty, !rule.originDomains.isEmpty {
                    whyLine = String.localizedStringWithFormat(
                        String(localized: "Sent by “%1$@” · from %2$@.", comment: "Preview why: rule + origin."),
                        rule.name,
                        host
                    )
                } else {
                    whyLine = String.localizedStringWithFormat(
                        String(localized: "Sent by “%@”.", comment: "Preview why: named rule."),
                        rule.name
                    )
                }
            } else if useReceiptAutoRoute {
                whyLine = String(localized: "Looks like a receipt.", comment: "Preview why: receipt heuristic.")
            } else if let host = originHost, !host.isEmpty {
                whyLine = String.localizedStringWithFormat(
                    String(localized: "By file type · from %@.", comment: "Preview why: taxonomy + host."),
                    host
                )
            } else {
                whyLine = String(localized: "By file type.", comment: "Preview why: taxonomy only.")
            }

            out.append(SortPreviewEntry(
                id: UUID(),
                sourceLastPathComponent: standardized.lastPathComponent,
                proposedDestinationPath: target.path,
                summary: summary,
                whyLine: whyLine
            ))
        }

        return out
    }

    /// Files directly under `root`, plus regular files one level inside immediate subfolders when `recursiveOneLevel` is true.
    nonisolated static func collectSweepFiles(in root: URL, recursiveOneLevel: Bool, fileManager fm: FileManager = .default) -> [URL] {
        guard let urls = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [URL] = []
        for url in urls {
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if vals?.isDirectory != true {
                files.append(url.standardizedFileURL)
                continue
            }
            guard recursiveOneLevel else { continue }
            guard let inner = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for u in inner {
                if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
                    files.append(u.standardizedFileURL)
                }
            }
        }
        return files
    }

    /// Top-level files in each active inbox folder (global watch root + unique preset watch roots).
    static func topLevelInboxFiles(prefs: BinkyPreferences) -> [URL] {
        prefs.reconcileFolderBookmarksIfNeeded()
        let fm = FileManager.default
        let recursive = prefs.watchRecursiveOneLevel
        var rootPaths: Set<String> = []
        rootPaths.insert(prefs.downloadsSortRootDirectory().path)

        let reg = WatchPipelineRegistry(prefs: prefs)
        for (_, path) in reg.presetPaths {
            let normalized = WatchFolderPathResolver.normalizedPath(path)
            guard !normalized.isEmpty else { continue }
            rootPaths.insert(normalized)
        }

        var collected: [URL] = []
        for path in rootPaths {
            let root = URL(fileURLWithPath: path)
            collected.append(contentsOf: collectSweepFiles(in: root, recursiveOneLevel: recursive, fileManager: fm))
        }
        return collected
    }

    func previewInbox(prefs: BinkyPreferences) async -> [SortPreviewEntry] {
        await previewSort(files: Self.topLevelInboxFiles(prefs: prefs), prefs: prefs)
    }

    /// Matches the guards at the beginning of ``sort``: only regular files that exist.
    private func urlsEligibleForSortPass(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var ordered: [URL] = []
        for raw in urls {
            let standardized = raw.standardizedFileURL
            guard standardized.isFileURL else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            ordered.append(standardized)
        }
        return ordered
    }

    /// `rootOverride` pins specific files to an ad-hoc inbox root (e.g. a right-clicked folder
    /// in Finder Services that should act as its own one-shot inbox). Keys are matched against
    /// each file's `standardizedFileURL`.
    func sort(
        files urls: [URL],
        prefs: BinkyPreferences,
        rootOverride: [URL: URL] = [:],
        progress: (@Sendable (SortProgressEvent) -> Void)? = nil
    ) async -> SortBatchOutcome {
        guard !isSorting else {
            NotificationCenter.default.post(name: .binkySortRejectedBecauseBusy, object: nil)
            return Self.emptyOutcome()
        }

        isSorting = true
        sortControlState = .running
        SortProgressTracker.shared.setRunState(.running)

        let gate = SortRunGate()
        sortRunGate = gate

        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: String(localized: "Binky is sorting files.", comment: "Process activity reason while sorting watched-folder files.")
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            sortRunGate?.endSession()
            sortRunGate = nil
            isSorting = false
            sortControlState = .running
        }

        let startedAt = Date()
        prefs.reconcileFolderBookmarksIfNeeded()
        let snapshot = prefs.makeSortPreferencesSnapshot()

        let normalizedOverride: [URL: URL] = Dictionary(
            rootOverride.map { ($0.key.standardizedFileURL, $0.value.standardizedFileURL) },
            uniquingKeysWith: { first, _ in first }
        )

        let uniqueRoots = Set(urls.map { url -> URL in
            let std = url.standardizedFileURL
            return normalizedOverride[std] ?? prefs.sortContext(for: std).inboxRoot
        })
        for root in uniqueRoots {
            StarterDestinations.ensure(downloadsRoot: root)
        }

        let workURLs = urlsEligibleForSortPass(urls)
        progress?(.batchStarted(total: workURLs.count))
        defer {
            progress?(.batchEnded)
        }

        let loopResult = await Task.detached(priority: .utility) { [workURLs, snapshot, normalizedOverride, gate, progress] in
            await SortWork.runSortWorkLoop(
                workURLs: workURLs,
                snapshot: snapshot,
                rootOverride: normalizedOverride,
                gate: gate,
                progress: progress
            )
        }.value

        let rows = loopResult.rows
        let tagWriteFailures = loopResult.tagWriteFailures

        let elapsed = Date().timeIntervalSince(startedAt)
        lastUndoPairs = rows
            .filter { $0.disposition == .moved }
            .compactMap { row in
                guard let dst = row.destinationPath else { return nil }
                return (URL(fileURLWithPath: dst), URL(fileURLWithPath: row.sourcePath))
            }

        var warnings: [String] = []
        if tagWriteFailures > 0 {
            let msg =
                tagWriteFailures == 1
                ? String(localized: "Finder tags didn’t stick for one file — the sort still landed.", comment: "Sort ancillary warning; single-file tag failure.")
                : String(
                    localized: "Finder tags didn’t stick for \(tagWriteFailures) files — the sort still landed.",
                    comment: "Sort ancillary warning; multiple tag failures. Argument is integer count."
                )
            warnings.append(msg)
        }

        let outcome = SortBatchOutcome(id: UUID(), started: startedAt, elapsed: elapsed, entries: rows, ancillaryWarnings: warnings)
        lastCompletedSortID = outcome.id
        prefs.appendSortOutcomeRecord(outcome)
        return outcome
    }

    private func destinationDisplayLabel(root: URL, destinationDir: URL) -> String {
        let rootPath = root.path
        let destPath = destinationDir.path
        guard destPath.hasPrefix(rootPath) else { return destinationDir.lastPathComponent }
        let tail = String(destPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return tail.isEmpty ? destinationDir.lastPathComponent : tail
    }

    /// Reverses the given move pairs: pulls each file back from `destination` to `source`.
    func undoMovesReversingSort(_ pairs: [(destination: URL, source: URL)], clearPinnedUndoIfOutcomeID outcomeID: UUID?) async -> UndoMovesSummary {
        let fm = FileManager.default
        var failures = 0
        let attempted = pairs.count
        for pair in pairs.reversed() {
            guard fm.fileExists(atPath: pair.destination.path) else {
                failures += 1
                continue
            }
            do {
                try fm.moveItem(at: pair.destination, to: pair.source)
            } catch {
                failures += 1
            }
        }
        if let outcomeID, outcomeID == lastCompletedSortID, failures == 0, attempted > 0 {
            lastUndoPairs = []
        }
        return UndoMovesSummary(attempted: attempted, failures: failures)
    }

    /// Undoes the orchestrator’s pinned “last batch” pairs (same as the most recent successful sort).
    func undoMostRecentPinnedBatchMoves() async -> UndoMovesSummary {
        let mapped = lastUndoPairs.map { (destination: $0.0, source: $0.1) }
        let summary = await undoMovesReversingSort(mapped, clearPinnedUndoIfOutcomeID: nil)
        lastUndoPairs = []
        return summary
    }
}

// MARK: - Preview (dry run)

/// One row for **Preview sort** — no files are moved.
struct SortPreviewEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceLastPathComponent: String
    let proposedDestinationPath: String
    let summary: String
    /// Plain-language “why” for the row (see VOICE.md).
    let whyLine: String
}

// MARK: — Trust-focused sheet

struct SortOutcomeSheet: View {

    let outcome: SortBatchOutcome
    var onRevealDestination: (SortBatchEntry) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onDismiss: () -> Void = {}
    /// Feedback for transient organizer banner (partial undo / Dinky handoff).
    var onTransientStatus: ((String) -> Void)?

    init(
        outcome: SortBatchOutcome,
        onRevealDestination: @escaping (SortBatchEntry) -> Void = { _ in },
        onUndo: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        onTransientStatus: ((String) -> Void)? = nil
    ) {
        self.outcome = outcome
        self.onRevealDestination = onRevealDestination
        self.onUndo = onUndo
        self.onDismiss = onDismiss
        self.onTransientStatus = onTransientStatus
    }

    @EnvironmentObject private var prefs: BinkyPreferences
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sortProgress = SortProgressTracker.shared
    @State private var undoFootnote: String?

    private var titleString: String {
        if let preset = outcome.matchedAutomation(in: prefs.savedPresets) {
            return String.localizedStringWithFormat(
                String(localized: "Sorted “%@”", comment: "Sort summary title; arg is automation name."),
                preset.name
            )
        }
        return String(localized: "Move / review summary", comment: "Automated sort audit title; fallback when no automation matches.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(titleString)
                .font(.title2)

            HStack(spacing: 12) {
                statChip(title: String(localized: "Moved", comment: "Sort audit"), value: outcome.movedCount, systemImage: "folder")
                statChip(title: String(localized: "Kept", comment: "Sort audit"), value: outcome.keptCount, systemImage: "checkmark.circle")
                statChip(title: String(localized: "Skipped", comment: "Sort audit"), value: outcome.skippedCount, systemImage: "minus.circle")
                statChip(title: String(localized: "Review folder", comment: "Sort audit queue"), value: outcome.reviewQueuedCount, systemImage: "questionmark.circle")
            }

            ForEach(Array(outcome.ancillaryWarnings.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(outcome.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: entry.sourcePath).lastPathComponent)
                                .font(.headline)
                            Text(entry.userFacingWhyDescription())
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let dest = entry.destinationPath {
                                Button(String(localized: "Reveal in Finder", comment: "Sort audit")) {
                                    NSWorkspace.shared.selectFile(dest, inFileViewerRootedAtPath: URL(fileURLWithPath: dest).deletingLastPathComponent().path)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 320)

            dinkySection

            HStack {
                Button(role: .cancel, action: { onDismiss(); dismiss() }) {
                    Text(String(localized: "Close", comment: "Sort audit sheet dismiss."))
                }
                Button(String(localized: "Undo moves", comment: "Sort audit")) {
                    undoFootnote = nil
                    Task {
                        let summary = await DownloadsSortOrchestrator.shared.undoMovesReversingSort(
                            outcome.reversibleMoves,
                            clearPinnedUndoIfOutcomeID: outcome.id
                        )
                        if summary.failures > 0 {
                            undoFootnote = String(
                                localized: "\(summary.failures) of \(summary.attempted) moves couldn’t be undone — files may have moved or been renamed.",
                                comment: "Sort sheet undo partial failure footer. Arguments are counts."
                            )
                        } else if summary.attempted > 0 {
                            onUndo()
                            dismiss()
                            onDismiss()
                        }
                    }
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(outcome.reversibleMoves.isEmpty || sortProgress.isActive)
                Spacer()
            }

            if let undoFootnote {
                Text(undoFootnote)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(String(localized: "Undo moves puts files back where they were before this sort.", comment: "Sort sheet footer."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 520)
    }

    @ViewBuilder
    private var dinkySection: some View {
        let movedURLs: [URL] = outcome.entries.compactMap { e in
            guard e.disposition == .moved, let d = e.destinationPath else { return nil }
            return URL(fileURLWithPath: d)
        }
        let compressible = DinkyBridge.compressibleURLs(from: movedURLs)
        if compressible.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text(String(localized: "Dinky", comment: "Sort sheet: Dinky handoff section title."))
                    .font(.subheadline.weight(.semibold))
                if DinkyBridge.isInstalled {
                    Button(String.localizedStringWithFormat(String(localized: "Send %lld files to Dinky", comment: "Sort sheet: handoff button; file count."), Int64(compressible.count))) {
                        let msg = String(localized: "Dinky couldn’t open these — try installing or reopening it.", comment: "Organizer transient when Dinky app handoff fails.")
                        _ = DinkyBridge.openFiles(compressible) { ok in
                            guard !ok else { return }
                            Task { @MainActor in onTransientStatus?(msg) }
                        }
                    }
                    let folders = DinkyBridge.uniqueFolders(containing: compressible)
                    ForEach(folders, id: \.path) { folder in
                        Button {
                            let msg = String(localized: "Couldn’t open that folder in Dinky.", comment: "Organizer transient when Dinky folder handoff fails.")
                            _ = DinkyBridge.openFolder(folder) { ok in
                                guard !ok else { return }
                                Task { @MainActor in onTransientStatus?(msg) }
                            }
                        } label: {
                            Text(String.localizedStringWithFormat(String(localized: "Watch “%@” in Dinky →", comment: "Sort sheet: watch chain; folder name."), folder.lastPathComponent))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(binkyTintColor)
                    }
                } else {
                    Link(String(localized: "Compress these with Dinky ↗", comment: "Sort sheet: marketing link when Dinky not installed."), destination: DinkyBridge.marketingURL)
                        .font(.caption)
                }
            }
        }
    }

    private func statChip(title: String, value: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.monospacedDigit())
                .bold()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.35)))
    }
}

// MARK: - Watch folder coordinator (runs without main window)

/// Keeps Downloads watch-folder FSEvents and sorting alive even when the main window is closed.
@MainActor
final class WatchSortCoordinator {
    private let prefs: BinkyPreferences
    private let viewModel: OrganizerViewModel
    private let watcher = FolderWatcher()
    private var subscriptions = Set<AnyCancellable>()

    private var ingestTask: Task<Void, Never>?
    private var queuedIncoming: Set<URL> = []
    /// First arrival in the current debounce burst (for max-wait ceiling).
    private var debounceBurstStart: Date?
    /// Last time new paths were merged into ``queuedIncoming``.
    private var lastIncomingArrival: Date?
    private var rulesResortTask: Task<Void, Never>?

    init(prefs: BinkyPreferences, viewModel: OrganizerViewModel) {
        self.prefs = prefs
        self.viewModel = viewModel

        watcher.onNewFiles = { [weak self] incoming in
            self?.enqueueIncomingForDebouncedSort(incoming)
        }

        restartWatcherIfNeeded()

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                prefs.reconcileFolderBookmarksIfNeeded()
                restartWatcherIfNeeded()
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(140), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.restartWatcherIfNeeded() }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .binkyFolderWatchPauseChanged)
            .sink { [weak self] _ in self?.restartWatcherIfNeeded() }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .binkyRoutingRulesDidChange)
            .sink { [weak self] _ in self?.scheduleResortAfterRulesChanged() }
            .store(in: &subscriptions)
    }

    func restartWatcherIfNeeded() {
        prefs.reconcileFolderBookmarksIfNeeded()

        guard !prefs.folderWatchPaused else {
            watcher.stop()
            return
        }

        let registry = WatchPipelineRegistry(prefs: prefs)
        let paths = registry.watchedRootPaths
        guard !paths.isEmpty else {
            watcher.stop()
            return
        }
        watcher.start(paths: paths)
    }

    private func enqueueIncomingForDebouncedSort(_ incoming: [URL]) {
        let dedup = incoming.map(\.standardizedFileURL).filter(\.isFileURL)
        guard !dedup.isEmpty else { return }
        let now = Date()
        if debounceBurstStart == nil { debounceBurstStart = now }
        lastIncomingArrival = now
        queuedIncoming.formUnion(dedup)
        ingestTask?.cancel()
        ingestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while DownloadsSortOrchestrator.shared.isSorting {
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { return }
            }

            let debounceQuiet: TimeInterval = 0.8
            let burstCeiling: TimeInterval = 1.5

            while !Task.isCancelled {
                let nowTick = Date()
                guard let last = self.lastIncomingArrival, let burstStart = self.debounceBurstStart else { break }
                let quietDeadline = last.addingTimeInterval(debounceQuiet)
                let capDeadline = burstStart.addingTimeInterval(burstCeiling)
                let fireDate = min(quietDeadline, capDeadline)
                if nowTick >= fireDate { break }
                let waitSec = fireDate.timeIntervalSince(nowTick)
                let ns = UInt64(min(max(waitSec, 0.02), 1.0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
            if Task.isCancelled { return }

            let batch = Array(self.queuedIncoming)
            self.queuedIncoming.removeAll()
            self.debounceBurstStart = nil
            self.lastIncomingArrival = nil
            guard !batch.isEmpty else { return }
            while EnergyConditions.shared.shouldPauseFully {
                if Task.isCancelled {
                    self.queuedIncoming.formUnion(batch)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else {
                self.queuedIncoming.formUnion(batch)
                return
            }
            let outcome = await DownloadsSortOrchestrator.shared.sort(
                files: batch,
                prefs: prefs,
                progress: SortProgressTracker.orchestratorClosure()
            )
            guard outcome.hasWork else { return }
            viewModel.deliverCompletedSort(outcome, prefs: prefs)
        }
    }

    /// After routing rules change, optionally re-run sort across all watched inbox roots (Hazel-style).
    private func scheduleResortAfterRulesChanged() {
        guard prefs.sortAutoRunWhenRulesChange else { return }
        rulesResortTask?.cancel()
        rulesResortTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self.performResortAcrossWatchedInboxesAfterRulesChanged()
        }
    }

    private func performResortAcrossWatchedInboxesAfterRulesChanged() async {
        guard prefs.sortAutoRunWhenRulesChange else { return }
        guard prefs.folderWatchEnabled, !prefs.folderWatchPaused else { return }
        prefs.reconcileFolderBookmarksIfNeeded()

        while DownloadsSortOrchestrator.shared.isSorting {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard !Task.isCancelled else { return }

        let files = DownloadsSortOrchestrator.topLevelInboxFiles(prefs: prefs)
        guard !files.isEmpty else { return }

        let outcome = await DownloadsSortOrchestrator.shared.sort(
            files: files,
            prefs: prefs,
            progress: SortProgressTracker.orchestratorClosure()
        )
        guard outcome.hasWork else { return }
        viewModel.deliverCompletedSort(outcome, prefs: prefs)
    }
}