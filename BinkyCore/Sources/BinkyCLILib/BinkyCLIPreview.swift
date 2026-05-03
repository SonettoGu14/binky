import BinkyCoreShared
import BinkyCoreSort
import Foundation

enum BinkyCLIPreviewCommand {

    private struct PreviewJSONEnvelope: Codable {
        let schema: String
        let entries: [Row]
    }

    private struct Row: Codable {
        let input: String
        let plannedDestination: String
        let category: String
        let matchedRule: String?
        let addedTags: [String]
        let disposition: String
    }

    /// Read-only planner path (no flock).
    nonisolated static func execute(rawArgs: [String], prefs: BinkyPrefsStore, stderrPrelude: String? = nil) -> Int32 {
        if let prelude = stderrPrelude {
            BinkyCLIPrint.err(prelude)
        }

        switch BinkyCLIParse.peelPathOpts(tokens: rawArgs) {
        case let .failure(err):
            switch err {
            case let .missingFlagValue(flag):
                BinkyCLIPrint.err("preview: missing value for \(flag).")
            case let .unknownFlag(flag):
                BinkyCLIPrint.err("preview: unknown flag \(flag).")
            }
            return 1
        case let .success(bundle):
            let mergedPOSIX: [String]
            do {
                mergedPOSIX = try BinkyCLIParse.mergeStdin(paths: bundle.remainder) {
                    try BinkyCLIPaths.readPOSIXPathsFromStandardInput()
                }
            } catch {
                BinkyCLIPrint.err("preview: stdin: \(error.localizedDescription)")
                return 1
            }

            let urlsAll = BinkyCLIPaths.uniqPreservingOrder(BinkyCLIPaths.standardizedFileURLs(posixPaths: mergedPOSIX))
            guard !urlsAll.isEmpty else {
                BinkyCLIPrint.err("preview: no eligible file paths.")
                return 1
            }

            let snapshot = prefs.makeSortPreferencesSnapshot()

            var rootOverrideByFile = [URL: URL]()
            if let rootPOSIX = bundle.opts.inboxRootPOSIX?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !rootPOSIX.isEmpty {
                let pinned = URL(fileURLWithPath: (rootPOSIX as NSString).expandingTildeInPath).standardizedFileURL
                for u in urlsAll { rootOverrideByFile[u.standardizedFileURL] = pinned }
            }

            let rootOverridesCaptured = rootOverrideByFile
            let rowsModel = BinkyCLIAsync.runBlocking {
                await SortPreviewPlanner.preview(files: urlsAll, snapshot: snapshot, rootOverride: rootOverridesCaptured)
            }

            if bundle.opts.json {
                let rows = rowsModel.map {
                    Row(
                        input: $0.sourcePath,
                        plannedDestination: $0.proposedDestinationPath,
                        category: $0.category.rawValue,
                        matchedRule: $0.matchedRuleName,
                        addedTags: $0.addedTags,
                        disposition: $0.planDisposition.rawValue
                    )
                }
                let env = PreviewJSONEnvelope(schema: "binky.sort.preview/1.0.0", entries: rows)
                BinkyCLIPrint.jsonLine(env)
            } else if !bundle.opts.quiet {
                for row in rowsModel {
                    let rule = row.matchedRuleName.map { "\"\($0)\"" } ?? "–"
                    BinkyCLIPrint.err(
                        "preview: \(URL(fileURLWithPath: row.sourcePath).lastPathComponent) → \(row.proposedDestinationPath) [\(row.category.rawValue)] rule:\(rule) tags:[\(row.addedTags.joined(separator: ", "))]"
                    )
                }
            }
            return 0
        }
    }
}
