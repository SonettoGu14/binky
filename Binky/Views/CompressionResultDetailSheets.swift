import AppKit
import SwiftUI

// MARK: - Error detail sheet

struct CompressionErrorDetailView: View {
    let filename: String
    let error: Error
    @Environment(\.dismiss) private var dismiss

    private var footerTip: String {
        let desc = error.localizedDescription
        if desc.range(of: "sips", options: .caseInsensitive) != nil {
            return String(localized: "Tip: macOS image resizing failed while applying a width limit. Try turning off Limit width in Settings. Bundled encoders (cwebp / avifenc) are usually unrelated.", comment: "Error sheet footer when sips failed.")
        }
        return String(localized: "Tip: check that cwebp / avifenc are present in the app bundle.", comment: "Error sheet footer.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Compression Failed", comment: "Error sheet title."))
                        .font(.headline)
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                Text(error.localizedDescription)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(String(localized: "Email Error…", comment: "Send error by email.")) {
                        NSWorkspace.shared.open(
                            DiagnosticsReporter.emailURL(
                                subject: String(localized: "Error — \(filename)", comment: "Email subject; argument is filename."),
                                extraBody: error.localizedDescription
                            )
                        )
                    }
                    Button(String(localized: "GitHub Issue…", comment: "Open GitHub issue for error.")) {
                        NSWorkspace.shared.open(
                            DiagnosticsReporter.githubIssueURL(
                                title: String(localized: "Error: \(filename)", comment: "Issue title; argument is filename."),
                                extraBody: error.localizedDescription
                            )
                        )
                    }
                    Spacer()
                    Button(String(localized: "Dismiss", comment: "Close sheet.")) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                Text(footerTip)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Skipped detail sheet

struct CompressionSkippedDetailView: View {
    let filename: String
    let savedPercent: Double?
    let threshold: Int
    let onForceCompress: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var headlineText: String {
        if let p = savedPercent {
            return String(format: String(localized: "Would only save %.1f%%", comment: "Skipped detail headline."), p)
        }
        return String(localized: "Already at minimum size", comment: "Skipped detail headline.")
    }

    private var bodyText: String {
        if let p = savedPercent {
            return String(format:
                String(localized: "Binky compressed this file but the result was only %.1f%% smaller — under your %d%% threshold, so the original was kept.\n\nLower the threshold in Settings → General → Skip if savings below to compress files like this automatically, or click Compress Anyway to force this one. (PDFs are not subject to this threshold.)", comment: "Skipped detail body."),
                p, threshold)
        }
        return String(localized: "The encoder couldn't make this file any smaller. It's likely already optimized for its format.\n\nForcing compression won't help here, but you can try a different format (e.g. WebP or AVIF) from the sidebar.", comment: "Skipped detail body.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(headlineText).font(.headline)
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                Text(bodyText)
                    .font(.system(.body))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 220)

            Divider()

            HStack {
                if savedPercent != nil {
                    Button(String(localized: "Compress Anyway", comment: "Force compress from sheet.")) { onForceCompress() }
                }
                Spacer()
                Button(String(localized: "Dismiss", comment: "Close sheet.")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Zero-gain detail sheet

struct CompressionZeroGainDetailView: View {
    let filename: String
    let originalSize: Int64
    let attemptedSize: Int64
    var isPDF: Bool = false
    var pdfOutputMode: PDFOutputMode? = nil
    var onTryFlattenSmallest: (() -> Void)? = nil
    /// Preserve-mode retries with experimental qpdf options (strip structure / stronger images / both).
    var onTryPreserveExperimental: ((PDFPreserveExperimentalMode) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private static let experimentalPreserveRetries: [PDFPreserveExperimentalMode] = [
        .stripNonEssentialStructure, .strongerImageRecompression, .maximum,
    ]

    private var diffText: String {
        let diff = attemptedSize - originalSize
        let mb = Double(abs(diff)) / 1_048_576
        if diff > 0 {
            return String(format: String(localized: "%.2f MB larger", comment: "Comparison: output larger than original."), mb)
        }
        return String(localized: "the same size", comment: "Comparison: file sizes equal.")
    }

    private var attemptedSizePillLabel: String {
        if isPDF, pdfOutputMode == .preserveStructure {
            return String(localized: "Rewrite (not saved)", comment: "Zero-gain sheet: PDFKit temp rewrite size pill.")
        }
        if isPDF, pdfOutputMode == .flattenPages {
            return String(localized: "Flatten attempt (not saved)", comment: "Zero-gain sheet: flatten output pill.")
        }
        return String(localized: "Compressed", comment: "Size pill label.")
    }

    private var explanationText: String {
        if isPDF, pdfOutputMode == .preserveStructure {
            return String(format: String(localized: "A temporary re-save was %@ than your file. That version was discarded — your original was not replaced.\n\nPreserve text and links first runs stream optimization (bundled qpdf), then a PDFKit rewrite if needed. Many modern PDFs are already tightly compressed, so this mode often cannot shrink them further. It is not a guaranteed size optimizer. In the sidebar (or below), you can try Advanced (experimental) passes for a bit more shrink while staying in preserve mode. For reliably smaller files, use “Smallest file (flatten pages)”, or the flatten button below.", comment: "Zero-gain sheet: preserve PDF; first format arg is size phrase."), diffText)
        }
        if isPDF, pdfOutputMode == .flattenPages {
            return String(format: String(localized: "Flattening still produced a file %@ than the original after trying lower quality tiers, so Binky kept the original.\n\nThis PDF may already use efficient images, or pages are very large. You can leave it as-is.", comment: "Zero-gain sheet: flatten PDF still larger; first format arg is size phrase."), diffText)
        }
        if isPDF {
            return String(format: String(localized: "The output was %@ than the original, so Binky kept the original.\n\nTry “Smallest file (flatten pages)” in the sidebar for image-like compression, or leave the file as-is.", comment: "Zero-gain sheet: PDF fallback when mode unknown; first format arg is size phrase."), diffText)
        }
        return String(format: String(localized: "The compressed version was %@ than the original, so Binky kept the original.\n\nThis usually happens with files that are already heavily optimized, or when re-encoding does not suit the content. Try a different format from the sidebar, or leave this file as-is.", comment: "Zero-gain sheet: generic explanation; first format argument is a size phrase."), diffText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "No size gain", comment: "Zero-gain sheet title.")).font(.headline)
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    sizePill(String(localized: "Original", comment: "Size pill label."), value: bytes(originalSize))
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    sizePill(attemptedSizePillLabel, value: bytes(attemptedSize), highlight: true)
                }

                Text(explanationText)
                    .font(.system(.body))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            HStack(alignment: .center, spacing: 10) {
                if let tryFlatten = onTryFlattenSmallest {
                    Button(String(localized: "Try smallest file (flatten)", comment: "Zero-gain sheet: retry PDF as flattened smallest tier.")) {
                        tryFlatten()
                        dismiss()
                    }
                }
                if let onExp = onTryPreserveExperimental, isPDF, pdfOutputMode == .preserveStructure || pdfOutputMode == nil {
                    Menu {
                        ForEach(Self.experimentalPreserveRetries, id: \.rawValue) { mode in
                            Button(mode.displayName) {
                                onExp(mode)
                                dismiss()
                            }
                        }
                    } label: {
                        Text(String(localized: "Try experimental preserve…", comment: "Zero-gain sheet: menu to retry preserve with experimental qpdf options."))
                    }
                }
                Spacer()
                Button(String(localized: "Dismiss", comment: "Close sheet.")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
    }

    private func bytes(_ n: Int64) -> String {
        String(format: String(localized: "%.2f MB", comment: "File size with megabytes unit."), Double(n) / 1_048_576)
    }

    private func sizePill(_ label: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(highlight ? .primary : .secondary)
                .fontWeight(highlight ? .semibold : .regular)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
