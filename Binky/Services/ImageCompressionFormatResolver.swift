import Foundation

/// Resolves which ``CompressionFormat`` will be used for an image job — matches
/// ``ContentView.compressImageItem`` (before PNG-source validation).
enum ImageCompressionFormatResolver {

    /// When `classifiedContent` is provided (same run as compression), it is used instead of
    /// classifying again so Smart Quality + Auto format do not double-call ``ContentClassifier``.
    static func resolvedFormat(
        sourceURL: URL,
        formatOverride: CompressionFormat?,
        preset: CompressionPreset?,
        globalAutoFormat: Bool,
        globalSelectedFormat: CompressionFormat,
        classifiedContent: ContentType? = nil
    ) -> CompressionFormat {
        let autoFmt = preset?.autoFormat ?? globalAutoFormat
        var format = formatOverride ?? preset?.format ?? globalSelectedFormat
        if autoFmt, formatOverride == nil {
            let ct = classifiedContent ?? ContentClassifier.classify(sourceURL)
            format = ct == .photo ? .avif : .webp
        }
        return format
    }
}
