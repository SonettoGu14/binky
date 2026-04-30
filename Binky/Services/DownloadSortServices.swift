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

// MARK: - Semantic buckets + starter folders

enum FileSortCategory: String, CaseIterable, Codable, Sendable {
    case images, pdf, video, audio, documents, archives, apps, screenshots, misc, review

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
        default: return "New"
        }
    }
}

enum SortDisposition: String, Codable, Sendable {
    case moved, kept
    case skippedTransient, skippedStableCheckTimeout, skippedError, skippedExcluded
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
}

struct SortBatchOutcome: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let started: Date
    let elapsed: TimeInterval
    let entries: [SortBatchEntry]

    var movedCount: Int { entries.filter { $0.disposition == .moved }.count }
    var keptCount: Int { entries.filter { $0.disposition == .kept }.count }

    var skippedCount: Int {
        entries.count(where: {
            switch $0.disposition {
            case .skippedTransient, .skippedStableCheckTimeout, .skippedError, .skippedExcluded: return true
            default: return false
            }
        })
    }

    /// Review bucket moves (confidence path).
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

    init(id: UUID, started: Date, elapsed: TimeInterval, entries: [SortBatchEntry]) {
        self.id = id
        self.started = started
        self.elapsed = elapsed
        self.entries = entries
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

private func waitUntilStable(at url: URL, maxSeconds: Double = 120) async -> Bool {
    let fm = FileManager.default
    var lastBytes: Int64?
    var lastMod: Date?
    var unchangedHits = 0
    let end = Date().addingTimeInterval(maxSeconds)

    while Date() < end {
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

    static func merge(_ newTags: [String], onto url: URL) {
        let trimmed = newTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return }

        let path = url.path

        let existingNormalized = normalizedTagStrings(existingPlistData(onPath: path))
        let merged = Array(Set(existingNormalized).union(trimmed)).sorted()

        guard let data = try? PropertyListSerialization.data(fromPropertyList: merged, format: .binary, options: 0),
              merged != existingNormalized || existingPlistData(onPath: path) == nil
        else { return }

        path.withCString { cPath in
            data.withUnsafeBytes { ptr in
                let buf = UnsafeRawPointer(ptr.bindMemory(to: UInt8.self).baseAddress!)
                let _ = Darwin.setxattr(cPath, xattrName, buf, data.count, 0, 0)
            }
        }
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

/// Global semantic tag, profile tags, rule tags, then optional `"New"` (matches per-profile customization plan).
private func composedFinderTagsForSort(
    prefs: BinkyPreferences,
    category: FileSortCategory,
    preset: CompressionPreset?,
    matchedRule: InboxSortRule?
) -> [String] {
    var tags: [String] = [category.semanticTagHint]
    if let preset {
        tags.append(contentsOf: preset.customFinderTags.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
    }
    if let matchedRule {
        tags.append(contentsOf: matchedRule.addedTags.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
    }
    if prefs.sortAppendNewSemanticTagEnabled {
        tags.append("New")
    }
    return tags
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

// MARK: - Physical layout helpers

enum StarterBuckets {
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

@MainActor
final class DownloadsSortOrchestrator {

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

    /// Shows where files would land **without** waiting on stability or moving anything.
    func previewSort(files urls: [URL], prefs: BinkyPreferences) -> [SortPreviewEntry] {
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
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourceLastPathComponent: standardized.lastPathComponent,
                    proposedDestinationPath: "—",
                    summary: String(localized: "Skipped — looks like an incomplete download.", comment: "Sort preview row.")
                ))
                continue
            }

            if SortRulesEvaluator.isExcluded(url: standardized, prefs: prefs) {
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourceLastPathComponent: standardized.lastPathComponent,
                    proposedDestinationPath: "—",
                    summary: String(localized: "Excluded — matches your ignore list.", comment: "Sort preview row.")
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
                    modificationDate: nil
                )

            let (inboxRoot, preset) = prefs.sortContext(for: standardized)
            let activeRules = activeSortRulesForSort(prefs: prefs, preset: preset)
            let matchedRule = SortRulesEvaluator.firstMatchingRule(in: activeRules, signals: signals)

            let category: FileSortCategory
            let destinationDir: URL
            let preferredFilename: String

            if let rule = matchedRule {
                category = SortRulesEvaluator.customRuleTagCategory
                destinationDir = SortRulesEvaluator.destinationDirectory(rule: rule, category: category, inboxRoot: inboxRoot)
                preferredFilename = SortRulesEvaluator.renamedFilename(originalURL: standardized, rule: rule, renameCounter: renameCounter)
                if rule.renameStyle != .none { renameCounter += 1 }
            } else {
                category = FileClassification.categorize(url: standardized)
                destinationDir = StarterBuckets.directory(for: category, root: inboxRoot)
                preferredFilename = standardized.lastPathComponent
            }

            if standardized.deletingLastPathComponent().standardizedFileURL == destinationDir.standardizedFileURL,
               standardized.lastPathComponent == preferredFilename {
                out.append(SortPreviewEntry(
                    id: UUID(),
                    sourceLastPathComponent: standardized.lastPathComponent,
                    proposedDestinationPath: destinationDir.path,
                    summary: String(localized: "Already in place — no move.", comment: "Sort preview row.")
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
            } else {
                summary = String.localizedStringWithFormat(
                    String(localized: "Automatic sort → %1$@", comment: "Sort preview; destination label."),
                    label
                )
            }

            out.append(SortPreviewEntry(
                id: UUID(),
                sourceLastPathComponent: standardized.lastPathComponent,
                proposedDestinationPath: target.path,
                summary: summary
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

    func previewInbox(prefs: BinkyPreferences) -> [SortPreviewEntry] {
        previewSort(files: Self.topLevelInboxFiles(prefs: prefs), prefs: prefs)
    }

    func sort(files urls: [URL], prefs: BinkyPreferences) async -> SortBatchOutcome {
        let fm = FileManager.default
        let startedAt = Date()
        prefs.reconcileFolderBookmarksIfNeeded()

        let uniqueRoots = Set(urls.map { prefs.sortContext(for: $0.standardizedFileURL).inboxRoot })
        for root in uniqueRoots {
            StarterBuckets.ensure(downloadsRoot: root)
        }

        var rows: [SortBatchEntry] = []
        var renameCounter = 1

        for raw in urls {
            let standardized = raw.standardizedFileURL
            guard standardized.isFileURL else { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir), !isDir.boolValue else { continue }

            if looksTransientIncomplete(standardized) {
                rows.append(entry(path: standardized.path, dest: nil, category: .review, disposition: .skippedTransient,
                                  reason: String(localized: "Temporary download artifact — skipping until finalized.", comment: "Sort log."),
                                  matchedRuleName: nil))
                continue
            }

            guard await waitUntilStable(at: standardized) else {
                rows.append(entry(path: standardized.path, dest: nil, category: .review, disposition: .skippedStableCheckTimeout,
                                  reason: String(localized: "File never stabilized before timeout.", comment: "Sort log."),
                                  matchedRuleName: nil))
                continue
            }

            if SortRulesEvaluator.isExcluded(url: standardized, prefs: prefs) {
                rows.append(entry(path: standardized.path, dest: nil, category: .misc, disposition: .skippedExcluded,
                                  reason: String(localized: "Skipped — file matches your ignore list.", comment: "Sort log."),
                                  matchedRuleName: nil))
                continue
            }

            let signals = SortRulesEvaluator.loadSignals(url: standardized)
                ?? SortRulesEvaluator.FileSignals(
                    ext: standardized.pathExtension.lowercased(),
                    baseName: standardized.lastPathComponent,
                    byteSize: 0,
                    addedToDirectoryDate: nil,
                    creationDate: nil,
                    modificationDate: nil
                )

            let (inboxRoot, preset) = prefs.sortContext(for: standardized)
            let activeRules = activeSortRulesForSort(prefs: prefs, preset: preset)
            let matchedRule = SortRulesEvaluator.firstMatchingRule(in: activeRules, signals: signals)

            let category: FileSortCategory
            let destinationDir: URL
            let preferredFilename: String
            let ruleName: String?

            if let rule = matchedRule {
                category = SortRulesEvaluator.customRuleTagCategory
                destinationDir = SortRulesEvaluator.destinationDirectory(rule: rule, category: category, inboxRoot: inboxRoot)
                preferredFilename = SortRulesEvaluator.renamedFilename(originalURL: standardized, rule: rule, renameCounter: renameCounter)
                if rule.renameStyle != .none { renameCounter += 1 }
                ruleName = rule.name
            } else {
                category = FileClassification.categorize(url: standardized)
                destinationDir = StarterBuckets.directory(for: category, root: inboxRoot)
                preferredFilename = standardized.lastPathComponent
                ruleName = nil
            }

            if standardized.deletingLastPathComponent().standardizedFileURL == destinationDir.standardizedFileURL,
               standardized.lastPathComponent == preferredFilename {
                rows.append(entry(path: standardized.path, dest: standardized.path, category: category, disposition: .kept,
                                  reason: String(localized: "Already sorted into this bucket.", comment: "Sort log."),
                                  matchedRuleName: ruleName))
                continue
            }

            let target = DownloadsSortOrchestrator.uniquify(destinationDirectory: destinationDir, preferredFilename: preferredFilename)

            do {
                try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                try fm.moveItem(at: standardized, to: target)

                if prefs.assignFinderTagsOnSortEnabled {
                    FinderTagApplicator.merge(
                        composedFinderTagsForSort(prefs: prefs, category: category, preset: preset, matchedRule: matchedRule),
                        onto: target
                    )
                }

                if prefs.assignFinderTagsOnSortEnabled, prefs.sortAppendNewSemanticTagEnabled,
                   let preset, preset.newTagExpiryDays > 0 {
                    NewTagExpiryService.shared.register(file: target, expiryDays: preset.newTagExpiryDays)
                }

                if let preset, !preset.postSortShortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    PostSortShortcutRunner.run(shortcutName: preset.postSortShortcutName, fileURL: target)
                }

                rows.append(entry(path: standardized.path,
                                  dest: target.path,
                                  category: category,
                                  disposition: .moved,
                                  reason: localizedMoveReason(category: category, matchedRuleName: ruleName, destinationDir: destinationDir, inboxRoot: inboxRoot),
                                  matchedRuleName: ruleName))

            } catch {
                rows.append(entry(path: standardized.path,
                                  dest: nil,
                                  category: category,
                                  disposition: .skippedError,
                                  reason: error.localizedDescription,
                                  matchedRuleName: ruleName))
            }
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        lastUndoPairs = rows
            .filter { $0.disposition == .moved }
            .compactMap { row in
                guard let dst = row.destinationPath else { return nil }
                return (URL(fileURLWithPath: dst), URL(fileURLWithPath: row.sourcePath))
            }

        let outcome = SortBatchOutcome(id: UUID(), started: startedAt, elapsed: elapsed, entries: rows)
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

    private func entry(path: String, dest: String?, category: FileSortCategory,
                       disposition: SortDisposition, reason: String, matchedRuleName: String?) -> SortBatchEntry {
        .init(id: UUID(), sourcePath: path, destinationPath: dest, category: category, disposition: disposition, reason: reason,
              matchedRuleName: matchedRuleName)
    }

    private func localizedMoveReason(category _: FileSortCategory, matchedRuleName: String?, destinationDir: URL, inboxRoot: URL) -> String {
        let label = destinationDisplayLabel(root: inboxRoot, destinationDir: destinationDir)
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

    func undoLastBatchUsingPairs() async {
        let fm = FileManager.default
        for pair in lastUndoPairs.reversed() {
            if fm.fileExists(atPath: pair.0.path) {
                try? fm.moveItem(at: pair.0, to: pair.1)
            }
        }
        lastUndoPairs = []
    }
}

extension BinkyPreferences {

    /// Canonical watched inbox root (defaults to Downloads; honors global watch-folder bookmark path).
    func downloadsSortRootDirectory() -> URL {
        reconcileFolderBookmarksIfNeeded()
        if folderWatchEnabled, !watchedFolderPath.isEmpty {
            let normalized = watchedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
            return URL(fileURLWithPath: normalized).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .standardizedFileURL
    }

    /// Finder tags layered on freshly sorted items (semantic tag + optional “New”).
    func sortTagComposition(forCategory category: FileSortCategory) -> [String] {
        var tags: [String] = []
        if sortAppendNewSemanticTagEnabled { tags.append("New") }
        tags.append(category.semanticTagHint)
        return tags
    }

    /// Persists coarse history alongside compression sessions (`SessionRecord.batchSummaryData` carries `SortBatchOutcome` JSON).
    func appendSortOutcomeRecord(_ outcome: SortBatchOutcome) {
        let payload = try? JSONEncoder().encode(outcome)
        guard let data = payload else { return }

        let record = SessionRecord(
            id: outcome.id,
            timestamp: outcome.started,
            fileCount: outcome.entries.count,
            totalBytesSaved: Int64(outcome.entries.filter { $0.disposition == .moved }.count),
            formats: outcome.entries.isEmpty
                ? ["Downloads sort"]
                : Array(Set(outcome.entries.map(\.category.rawValue))).sorted(),
            batchSummaryData: data
        )

        var hist = sessionHistory
        hist.insert(record, at: 0)
        sessionHistory = Array(hist.prefix(50))
    }
}

// MARK: - Preview (dry run)

/// One row for **Preview sort** — no files are moved.
struct SortPreviewEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceLastPathComponent: String
    let proposedDestinationPath: String
    let summary: String
}

// MARK: — Trust-focused sheet

struct SortOutcomeSheet: View {

    let outcome: SortBatchOutcome
    var onRevealDestination: (SortBatchEntry) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onDismiss: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Move / review summary", comment: "Automated sort audit title."))
                .font(.title2)

            HStack(spacing: 12) {
                statChip(title: String(localized: "Moved", comment: "Sort audit"), value: outcome.movedCount, systemImage: "folder")
                statChip(title: String(localized: "Kept", comment: "Sort audit"), value: outcome.keptCount, systemImage: "checkmark.circle")
                statChip(title: String(localized: "Skipped", comment: "Sort audit"), value: outcome.skippedCount, systemImage: "minus.circle")
                statChip(title: String(localized: "Review", comment: "Sort audit queue"), value: outcome.reviewQueuedCount, systemImage: "questionmark.circle")
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(outcome.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: entry.sourcePath).lastPathComponent)
                                .font(.headline)
                            Text(entry.reason)
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

            HStack {
                Button(role: .cancel, action: { onDismiss(); dismiss() }) {
                    Text(String(localized: "Close", comment: "Sort audit sheet dismiss."))
                }
                Button(String(localized: "Undo moves", comment: "Sort audit")) {
                    Task {
                        await DownloadsSortOrchestrator.shared.undoLastBatchUsingPairs()
                        onUndo()
                        dismiss()
                        onDismiss()
                    }
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(outcome.reversibleMoves.isEmpty)
                Spacer()
            }
        }
        .padding(24)
        .frame(minWidth: 520)
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

    init(prefs: BinkyPreferences, viewModel: OrganizerViewModel) {
        self.prefs = prefs
        self.viewModel = viewModel

        watcher.onNewFiles = { [weak self] incoming in
            self?.handleIncoming(incoming)
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

    private func handleIncoming(_ incoming: [URL]) {
        let dedup = Array(Set(incoming.map(\.standardizedFileURL))).filter(\.isFileURL)
        guard !dedup.isEmpty else { return }
        Task { @MainActor in
            let outcome = await DownloadsSortOrchestrator.shared.sort(files: dedup, prefs: prefs)
            guard outcome.hasWork else { return }
            viewModel.deliverCompletedSort(outcome, prefs: prefs)
        }
    }
}