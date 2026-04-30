import Foundation
import os

/// Structured PDF compression outcomes for Console.app (`subsystem`: app bundle id, `category`: `PDFMetrics`).
/// Enable **Debug** for this subsystem to compare runs and validate shrink on fixture documents.
enum PDFCompressionMetrics {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.binky.app",
        category: "PDFMetrics"
    )

    // MARK: - Product / regression expectations (see docs/PDF_COMPRESSION.md)

    /// Interpretation aid: flatten should usually beat the source on typical scan / mixed raster PDFs when Smart Quality or tiers are set sanely.
    /// Not enforced as a runtime gate in Release.
    static let regressionNoteFlattenShouldShrinkTypicalScanPDF = true

    /// Preserve mode may legitimately produce no savings on already-optimized exports; do not treat as a regression by itself.
    static let regressionNotePreserveMayShowNoGain = true

    /// Log line prefix for filtering in Console.
    private static let eventPrefix = "pdf_metrics"

    static func logOutcome(
        outputMode: PDFOutputMode,
        originalBytes: Int64,
        outputBytes: Int64,
        flattenLastResort: Bool,
        flattenUltra: Bool,
        preserveQpdfChain: String? = nil,
        preserveQpdfWinningStep: String? = nil
    ) {
        let saved = originalBytes - outputBytes
        let pct = originalBytes > 0 ? Double(saved) / Double(originalBytes) * 100.0 : 0
        let bailout = flattenUltra ? "ultra" : (flattenLastResort ? "lastResort" : "none")
        if let chain = preserveQpdfChain, let win = preserveQpdfWinningStep {
            log.debug("\(Self.eventPrefix, privacy: .public) outcome mode=\(outputMode.rawValue, privacy: .public) in=\(originalBytes, privacy: .public) out=\(outputBytes, privacy: .public) savedBytes=\(saved, privacy: .public) savedPct=\(String(format: "%.2f", pct), privacy: .public) bailout=\(bailout, privacy: .public) preserveChain=\(chain, privacy: .public) preserveWin=\(win, privacy: .public)")
        } else if let chain = preserveQpdfChain {
            log.debug("\(Self.eventPrefix, privacy: .public) outcome mode=\(outputMode.rawValue, privacy: .public) in=\(originalBytes, privacy: .public) out=\(outputBytes, privacy: .public) savedBytes=\(saved, privacy: .public) savedPct=\(String(format: "%.2f", pct), privacy: .public) bailout=\(bailout, privacy: .public) preserveChain=\(chain, privacy: .public) preserveWin=pdfkit")
        } else {
            log.debug("\(Self.eventPrefix, privacy: .public) outcome mode=\(outputMode.rawValue, privacy: .public) in=\(originalBytes, privacy: .public) out=\(outputBytes, privacy: .public) savedBytes=\(saved, privacy: .public) savedPct=\(String(format: "%.2f", pct), privacy: .public) bailout=\(bailout, privacy: .public)")
        }
    }

    static func logRejectedOutput(
        outputMode: PDFOutputMode,
        originalBytes: Int64,
        attemptedBytes: Int64,
        reason: String
    ) {
        log.debug("\(Self.eventPrefix, privacy: .public) rejected mode=\(outputMode.rawValue, privacy: .public) reason=\(reason, privacy: .public) in=\(originalBytes, privacy: .public) attempted=\(attemptedBytes, privacy: .public)")
    }
}
