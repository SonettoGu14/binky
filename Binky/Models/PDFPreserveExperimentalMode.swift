import Foundation

/// Optional qpdf passes for **preserve** mode when normal optimization isn’t enough. Experimental: may affect tagged PDFs or image quality.
enum PDFPreserveExperimentalMode: String, CaseIterable, Identifiable, Sendable {
    /// Default: same as before (object streams, flate, `--optimize-images` when supported).
    case none = "none"
    /// Drops structure tree / markup hints (`qpdf --remove-structure`). Can shrink tagged PDFs; accessibility tags may be affected.
    case stripNonEssentialStructure = "stripStructure"
    /// Lower JPEG quality on image recompression (`--jpeg-quality=50` with `--optimize-images`). Visually lossier; may help image-heavy PDFs.
    case strongerImageRecompression = "strongerImages"
    /// Applies both structure strip and stronger image settings.
    case maximum = "maximum"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return String(localized: "Off (default)", comment: "PDF experimental preserve: disabled.")
        case .stripNonEssentialStructure:
            return String(localized: "Strip non-essential structure", comment: "PDF experimental preserve preset name.")
        case .strongerImageRecompression:
            return String(localized: "Stronger image recompression", comment: "PDF experimental preserve preset name.")
        case .maximum:
            return String(localized: "Maximum (both)", comment: "PDF experimental preserve preset name.")
        }
    }

    var shortDescription: String {
        switch self {
        case .none:
            return String(localized: "Standard qpdf + PDFKit preserve path.", comment: "PDF experimental preserve description.")
        case .stripNonEssentialStructure:
            return String(localized: "Removes the PDF structure tree (tagged PDF / markup). Smaller on some exports; screen readers may lose tags.", comment: "PDF experimental preserve description.")
        case .strongerImageRecompression:
            return String(localized: "Recompresses embedded images more aggressively. Can introduce JPEG artifacts.", comment: "PDF experimental preserve description.")
        case .maximum:
            return String(localized: "Structure strip + stronger JPEG. Highest chance of a smaller file; highest risk to fidelity.", comment: "PDF experimental preserve description.")
        }
    }

    /// Extra qpdf arguments after base preserve args (before metadata flags).
    var extraQpdfArgs: [String] {
        switch self {
        case .none:
            return []
        case .stripNonEssentialStructure:
            return ["--remove-structure"]
        case .strongerImageRecompression:
            return ["--jpeg-quality=50"]
        case .maximum:
            return ["--remove-structure", "--jpeg-quality=50"]
        }
    }

    /// When falling back without `--optimize-images`, omit `--jpeg-quality` (it only applies with image optimization).
    var qpdfExtrasWithoutJPEGQuality: [String] {
        extraQpdfArgs.filter { !$0.hasPrefix("--jpeg-quality=") }
    }
}
