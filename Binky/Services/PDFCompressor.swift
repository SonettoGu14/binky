import Foundation
import AppKit
import PDFKit
import CoreGraphics
import ImageIO

/// How PDFs are written: keep structure (text, links, forms) or rasterize pages for maximum shrink.
enum PDFOutputMode: String, CaseIterable, Identifiable {
    case preserveStructure = "preserveStructure"
    case flattenPages = "flattenPages"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .preserveStructure:
            return String(localized: "Preserve text (best-effort size)", comment: "PDF output mode short label.")
        case .flattenPages:
            return String(localized: "Smallest file (flatten pages)", comment: "PDF output mode short label.")
        }
    }

    var shortDescription: String {
        switch self {
        case .preserveStructure:
            return String(localized: "qpdf + PDFKit when smaller; keeps text and links. Many PDFs won’t shrink.", comment: "PDF preserve mode description.")
        case .flattenPages:
            return String(localized: "Rasterizes each page to JPEG for reliable smaller files. No selectable text or links.", comment: "PDF flatten mode description.")
        }
    }
}

enum PDFQuality: String, CaseIterable, Identifiable {
    case smallest = "smallest"
    case low    = "low"
    case medium = "medium"
    case high   = "high"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smallest: return String(localized: "Smallest", comment: "PDF flatten quality tier.")
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    var dpi: CGFloat {
        switch self {
        case .smallest: return 72
        case .low:    return 88
        case .medium: return 120
        case .high:   return 160
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .smallest: return 0.26
        case .low:    return 0.34
        case .medium: return 0.48
        case .high:   return 0.64
        }
    }

    var description: String {
        switch self {
        case .smallest: return String(localized: "Minimum size. 72 DPI — screen sharing and quick previews only.", comment: "PDF flatten quality tier description.")
        case .low:    return String(localized: "Very small. ~88 DPI — fine for screen viewing.", comment: "PDF flatten quality tier description.")
        case .medium: return String(localized: "Balanced. ~120 DPI — good for most purposes.", comment: "PDF flatten quality tier description.")
        case .high:   return String(localized: "Sharper. ~160 DPI — better for print than Medium.", comment: "PDF flatten quality tier description.")
        }
    }

    /// From largest toward smallest output — used to retry flatten when a tier bloats the file.
    private static let flattenTierDescending: [PDFQuality] = [.high, .medium, .low, .smallest]

    /// Tiers to try when flattening, starting at `first` and stepping down until `.smallest`.
    static func flattenQualityFallbackChain(startingAt first: PDFQuality) -> [PDFQuality] {
        guard let i = flattenTierDescending.firstIndex(of: first) else { return [first] }
        return Array(flattenTierDescending[i...])
    }

    /// Starting tiers to show when a max-size target is on: tighter caps hide higher tiers (unlikely to hit the cap on the first pass).
    static func flattenUIShowableTiers(maxFileSizeEnabled: Bool, pdfMaxFileSizeKB: Int) -> [PDFQuality] {
        guard maxFileSizeEnabled else { return PDFQuality.allCases }
        let mb = Double(pdfMaxFileSizeKB) / 1024.0
        if mb <= 6 {
            return [.smallest, .low]
        }
        if mb <= 12 {
            return [.smallest, .low, .medium]
        }
        return [.smallest, .low, .medium, .high]
    }

    /// Picks the nearest allowed starting tier when the current one is hidden (walks down the flatten fallback chain).
    static func snapFlattenStartTier(_ current: PDFQuality, allowed: [PDFQuality]) -> PDFQuality {
        guard !allowed.isEmpty else { return current }
        if allowed.contains(current) { return current }
        for q in flattenQualityFallbackChain(startingAt: current) {
            if allowed.contains(q) { return q }
        }
        return allowed[0]
    }
}

enum PDFCompressor {

    /// Caps flatten rasterization so huge `mediaBox` pages cannot allocate multi‑hundred‑megapixel bitmaps or explode output size.
    /// Tighter than 8K so large physical pages don’t rasterize more pixels than needed for web/screen PDFs.
    private static let flattenMaxRasterEdgePixels = 5632
    /// Tighter cap for the automatic last-resort flatten pass (after normal tiers fail to shrink).
    private static let flattenLastResortMaxRasterEdgePixels = 4096
    /// Strongest automatic bailout when milder flatten tiers still do not beat the source (same color mode as the user chose).
    private static let flattenUltraMaxRasterEdgePixels = 2048

    private static func resourceByteCount(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
    }

    /// Rewrites the PDF without rasterizing: preserves text, annotations, links, and typical form structures.
    /// The result is only committed when it is **smaller** than the source, so a round-trip rewrite never
    /// replaces the user’s file with a larger one.
    static func preserveStructure(
        source: URL,
        stripMetadata: Bool,
        outputURL: URL,
        collisionSourceURL: URL,
        collisionNamingStyle: CollisionNamingStyle,
        collisionCustomPattern: String,
        progress: (@Sendable (Float) -> Void)? = nil
    ) throws -> URL {
        progress?(0.12)
        guard let document = PDFDocument(url: source) else {
            throw PDFCompressionError.loadFailed
        }
        guard document.pageCount > 0 else { throw PDFCompressionError.noPages }

        progress?(0.55)
        if stripMetadata {
            document.documentAttributes = nil
        } else if let attrs = document.documentAttributes {
            var safeAttrs = attrs
            safeAttrs.removeValue(forKey: PDFDocumentAttribute.authorAttribute)
            safeAttrs.removeValue(forKey: PDFDocumentAttribute.creatorAttribute)
            document.documentAttributes = safeAttrs
        }

        progress?(0.82)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("binky_pdf_preserve_\(UUID().uuidString).pdf")
        guard document.write(to: tmp) else {
            throw PDFCompressionError.writeFailed
        }
        let srcBytes = resourceByteCount(source)
        let dstBytes = resourceByteCount(tmp)
        if dstBytes < srcBytes {
            let out = try OutputPathUniqueness.moveTempItemToUniqueOutput(
                temp: tmp,
                desiredOutput: outputURL,
                sourceURL: collisionSourceURL,
                style: collisionNamingStyle,
                customPattern: collisionCustomPattern
            )
            progress?(1)
            return out
        } else {
            try? FileManager.default.removeItem(at: tmp)
            throw PDFCompressionError.rewriteNotSmallerThanOriginal(attemptedSize: dstBytes)
        }
    }

    /// Rasterizes each page to JPEG (legacy “compress” behavior).
    /// - Parameters:
    ///   - lastResortFlatten: Harsher DPI/JPEG/cap after normal tiers could not beat the source size.
    ///   - ultraLastResortFlatten: Strongest profile (lower DPI/JPEG, smaller raster cap). Implies last-resort if both are set.
    static func compressFlattened(
        source: URL,
        quality: PDFQuality,
        grayscale: Bool,
        stripMetadata: Bool,
        outputURL: URL,
        lastResortFlatten: Bool = false,
        ultraLastResortFlatten: Bool = false,
        progress: (@Sendable (Float) -> Void)? = nil
    ) throws {
        progress?(0.06)
        guard let document = PDFDocument(url: source) else {
            throw PDFCompressionError.loadFailed
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else { throw PDFCompressionError.noPages }

        let flattenDpi: CGFloat
        let flattenJpegQ: CGFloat
        let maxEdgePx: CGFloat
        if ultraLastResortFlatten {
            flattenDpi = 36
            flattenJpegQ = 0.17
            maxEdgePx = CGFloat(flattenUltraMaxRasterEdgePixels)
        } else if lastResortFlatten {
            flattenDpi = 48
            flattenJpegQ = 0.23
            maxEdgePx = CGFloat(flattenLastResortMaxRasterEdgePixels)
        } else {
            flattenDpi = quality.dpi
            flattenJpegQ = quality.jpegQuality
            maxEdgePx = CGFloat(flattenMaxRasterEdgePixels)
        }

        progress?(0.1)
        let output = PDFDocument()

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)

            let baseScale = flattenDpi / 72.0
            var rasterW = bounds.width * baseScale
            var rasterH = bounds.height * baseScale
            let longEdge = max(rasterW, rasterH)
            if longEdge > maxEdgePx {
                let factor = maxEdgePx / longEdge
                rasterW *= factor
                rasterH *= factor
            }
            let pixelWidth = max(1, Int(rasterW.rounded(.down)))
            let pixelHeight = max(1, Int(rasterH.rounded(.down)))
            let renderScale = min(CGFloat(pixelWidth) / bounds.width, CGFloat(pixelHeight) / bounds.height)

            // Render page to bitmap (grayscale saves ~60% on B&W documents)
            let colorSpace = grayscale ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = grayscale
                ? CGImageAlphaInfo.none.rawValue
                : CGImageAlphaInfo.noneSkipLast.rawValue
            guard let ctx = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { throw PDFCompressionError.renderFailed(i) }

            ctx.setFillColor(grayscale ? CGColor(gray: 1, alpha: 1) : CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            ctx.scaleBy(x: renderScale, y: renderScale)

            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = nsCtx
            page.draw(with: .mediaBox, to: ctx)
            NSGraphicsContext.current = nil

            guard let cgImage = ctx.makeImage() else { continue }

            // JPEG in memory — avoids disk + extra color-management roundtrip through `NSImage(contentsOf:)`.
            let jpegData = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(jpegData, "public.jpeg" as CFString, 1, nil) else {
                continue
            }
            let opts: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: flattenJpegQ,
                kCGImageDestinationOptimizeColorForSharing: true,
                kCGImagePropertyJFIFIsProgressive: true,
            ]
            CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { continue }

            guard let nsImage = NSImage(data: jpegData as Data),
                  let renderedPage = PDFPage(image: nsImage) else { continue }
            // Restore page bounds to original size (PDFPage from image defaults to pixel size at 72dpi)
            renderedPage.setBounds(bounds, for: .mediaBox)
            output.insert(renderedPage, at: output.pageCount)
            progress?(0.1 + 0.78 * Float(i + 1) / Float(pageCount))
        }

        if stripMetadata {
            // PDFDocument doesn't expose per-attribute stripping; we skip writing
            // the document attributes by not copying them to `output`.
        } else {
            // Copy non-identifying attributes (subject, keywords)
            if let attrs = document.documentAttributes {
                var safeAttrs = attrs
                safeAttrs.removeValue(forKey: PDFDocumentAttribute.authorAttribute)
                safeAttrs.removeValue(forKey: PDFDocumentAttribute.creatorAttribute)
                output.documentAttributes = safeAttrs
            }
        }

        progress?(0.92)
        guard output.write(to: outputURL) else {
            throw PDFCompressionError.writeFailed
        }
        progress?(1)
    }
}

enum PDFCompressionError: LocalizedError {
    case loadFailed
    case noPages
    case renderFailed(Int)
    case writeFailed
    /// PDFKit’s rewrite was not smaller than the source; `attemptedSize` is the would-be output on disk.
    case rewriteNotSmallerThanOriginal(attemptedSize: Int64)

    var errorDescription: String? {
        switch self {
        case .loadFailed:        return "Could not open the PDF file."
        case .noPages:           return "The PDF has no pages."
        case .renderFailed(let p): return "Could not render page \(p + 1)."
        case .writeFailed:       return "Could not write the compressed PDF."
        case .rewriteNotSmallerThanOriginal:
            return String(localized: "Saving the PDF did not reduce its size compared to the original.", comment: "PDF preserve: rewrite was larger or the same size.")
        }
    }
}
