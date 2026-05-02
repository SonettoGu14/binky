import AppKit
import Foundation

/// One file that would be affected by an aging rule — preview only, no moves.
struct FileAgingPreviewRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let lastActivity: Date
    let idleDays: Int
    let actionSummary: String
}

/// Moves or trashes stagnant inbox files per ``CategoryAgingRule`` (daily timer).
@MainActor
final class FileAgingService {
    static let shared = FileAgingService()

    private var timer: Timer?

    private init() {}

    func restartTimer(prefs: BinkyPreferences) {
        timer?.invalidate()
        timer = nil
        guard prefs.fileAgingEnabled, !prefs.fileAgingRules.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runSweep(prefs: prefs)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        runSweep(prefs: prefs)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func runSweep(prefs: BinkyPreferences) {
        guard prefs.fileAgingEnabled else { return }
        prefs.reconcileFolderBookmarksIfNeeded()
        let root = prefs.activeSortSweepRootDirectory()
        let fm = FileManager.default
        var moves = 0

        for rule in prefs.fileAgingRules {
            guard rule.untouchedDays > 0,
                  let category = FileSortCategory(rawValue: rule.categoryRaw) else { continue }
            let folder = StarterDestinations.directory(for: category, root: root)
            guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [
                .contentAccessDateKey,
                .addedToDirectoryDateKey,
                .contentModificationDateKey,
                .isDirectoryKey,
            ], options: [.skipsHiddenFiles]) else { continue }

            let cutoff = Date().addingTimeInterval(-Double(rule.untouchedDays) * 24 * 3600)
            for url in urls {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                guard let lastActivity = lastActivityDate(for: url), lastActivity < cutoff else { continue }

                switch rule.action {
                case .archive:
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM"
                    let month = df.string(from: Date())
                    let rel = rule.archiveFolderRelative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let destRoot = root.appendingPathComponent(rel.isEmpty ? "Archive" : rel, isDirectory: true)
                        .appendingPathComponent(month, isDirectory: true)
                    let dest = DownloadsSortOrchestrator.uniquify(
                        destinationDirectory: destRoot,
                        preferredFilename: url.lastPathComponent
                    )
                    do {
                        try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)
                        try fm.moveItem(at: url, to: dest)
                        moves += 1
                    } catch { continue }
                case .trash:
                    do {
                        try fm.trashItem(at: url, resultingItemURL: nil)
                        moves += 1
                    } catch { continue }
                }
            }
        }

        if moves > 0 {
            SortDailyDigestAccumulator.shared.recordAgingArchived(count: moves)
        }
    }

    /// Files that would be moved or trashed **now** if this rule ran (read-only).
    func previewCandidates(rule: CategoryAgingRule, prefs: BinkyPreferences) -> [FileAgingPreviewRow] {
        guard rule.untouchedDays > 0,
              let category = FileSortCategory(rawValue: rule.categoryRaw) else { return [] }
        prefs.reconcileFolderBookmarksIfNeeded()
        let root = prefs.activeSortSweepRootDirectory()
        let fm = FileManager.default
        let folder = StarterDestinations.directory(for: category, root: root)
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [
            .contentAccessDateKey,
            .addedToDirectoryDateKey,
            .contentModificationDateKey,
            .isDirectoryKey,
        ], options: [.skipsHiddenFiles]) else { return [] }

        let cutoff = Date().addingTimeInterval(-Double(rule.untouchedDays) * 24 * 3600)
        var rows: [FileAgingPreviewRow] = []
        let cal = Calendar.current
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard let lastActivity = lastActivityDate(for: url), lastActivity < cutoff else { continue }
            let days = cal.dateComponents([.day], from: lastActivity, to: Date()).day ?? rule.untouchedDays
            let summary: String
            switch rule.action {
            case .archive:
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM"
                let month = df.string(from: Date())
                let rel = rule.archiveFolderRelative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let destRoot = root.appendingPathComponent(rel.isEmpty ? "Archive" : rel, isDirectory: true)
                    .appendingPathComponent(month, isDirectory: true)
                let relPath = String(destRoot.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                summary = String.localizedStringWithFormat(
                    String(localized: "Archive → %@", comment: "Aging preview: relative archive destination."),
                    relPath
                )
            case .trash:
                summary = String(localized: "Trash", comment: "Aging preview: trash action.")
            }
            rows.append(FileAgingPreviewRow(
                id: UUID(),
                url: url,
                lastActivity: lastActivity,
                idleDays: max(days, rule.untouchedDays),
                actionSummary: summary
            ))
        }
        return rows.sorted { $0.lastActivity < $1.lastActivity }
    }

    private func lastActivityDate(for url: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.contentAccessDateKey, .addedToDirectoryDateKey, .contentModificationDateKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        return [v.contentAccessDate, v.addedToDirectoryDate, v.contentModificationDate].compactMap { $0 }.max()
    }
}
