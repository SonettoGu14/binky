import BinkyCoreShared
import BinkyCoreSort
import Foundation

enum BinkyCLITagCommand {

    private struct TagApplyEnvelope: Codable {
        let schema: String
        let results: [Row]
    }

    private struct Row: Codable {
        let path: String
        let tags: [String]
        let disposition: String
        let applied: Bool
    }

    nonisolated static func execute(rawArgs: [String], prefs: BinkyPrefsStore) -> Int32 {
        switch BinkyCLIParse.peelPathOpts(tokens: rawArgs) {
        case let .failure(err):
            switch err {
            case let .missingFlagValue(flag):
                BinkyCLIPrint.err("tag: missing value for \(flag).")
            case let .unknownFlag(flag):
                BinkyCLIPrint.err("tag: unknown flag \(flag).")
            }
            return 1
        case let .success(bundle):
            if bundle.opts.dryRun || bundle.opts.inboxRootPOSIX != nil {
                BinkyCLIPrint.err("tag: unsupported flag for this command.")
                return 1
            }

            let snapshot = prefs.makeSortPreferencesSnapshot()
            guard snapshot.assignFinderTagsOnSortEnabled else {
                BinkyCLIPrint.err("tag: turn on “Assign Finder tags when sorting” in Binky Settings first.")
                return 1
            }

            let mergedPOSIX: [String]
            do {
                mergedPOSIX = try BinkyCLIParse.mergeStdin(paths: bundle.remainder) {
                    try BinkyCLIPaths.readPOSIXPathsFromStandardInput()
                }
            } catch {
                BinkyCLIPrint.err("tag: stdin: \(error.localizedDescription)")
                return 1
            }

            let urls = BinkyCLIPaths.uniqPreservingOrder(BinkyCLIPaths.standardizedFileURLs(posixPaths: mergedPOSIX))
            guard !urls.isEmpty else {
                BinkyCLIPrint.err("tag: no eligible file paths.")
                return 1
            }

            let rowsModel = BinkyCLIAsync.runBlocking {
                await SortPreviewPlanner.preview(files: urls, snapshot: snapshot, rootOverride: [:])
            }

            var jsonRows: [Row] = []
            for preview in rowsModel {
                let mergedOK: Bool
                if preview.addedTags.isEmpty {
                    mergedOK = false
                } else {
                    let url = URL(fileURLWithPath: preview.sourcePath).standardizedFileURL
                    mergedOK = FinderTagApplicator.merge(preview.addedTags, onto: url)
                    if !bundle.opts.json && !bundle.opts.quiet {
                        let state = mergedOK ? "ok" : "failed"
                        BinkyCLIPrint.err("tag (\(state)): \(url.lastPathComponent) ← [\(preview.addedTags.joined(separator: ", "))]")
                    }
                }

                if bundle.opts.json {
                    jsonRows.append(
                        Row(
                            path: preview.sourcePath,
                            tags: preview.addedTags,
                            disposition: preview.planDisposition.rawValue,
                            applied: mergedOK
                        )
                    )
                }
            }

            if bundle.opts.json {
                let env = TagApplyEnvelope(schema: "binky.tag.apply/1.0.0", results: jsonRows)
                BinkyCLIPrint.jsonLine(env)
            }
            return 0
        }
    }
}
