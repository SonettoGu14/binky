import UniformTypeIdentifiers

enum MediaType: Hashable {
    case image
    case pdf
    case video
}

// MARK: - Preset “Applies to” encoding (`CompressionPreset.presetMediaScopeRaw`)

/// Parses and writes `presetMediaScopeRaw`: `"all"`, a single token (`image` / `video` / `pdf`), or comma-separated pairs/triples in canonical order.
enum PresetMediaScopeRawCodec {
    static let allTypes: Set<MediaType> = [.image, .video, .pdf]

    static func includedTypes(from raw: String) -> Set<MediaType> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return allTypes }
        if trimmed == "all" { return allTypes }
        if trimmed.contains(",") {
            var set = Set<MediaType>()
            for part in trimmed.split(separator: ",") {
                let p = part.trimmingCharacters(in: .whitespaces).lowercased()
                if let m = tokenToMedia(p) { set.insert(m) }
            }
            return set.isEmpty ? allTypes : set
        }
        if let m = tokenToMedia(trimmed.lowercased()) {
            return [m]
        }
        return allTypes
    }

    /// Serializes a non-empty subset. Callers must ensure `set` is non-empty.
    static func serialize(_ set: Set<MediaType>) -> String {
        precondition(!set.isEmpty, "preset media scope must include at least one type")
        if set == allTypes { return "all" }
        if set.count == 1, let only = set.first {
            return token(for: only)
        }
        let order: [MediaType] = [.image, .video, .pdf]
        return order.filter { set.contains($0) }.map { token(for: $0) }.joined(separator: ",")
    }

    private static func token(for m: MediaType) -> String {
        switch m {
        case .image: return "image"
        case .video: return "video"
        case .pdf: return "pdf"
        }
    }

    private static func tokenToMedia(_ s: String) -> MediaType? {
        switch s {
        case "image": return .image
        case "video": return .video
        case "pdf": return .pdf
        default: return nil
        }
    }
}

/// Which file types a preset applies to (stored on ``CompressionPreset``).
enum PresetMediaScope: String, CaseIterable, Identifiable {
    case all
    case image
    case video
    case pdf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .image: return "Images"
        case .pdf: return "PDFs"
        case .video: return "Videos"
        }
    }
}

extension MediaType {
    /// Plural label for “applies to” summaries (preset list, sidebar).
    var presetAppliesToSummaryWord: String {
        switch self {
        case .image: return String(localized: "Images", comment: "Preset list: applies to image files.")
        case .video: return String(localized: "Videos", comment: "Preset list: applies to video files.")
        case .pdf: return String(localized: "PDFs", comment: "Preset list: applies to PDF files.")
        }
    }

    /// Singular label for Applies-to multi-select (Image / Video / PDF).
    var presetAppliesToSegmentLabel: String {
        switch self {
        case .image: return String(localized: "Image", comment: "Settings UI: media type segment.")
        case .video: return String(localized: "Video", comment: "Settings UI: media type segment.")
        case .pdf: return String(localized: "PDF", comment: "Settings UI: media type segment.")
        }
    }
}

enum MediaTypeDetector {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "avif", "tiff", "bmp", "heic", "heif", "gif"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi"]

    static func detect(_ url: URL) -> MediaType? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if ext == "pdf" { return .pdf }
        if videoExtensions.contains(ext) { return .video }
        guard let uti = UTType(filenameExtension: ext) else { return nil }
        // MP4/MOV family only — avoids classifying WebM/MKV/etc. as video when AVFoundation export often fails.
        if uti.conforms(to: .mpeg4Movie) || uti.conforms(to: .quickTimeMovie) { return .video }
        if uti.conforms(to: .pdf) { return .pdf }
        if uti.conforms(to: .image) { return .image }
        return nil
    }
}
