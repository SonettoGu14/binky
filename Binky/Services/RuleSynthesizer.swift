import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Natural-language → ``InboxSortRule``. On macOS 26+ uses on-device Foundation Models when available; falls back to heuristics.
enum RuleSynthesizer {

    static func synthesize(from phrase: String, order: Int) async -> InboxSortRule? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let modelRule = await synthesizeWithFoundationModels(phrase: trimmed, order: order) {
                return modelRule
            }
        }
        #endif

        return heuristicRule(from: trimmed, order: order)
    }

    private static func heuristicRule(from phrase: String, order: Int) -> InboxSortRule {
        var rule = InboxSortRule.fresh(order: order)
        rule.name = String(localized: "From phrase", comment: "NL rule default name.")

        let lower = phrase.lowercased()

        if let destRange = lower.range(of: " to ") {
            let head = String(lower[..<destRange.lowerBound])
            let tail = String(lower[destRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            extractDomains(from: head, into: &rule)
            let dest = tail.split(whereSeparator: \.isWhitespace).joined(separator: "/")
            if !dest.isEmpty {
                rule.destinationRelativePath = dest
            }
        } else {
            extractDomains(from: lower, into: &rule)
        }

        if lower.contains("receipt") || lower.contains("invoice") {
            rule.contentMatch = SortContentMatch(kind: .receipt)
            rule.fileKindFilter = .pdf
        }

        return rule
    }

    private static func extractDomains(from head: String, into rule: inout InboxSortRule) {
        if head.contains("from ") {
            let raw = head.replacingOccurrences(of: "from ", with: "")
            let parts = raw.split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            rule.originDomains = parts
        }
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func synthesizeWithFoundationModels(phrase: String, order: Int) async -> InboxSortRule? {
        let system = """
        Output ONLY JSON for an inbox file sort rule. Keys:
        name (string), originDomains (string array, globs like *.stripe.com), destinationRelativePath (string),
        fileKindFilter (any|image|movie|audio|archive|pdf|document),
        contentMatchKind (none|ocrText|receipt).
        No markdown.
        """
        do {
            let session = LanguageModelSession(instructions: system)
            let resp = try await session.respond(to: phrase)
            let text = resp.content
            guard let data = text.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            var rule = InboxSortRule.fresh(order: order)
            if let n = obj["name"] as? String { rule.name = n }
            if let d = obj["destinationRelativePath"] as? String, !d.isEmpty { rule.destinationRelativePath = d }
            if let doms = obj["originDomains"] as? [String] {
                rule.originDomains = doms.map { $0.lowercased() }
            }
            if let fk = obj["fileKindFilter"] as? String, let k = SortFileKindFilter(rawValue: fk) {
                rule.fileKindFilter = k
            }
            if let ck = obj["contentMatchKind"] as? String, let ckEnum = SortContentMatchKind(rawValue: ck) {
                rule.contentMatch = SortContentMatch(kind: ckEnum)
            }
            return rule
        } catch {
            return nil
        }
    }
    #endif
}
