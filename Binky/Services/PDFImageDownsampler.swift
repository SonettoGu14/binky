import Foundation
import AppKit
import PDFKit
import CoreGraphics
import ImageIO

/// Mixed-mode PDF: rasterizes image-heavy pages at 144 DPI while keeping text pages from a structure-preserved source.
/// Use in preserve mode when embedded images are over-resoluted (e.g. 300/600 DPI scans in a screen-bound PDF).
enum PDFImageDownsampler {

    /// Pages with fewer text chars than this are treated as image-heavy and rasterized.
    private static let imagePageTextThreshold = 500

    /// 144 DPI — retina-screen quality; halves data vs a 300 DPI scan without visible degradation on screen.
    private static let rasterDPI: CGFloat = 144

    /// High JPEG quality: resolution reduction is the gain, not aggressive lossy compression.
    private static let jpegQuality: CGFloat = 0.72

    /// Returns a mixed PDFDocument, or nil if downsampling produced no benefit.
    /// - Parameters:
    ///   - source:        Original PDF (used to render image pages at full fidelity then downsample).
    ///   - structureDoc:  qpdf-compressed document (used as-is for text pages).
    ///   - stripMetadata: When false, copies PDF document attributes from the source (except author/creator), matching ``PDFCompressor``.
    static func downsample(source: URL, structureDoc: PDFDocument, stripMetadata: Bool) -> PDFDocument? {
        guard let sourceDoc = PDFDocument(url: source) else { return nil }
        let pageCount = sourceDoc.pageCount
        guard pageCount > 0, structureDoc.pageCount == pageCount else { return nil }

        let output = PDFDocument()
        var rasterizedCount = 0

        for i in 0..<pageCount {
            guard let sourcePage = sourceDoc.page(at: i) else { continue }
            let textChars = sourcePage.string?.count ?? 0

            if textChars < imagePageTextThreshold, let rasterPage = rasterize(page: sourcePage) {
                rasterPage.setBounds(sourcePage.bounds(for: .mediaBox), for: .mediaBox)
                output.insert(rasterPage, at: output.pageCount)
                rasterizedCount += 1
            } else if let structPage = structureDoc.page(at: i) {
                output.insert(structPage, at: output.pageCount)
            }
        }

        guard rasterizedCount > 0 else { return nil }
        if !stripMetadata, let attrs = sourceDoc.documentAttributes {
            var safeAttrs = attrs
            safeAttrs.removeValue(forKey: PDFDocumentAttribute.authorAttribute)
            safeAttrs.removeValue(forKey: PDFDocumentAttribute.creatorAttribute)
            output.documentAttributes = safeAttrs
        }
        return output
    }

    private static func rasterize(page: PDFPage) -> PDFPage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let scale = rasterDPI / 72.0
        let pixelWidth = max(1, Int((bounds.width * scale).rounded(.down)))
        let pixelHeight = max(1, Int((bounds.height * scale).rounded(.down)))

        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        let renderScale = CGFloat(pixelWidth) / bounds.width
        ctx.scaleBy(x: renderScale, y: renderScale)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = nsCtx
        page.draw(with: .mediaBox, to: ctx)
        NSGraphicsContext.current = nil

        guard let cgImage = ctx.makeImage() else { return nil }

        let jpegData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(jpegData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
            kCGImageDestinationOptimizeColorForSharing: true,
            kCGImagePropertyJFIFIsProgressive: true,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }

        guard let nsImage = NSImage(data: jpegData as Data) else { return nil }
        return PDFPage(image: nsImage)
    }
}
