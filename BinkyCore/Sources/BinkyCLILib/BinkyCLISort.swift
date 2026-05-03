import BinkyCoreShared
import BinkyCoreSort
import Foundation

enum BinkyCLISortCommand {

    private struct SortOutcomeEnvelope: Codable {
        let schema: String
        let outcome: SortBatchOutcome
    }

    struct LockedSortResult: Sendable {
        let exitCode: Int32
        let outcome: SortBatchOutcome?
    }

    /// Implements `sort` (mutating prefs history). Caller must not route `--dry-run` here — that maps to Preview.
    nonisolated static func execute(rawArgs: [String], prefs: BinkyPrefsStore) -> Int32 {
        switch BinkyCLIParse.peelPathOpts(tokens: rawArgs) {
        case let .failure(err):
            switch err {
            case let .missingFlagValue(flag):
                BinkyCLIPrint.err("sort: missing value for \(flag).")
            case let .unknownFlag(flag):
                BinkyCLIPrint.err("sort: unknown flag \(flag).")
            }
            return 1
        case let .success(bundle):
            if bundle.opts.dryRun {
                BinkyCLIPrint.err("sort: internal routing error (--dry-run should call preview).")
                return 1
            }

            let mergedPOSIX: [String]
            do {
                mergedPOSIX = try BinkyCLIParse.mergeStdin(paths: bundle.remainder) {
                    try BinkyCLIPaths.readPOSIXPathsFromStandardInput()
                }
            } catch {
                BinkyCLIPrint.err("sort: stdin: \(error.localizedDescription)")
                return 1
            }

            let urls = BinkyCLIPaths.uniqPreservingOrder(BinkyCLIPaths.standardizedFileURLs(posixPaths: mergedPOSIX))
            guard !urls.isEmpty else {
                BinkyCLIPrint.err("sort: no eligible file paths.")
                return 1
            }

            var overrides = [URL: URL]()
            if let rootPOSIX = bundle.opts.inboxRootPOSIX?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !rootPOSIX.isEmpty {
                let pinned = URL(fileURLWithPath: (rootPOSIX as NSString).expandingTildeInPath).standardizedFileURL
                for u in urls { overrides[u.standardizedFileURL] = pinned }
            }

            let res = runPreparedBatchLocked(
                workURLs: urls,
                inboxRootOverrides: overrides,
                prefs: prefs,
                emitJSON: bundle.opts.json,
                quiet: bundle.opts.quiet,
                stderrPrefix: "sort:",
                envelopeSchemaID: "binky.sort.outcome/1.0.0",
                persistOutcome: { prefs.appendSortOutcomeRecord($0) }
            )
            return res.exitCode
        }
    }

    /// Shared flock-backed sort batch for CLI `sort` and ``routines run``.
    nonisolated static func runPreparedBatchLocked(
        workURLs: [URL],
        inboxRootOverrides: [URL: URL],
        prefs: BinkyPrefsStore,
        emitJSON: Bool,
        quiet: Bool,
        stderrPrefix: String,
        envelopeSchemaID: String,
        persistOutcome: ((SortBatchOutcome) -> Void)? = nil
    ) -> LockedSortResult {
        let snapshot = prefs.makeSortPreferencesSnapshot()
        let uniqueRoots = Set(workURLs.map { u in
            inboxRootOverrides[u.standardizedFileURL]
                ?? sortInboxContext(for: u.standardizedFileURL, snapshot: snapshot).inboxRoot
        })
        for root in uniqueRoots {
            StarterDestinations.ensure(downloadsRoot: root)
        }

        let flock = SortCrossProcessLock()
        guard flock.tryLock() else {
            BinkyCLIPrint.err(
                "\(stderrPrefix) blocked — \(flock.lockPOSIXPath) is held (another \(BinkyCLIPackageMeta.toolName) sort, Binky GUI sort, etc.)."
            )
            return LockedSortResult(exitCode: 1, outcome: nil)
        }
        defer { flock.unlock() }

        let startedAt = Date()
        let gate = SortRunGate()
        defer { gate.endSession() }

        let progress: (@Sendable (SortProgressEvent) -> Void)?
        if quiet {
            progress = nil
        } else {
            progress = { event in
                if case let .fileStarted(_, name, _) = event {
                    BinkyCLIPrint.err("\(stderrPrefix) ▸ \(name)")
                }
            }
        }

        let loop = BinkyCLIAsync.runBlocking {
            await SortWork.runSortWorkLoop(
                workURLs: workURLs,
                snapshot: snapshot,
                rootOverride: inboxRootOverrides,
                gate: gate,
                progress: progress,
                hooks: .detached
            )
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        let batchID = UUID()
        let warnings = warningsForTagWriteFailures(tagFails: loop.tagWriteFailures)
        let outcome = SortBatchOutcome(
            id: batchID,
            started: startedAt,
            elapsed: elapsed,
            entries: loop.rows,
            ancillaryWarnings: warnings
        )

        persistOutcome?(outcome)

        if emitJSON {
            BinkyCLIPrint.jsonLine(SortOutcomeEnvelope(schema: envelopeSchemaID, outcome: outcome))
        } else if !quiet {
            for entry in outcome.entries {
                let tail = cliCompactReason(entry.reason)
                BinkyCLIPrint.err("[\(entry.disposition.rawValue)] \(URL(fileURLWithPath: entry.sourcePath).lastPathComponent) — \(tail)")
            }
            BinkyCLIPrint.err("\(stderrPrefix) \(outcome.movedCount) moved · \(outcome.skippedCount) skipped · \(outcome.keptCount) kept.")
        }

        return LockedSortResult(exitCode: 0, outcome: outcome)
    }

    nonisolated private static func cliCompactReason(_ reason: String) -> String {
        if reason.count < 260 { return reason }
        return String(reason.prefix(260)) + "…"
    }

    nonisolated private static func warningsForTagWriteFailures(tagFails: Int) -> [String] {
        guard tagFails > 0 else { return [] }
        if tagFails == 1 {
            return ["Finder tags didn't stick for one file — the sort still landed."]
        }
        return ["Finder tags didn't stick for \(tagFails) files — the sort still landed."]
    }
}
