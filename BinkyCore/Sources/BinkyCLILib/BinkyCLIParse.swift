import Foundation

struct PathCommandOpts: Equatable {
    var json: Bool = false
    var quiet: Bool = false
    var dryRun: Bool = false
    /// Optional POSIX path for a one-shot inbox root (applied to each file in the batch).
    var inboxRootPOSIX: String?
}

enum BinkyCLIParse {

    enum Failure: Swift.Error, Equatable {
        case missingFlagValue(String)
        case unknownFlag(String)
    }

    /// Parses coordinator flags wherever they appear; remaining tokens keep their relative order.
    nonisolated static func peelPathOpts(tokens: [String]) -> Result<(opts: PathCommandOpts, remainder: [String]), Failure> {
        var opts = PathCommandOpts()
        var positional: [String] = []

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
            case "--dry-run":
                opts.dryRun = true
                i += 1
            case "--root":
                guard i + 1 < tokens.count else { return .failure(.missingFlagValue("--root")) }
                opts.inboxRootPOSIX = tokens[i + 1]
                i += 2
            default:
                if t.hasPrefix("--") || (t.hasPrefix("-") && t != "-") {
                    return .failure(.unknownFlag(t))
                }
                positional.append(t)
                i += 1
            }
        }
        return .success((opts, positional))
    }

    /// Collects hyphen tokens from positional strings (including stdin expansion callers).
    nonisolated static func mergeStdin(paths raw: [String], stdinPaths: () throws -> [String]) throws -> [String] {
        var out: [String] = []
        for fragment in raw {
            if fragment == "-" {
                out.append(contentsOf: try stdinPaths())
            } else {
                out.append(fragment)
            }
        }
        return out
    }
}
