import BinkyCoreShared
import BinkyCoreSort
import Foundation

enum BinkyCLIRoutinesCommand {

    private struct RoutineSummaryRow: Codable {
        let name: String
        let enabled: Bool
        /// Resolved POSIX watch path when the bookmark resolves; otherwise the stored path string.
        let sourcePath: String
    }

    private struct RoutineListEnvelope: Codable {
        let schema: String
        let routines: [RoutineSummaryRow]
    }

    private struct RoutineRunEnvelope: Codable {
        let schema: String
        let routineName: String
        let outcome: SortBatchOutcome
    }

    nonisolated static func execute(listArgs: [String], prefs: BinkyPrefsStore) -> Int32 {
        switch BinkyCLIParse.peelPathOpts(tokens: listArgs) {
        case let .failure(err):
            routinesListParseFailure(err)
            return 1
        case let .success(bundle):
            if bundle.opts.inboxRootPOSIX != nil || bundle.opts.dryRun {
                BinkyCLIPrint.err("routines list: unknown flag for this subcommand.")
                return 1
            }
            guard bundle.remainder.isEmpty else {
                BinkyCLIPrint.err("routines list: unexpected arguments — try `\(BinkyCLIPackageMeta.toolName) routines list`.")
                return 1
            }

            let presets = prefs.decodingSavedPresets()

            func resolvedPath(for preset: SortingRoutine) -> String {
                if let p = WatchFolderPathResolver.resolvedWatchDirectoryPath(
                    bookmark: preset.watchFolderBookmark,
                    storedPath: preset.watchFolderPath
                ), !p.isEmpty {
                    return p
                }
                return preset.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let rows = presets.map {
                RoutineSummaryRow(name: $0.name, enabled: $0.isEnabled, sourcePath: resolvedPath(for: $0))
            }

            if bundle.opts.json {
                let env = RoutineListEnvelope(schema: "binky.routines.list/1.0.0", routines: rows)
                BinkyCLIPrint.jsonLine(env)
            } else if !bundle.opts.quiet {
                guard !presets.isEmpty else {
                    BinkyCLIPrint.err("routines list: (none configured)")
                    return 0
                }
                for p in presets {
                    let badge = p.isEnabled ? "on" : "off"
                    BinkyCLIPrint.err("• [\(badge)] \(p.name) → \(resolvedPath(for: p))")
                }
            }
            return 0
        }
    }

    nonisolated static func executeRun(runArgs: [String], prefs: BinkyPrefsStore) -> Int32 {
        switch BinkyCLIParse.peelPathOpts(tokens: runArgs) {
        case let .failure(err):
            routinesRunParseFailure(err)
            return 1
        case let .success(bundle):
            if bundle.opts.dryRun || bundle.opts.inboxRootPOSIX != nil {
                BinkyCLIPrint.err("routines run: unknown flag for this subcommand.")
                return 1
            }

            let nameQuery = bundle.remainder.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !nameQuery.isEmpty else {
                BinkyCLIPrint.err("routines run: missing routine name.")
                return 1
            }

            let presets = prefs.decodingSavedPresets()
            let hits = presets.filter {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(nameQuery) == .orderedSame
            }
            guard let routine = hits.first, hits.count == 1 else {
                if hits.isEmpty {
                    BinkyCLIPrint.err("routines run: no routine named “\(nameQuery)”.")
                } else {
                    BinkyCLIPrint.err("routines run: more than one routine matches “\(nameQuery)” — give a unique name.")
                }
                return 1
            }

            guard let resolved = WatchFolderPathResolver.resolvedWatchDirectoryPath(
                bookmark: routine.watchFolderBookmark,
                storedPath: routine.watchFolderPath
            ), !resolved.isEmpty else {
                BinkyCLIPrint.err("routines run: cannot resolve watch folder for “\(routine.name)”.")
                return 1
            }

            let root = URL(fileURLWithPath: resolved).standardizedFileURL
            let snapshot = prefs.makeSortPreferencesSnapshot()
            let files = SortSweepFilesCollection.files(in: root, recursiveOneLevel: snapshot.watchRecursiveOneLevel)
            guard !files.isEmpty else {
                BinkyCLIPrint.err("routines run: no eligible files in \(root.path).")
                return 0
            }

            var overrides = [URL: URL]()
            for u in files {
                overrides[u.standardizedFileURL] = root
            }

            let json = bundle.opts.json
            let quietEngine = json || bundle.opts.quiet

            let res = BinkyCLISortCommand.runPreparedBatchLocked(
                workURLs: files,
                inboxRootOverrides: overrides,
                prefs: prefs,
                emitJSON: false,
                quiet: quietEngine,
                stderrPrefix: "routines run:",
                envelopeSchemaID: "binky.routines.run.outcome/1.0.0",
                persistOutcome: { prefs.appendSortOutcomeRecord($0) }
            )

            guard res.exitCode == 0, let outcome = res.outcome else {
                return res.exitCode
            }

            if json {
                let env = RoutineRunEnvelope(
                    schema: "binky.routines.run.outcome/1.0.0",
                    routineName: routine.name,
                    outcome: outcome
                )
                BinkyCLIPrint.jsonLine(env)
            }
            return 0
        }
    }

    private static func routinesListParseFailure(_ err: BinkyCLIParse.Failure) {
        switch err {
        case let .missingFlagValue(flag):
            BinkyCLIPrint.err("routines list: missing value for \(flag).")
        case let .unknownFlag(flag):
            BinkyCLIPrint.err("routines list: unknown flag \(flag).")
        }
    }

    private static func routinesRunParseFailure(_ err: BinkyCLIParse.Failure) {
        switch err {
        case let .missingFlagValue(flag):
            BinkyCLIPrint.err("routines run: missing value for \(flag).")
        case let .unknownFlag(flag):
            BinkyCLIPrint.err("routines run: unknown flag \(flag).")
        }
    }
}
