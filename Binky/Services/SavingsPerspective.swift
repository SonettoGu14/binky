import Foundation

/// Playful “put it in perspective” lines for bytes saved on disk (order-of-magnitude analogies only).
///
/// Reference heuristics (not precise): ~5 MB per smartphone photo, ~8–10 MB/min for 1080p video at typical bitrates.
enum SavingsPerspective {

    /// Below this, we skip the extra line — savings are too small for a meaningful analogy.
    private static let minMeaningfulBytes: Int64 = 8 * 1024

    /// Returns one icon + localized line for the batch summary, stable for a given `seed` (e.g. `summary.id`).
    static func perspective(savedBytes: Int64, seed: UUID) -> (icon: String, text: String)? {
        guard savedBytes >= minMeaningfulBytes else { return nil }
        let bucket = bucket(for: savedBytes)
        let templates = bucket.templates
        let idx = variationIndex(seed: seed, modulo: templates.count)
        let choice = templates[idx]
        return (choice.icon, choice.text)
    }

    private struct Choice {
        let icon: String
        let text: String
    }

    private enum Bucket {
        case tiny      // < 512 KB
        case small     // … 10 MB
        case medium    // … 100 MB
        case large     // … 1 GB
        case huge      // ≥ 1 GB

        var templates: [Choice] {
            switch self {
            case .tiny:
                return [
                    Choice(
                        icon: "doc.text",
                        text: String(localized: "Small win — about the size of a PDF attachment.", comment: "Batch summary savings perspective; rough size analogy.")
                    ),
                    Choice(
                        icon: "paperclip",
                        text: String(localized: "About the size of a hefty email attachment.", comment: "Batch summary savings perspective; rough size analogy.")
                    ),
                ]
            case .small:
                return [
                    Choice(
                        icon: "photo.stack",
                        text: String(localized: "Roughly in the ballpark of a few high-res photos.", comment: "Batch summary savings perspective; rough size analogy.")
                    ),
                    Choice(
                        icon: "photo.on.rectangle.angled",
                        text: String(localized: "About as much as a handful of smartphone shots.", comment: "Batch summary savings perspective; rough size analogy.")
                    ),
                ]
            case .medium:
                return [
                    Choice(
                        icon: "film",
                        text: String(localized: "About as much data as a short HD clip.", comment: "Batch summary savings perspective; rough size analogy.")
                    ),
                    Choice(
                        icon: "video",
                        text: String(localized: "In the neighborhood of a minute or two of 1080p video.", comment: "Batch summary savings perspective; rough size analogy.")
                    ),
                ]
            case .large:
                return [
                    Choice(
                        icon: "tv",
                        text: String(localized: "Roughly a TV episode or two, size-wise.", comment: "Batch summary savings perspective; rough size analogy.")
                    ),
                    Choice(
                        icon: "play.rectangle",
                        text: String(localized: "About what you'd expect for a feature-length SD rip.", comment: "Batch summary savings perspective; rough size analogy.")
                    ),
                ]
            case .huge:
                return [
                    Choice(
                        icon: "film.stack",
                        text: String(localized: "That's in the neighborhood of a full HD feature film or more.", comment: "Batch summary savings perspective; rough size analogy.")
                    ),
                    Choice(
                        icon: "externaldrive",
                        text: String(localized: "Like freeing up space for a whole season of shows.", comment: "Batch summary savings perspective; rough size analogy.")
                    ),
                ]
            }
        }
    }

    private static func bucket(for bytes: Int64) -> Bucket {
        let halfMB: Int64 = 512 * 1024
        let tenMB: Int64 = 10 * 1024 * 1024
        let hundredMB: Int64 = 100 * 1024 * 1024
        let oneGB: Int64 = 1024 * 1024 * 1024
        switch bytes {
        case ..<halfMB: return .tiny
        case ..<tenMB: return .small
        case ..<hundredMB: return .medium
        case ..<oneGB: return .large
        default: return .huge
        }
    }

    private static func variationIndex(seed: UUID, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        var hash: UInt64 = 1469598103934665603 // FNV-ish offset basis
        withUnsafeBytes(of: seed.uuid) { buf in
            for b in buf {
                hash ^= UInt64(b)
                hash &*= 1099511628211
            }
        }
        return Int(hash % UInt64(modulo))
    }
}
