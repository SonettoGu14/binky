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

private func activeSortRulesForSort(prefs: BinkyPreferences, preset: CompressionPreset?) -> [InboxSortRule] {
    if let preset, !preset.inboxSortRules.isEmpty {
        return preset.inboxSortRules
    }
    return prefs.sortCustomRulesEnabled ? prefs.sortRoutingRules : []
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
    let sortRoutingRules: [InboxSortRule]
    let sortAppendNewSemanticTagEnabled: Bool
    let assignFinderTagsOnSortEnabled: Bool
    let finderTagDefaultsByCategory: [String: [String]]
    let globalInboxRoot: URL
    let watchRegistry: WatchPipelineRegistry
    let presetsByID: [UUID: CompressionPreset]
    let sortDuplicateMode: SortDuplicateHandlingMode
    let sortSmartScreenshotNamesEnabled: Bool
    let sortDetectReceiptsEnabled: Bool
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
            sortDetectReceiptsEnabled: sortDetectReceiptsEnabled
        )
    }
}

private func sortInboxContext(for fileURL: URL, snapshot: SortPreferencesSnapshot) -> (inboxRoot: URL, preset: CompressionPreset?) {
    let reg = snapshot.watchRegistry
    switch reg.pipeline(for: fileURL) {
    case .global:
        return (snapshot.globalInboxRoot, nil)
    case .preset(let id):
        guard let preset = snapshot.presetsByID[id] else {
            return (snapshot.globalInboxRoot, nil)
        }
        if preset.watchFolderModeRaw == "unique",
           let path = WatchFolderPathResolver.resolvedWatchDirectoryPath(
                bookmark: preset.watchFolderBookmark,
                storedPath: preset.watchFolderPath
           ) {
            return (URL(fileURLWithPath: path).standardizedFileURL, preset)
        }
        return (snapshot.globalInboxRoot, preset)
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

private func activeSortRulesForSnapshot(snapshot: SortPreferencesSnapshot, preset: CompressionPreset?) -> [InboxSortRule] {
    if let preset, !preset.inboxSortRules.isEmpty {
        return preset.inboxSortRules
    }
    return snapshot.sortCustomRulesEnabled ? snapshot.sortRoutingRules : []
}

private func composedFinderTagsForSort(
    snapshot: SortPreferencesSnapshot,
    naturalCategory: FileSortCategory,
    preset: CompressionPreset?,
    matchedRule: InboxSortRule?
) -> [String] {
    FinderTagComposer.compose(
        naturalCategory: naturalCategory,
        globalDefaults: snapshot.finderTagDefaultsByCategory,
        preset: preset,
        matchedRule: matchedRule,
        appendNewSemanticTag: snapshot.sortAppendNewSemanticTagEnabled
    )
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

private enum SortWork {
    nonisolated static func applyEnergyThrottleBetweenFiles(batchSize: Int) async {
        await Task.yield()
        guard EnergyConditions.shared.shouldPauseFully else {
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
        let fm = FileManager.default
        var rows: [SortBatchEntry] = []
        var renameCounter = 1
        var tagWriteFailures = 0

        for standardized in workURLs {
            guard await gate.continueWhenSortPermitsProgress() else { break }
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
                await applyEnergyThrottleBetweenFiles(batchSize: workURLs.count)
                continue
            }

            guard await waitUntilStable(at: standardized, continueCheck: {
                await gate.continueWhenSortPermitsProgress()
            }) else {
                if gate.stopRequested() {
                    break
                }
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                emitFileStarted(categoryForAnimation: .review)
                rows.append(SortBatchEntry(
                    id: UUID(), sourcePath: standardized.path, destinationPath: nil, category: .review, disposition: .skippedStableCheckTimeout,
                    reason: String(localized: "File never stabilized before timeout.", comment: "Sort log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: workURLs.count)
                continue
            }

            guard await gate.continueWhenSortPermitsProgress() else { break }

            if isURLExcludedForSort(url: standardized, snapshot: snapshot) {
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                emitFileStarted(categoryForAnimation: .misc)
                rows.append(SortBatchEntry(
                    id: UUID(), sourcePath: standardized.path, destinationPath: nil, category: .misc, disposition: .skippedExcluded,
                    reason: String(localized: "Skipped — file matches your ignore list.", comment: "Sort log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: workURLs.count)
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

            let originHost = signals.originHosts.first

            let (defaultRoot, preset) = sortInboxContext(for: standardized, snapshot: snapshot)
            let inboxRoot = rootOverride[standardized] ?? defaultRoot
            let activeRules = activeSortRulesForSnapshot(snapshot: snapshot, preset: preset)

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
                            let dest = DownloadsSortOrchestrator.uniquify(
                                destinationDirectory: dupDir,
                                preferredFilename: standardized.lastPathComponent
                            )
                            do {
                                try fm.createDirectory(at: dupDir, withIntermediateDirectories: true)
                                try fm.moveItem(at: standardized, to: dest)
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
                        await applyEnergyThrottleBetweenFiles(batchSize: workURLs.count)
                        continue
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
                await ContentInspector.inspect(for: standardized, signals: signals, snapshot: snapshot)
            } else {
                ContentInspector.emptyInspection
            }

            let contentInput = SortRulesEvaluator.ContentRuleMatchInput(
                hasSignificantOCR: inspection.hasSignificantOCR,
                isReceiptLike: inspection.isReceiptLike
            )
            let matchedRule = SortRulesEvaluator.firstMatchingRule(in: activeRules, signals: signals, content: contentInput)
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

            if let rule = matchedRule {
                category = SortRulesEvaluator.customRuleTagCategory
                destinationDir = SortRulesEvaluator.destinationDirectory(rule: rule, category: category, inboxRoot: inboxRoot)
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
                    snapshot: snapshot
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
                await applyEnergyThrottleBetweenFiles(batchSize: workURLs.count)
                continue
            }

            let target = DownloadsSortOrchestrator.uniquify(destinationDirectory: destinationDir, preferredFilename: preferredFilename)

            do {
                try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                try fm.moveItem(at: standardized, to: target)

                if snapshot.assignFinderTagsOnSortEnabled {
                    let okTag = FinderTagApplicator.merge(
                        composedFinderTagsForSort(snapshot: snapshot, naturalCategory: naturalCategoryForTags, preset: preset, matchedRule: matchedRule),
                        onto: target
                    )
                    if !okTag {
                        tagWriteFailures += 1
                    }
                }

                if snapshot.assignFinderTagsOnSortEnabled, snapshot.sortAppendNewSemanticTagEnabled,
                   let preset, preset.newTagExpiryDays > 0 {
                    await MainActor.run {
                        NewTagExpiryService.shared.register(file: target, expiryDays: preset.newTagExpiryDays)
                    }
                }

                if let preset, !preset.postSortShortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await MainActor.run {
                        PostSortShortcutRunner.run(shortcutName: preset.postSortShortcutName, fileURL: target)
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

            await applyEnergyThrottleBetweenFiles(batchSize: workURLs.count)
        }

        return (rows, tagWriteFailures)
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

            let (defaultRoot, preset) = sortInboxContext(for: standardized, snapshot: snapshot)
            let inboxRoot = rootOverride[standardized] ?? defaultRoot
            let activeRules = activeSortRulesForSnapshot(snapshot: snapshot, preset: preset)

            if snapshot.sortDuplicateMode != .off {
                if let digestTry = try? FileHashStore.shared.digestFile(at: standardized) {
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
                inspection = await ContentInspector.inspect(for: standardized, signals: signals, snapshot: snapshot)
            } else {
                inspection = ContentInspector.emptyInspection
            }

            let contentInput = SortRulesEvaluator.ContentRuleMatchInput(
                hasSignificantOCR: inspection.hasSignificantOCR,
                isReceiptLike: inspection.isReceiptLike
            )
            let matchedRule = SortRulesEvaluator.firstMatchingRule(in: activeRules, signals: signals, content: contentInput)
            let originHost = signals.originHosts.first
            let useReceiptAutoRoute =
                matchedRule == nil
                && snapshot.sortDetectReceiptsEnabled
                && inspection.isReceiptLike
                && (ext == "pdf" || isImageFile)

            let category: FileSortCategory
            let destinationDir: URL
            let preferredFilename: String

            if let rule = matchedRule {
                category = SortRulesEvaluator.customRuleTagCategory
                destinationDir = SortRulesEvaluator.destinationDirectory(rule: rule, category: category, inboxRoot: inboxRoot)
                preferredFilename = SortRulesEvaluator.renamedFilename(
                    originalURL: standardized,
                    rule: rule,
                    renameCounter: renameCounter,
                    originHost: originHost
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
                summary = String.localizedStringWithFormat(
                    String(localized: "Rule “%1$@” → %2$@", comment: "Sort preview; rule name and destination."),
                    rule.name,
                    label
                )
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

    /// Top-level files in each active inbox folder (global watch root + unique preset watch roots).
    static func topLevelInboxFiles(prefs: BinkyPreferences) -> [URL] {
        prefs.reconcileFolderBookmarksIfNeeded()
        let fm = FileManager.default
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
            guard let urls = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            collected.append(contentsOf: urls.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
            })
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
            reason: String(localized: "Binky is sorting files.", comment: "Process activity reason while sorting inbox files.")
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

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sortProgress = SortProgressTracker.shared
    @State private var undoFootnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Move / review summary", comment: "Automated sort audit title."))
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
        queuedIncoming.formUnion(dedup)
        ingestTask?.cancel()
        ingestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while DownloadsSortOrchestrator.shared.isSorting {
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            let batch = Array(queuedIncoming)
            queuedIncoming.removeAll()
            guard !batch.isEmpty else { return }
            while EnergyConditions.shared.shouldPauseFully {
                if Task.isCancelled {
                    queuedIncoming.formUnion(batch)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else {
                queuedIncoming.formUnion(batch)
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
}