import BinkyCoreShared
import Foundation

enum BinkyCLIUndoCommand {

    struct UndoOptions: Equatable {
        var json: Bool = false
        var quiet: Bool = false
        var batch: UUID?
    }

    private struct UndoJSONEnvelope: Codable {
        let schema: String
        let attempted: Int
        let failures: Int
        let outcomeBatchId: String?
    }

    private enum UndoPeelError: Swift.Error {
        case message(String)
    }

    private static func peelUndo(tokens: [String]) -> Result<UndoOptions, UndoPeelError> {
        var opts = UndoOptions()
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            switch t {
            case "--json":
                opts.json = true
                i += 1
            case "--quiet", "-q":
                opts.quiet = true
                i += 1
            case "--batch":
                guard i + 1 < tokens.count else {
                    return .failure(.message("undo: missing value for --batch"))
                }
                let raw = tokens[i + 1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard let u = UUID(uuidString: raw) else {
                    return .failure(.message("undo: --batch must be a UUID string"))
                }
                opts.batch = u
                i += 2
            default:
                if t.hasPrefix("--") || (t.hasPrefix("-") && t != "-") {
                    return .failure(.message("undo: unknown flag \(t)"))
                }
                return .failure(.message("undo: unexpected argument \(t)"))
            }
        }
        return .success(opts)
    }

    nonisolated static func execute(rawArgs: [String], prefs: BinkyPrefsStore) -> Int32 {
        switch peelUndo(tokens: rawArgs) {
        case let .failure(.message(text)):
            BinkyCLIPrint.err(text)
            return 1
        case let .success(opts):
            let history = prefs.loadSessionHistory()
            let record: SortSessionHistoryRecord
            if let id = opts.batch {
                guard let chosen = history.first(where: { $0.id == id }) else {
                    BinkyCLIPrint.err("undo: no history entry for batch id \(id.uuidString).")
                    return 1
                }
                record = chosen
            } else {
                guard let newest = history.first else {
                    BinkyCLIPrint.err("undo: session history is empty.")
                    return 1
                }
                record = newest
            }

            guard let blob = record.batchSummaryData else {
                BinkyCLIPrint.err("undo: that history entry has no persisted sort payload.")
                return 1
            }

            guard let outcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: blob) else {
                BinkyCLIPrint.err("undo: could not decode stored sort outcome.")
                return 1
            }

            let pairs = outcome.reversibleMoves
            guard !pairs.isEmpty else {
                BinkyCLIPrint.err("undo: no reversible moves recorded for that batch.")
                return 1
            }

            let summary = reversing(pairs: pairs.map { ($0.destination, $0.source) })
            let failed = summary.failures > 0 ? 1 as Int32 : 0 as Int32

            if opts.json {
                let env = UndoJSONEnvelope(
                    schema: "binky.sort.undo/1.0.0",
                    attempted: summary.attempted,
                    failures: summary.failures,
                    outcomeBatchId: outcome.id.uuidString
                )
                BinkyCLIPrint.jsonLine(env)
            } else if !opts.quiet {
                BinkyCLIPrint.err(
                    "undo: attempted \(summary.attempted) · failures \(summary.failures) · batch \(outcome.id.uuidString)"
                )
            }
            return failed
        }
    }

    nonisolated private static func reversing(pairs: [(destination: URL, source: URL)]) -> UndoMovesSummary {
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
        return UndoMovesSummary(attempted: attempted, failures: failures)
    }
}
