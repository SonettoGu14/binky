import Foundation
import PDFKit
import CoreGraphics
import AppKit

/// Threshold on ``PDFDocumentSignals/scanLikelihood`` to treat a document as scan-like for OCR.
enum PDFScanDetection {
    static let ocrLikelihoodThreshold: Double = 0.42
}

/// Cheap signals from a quick PDF sample (same page indices as flatten Smart Quality).
struct PDFDocumentSignals: Sendable {
    let pageCount: Int
    let bytesPerPage: Double
    let avgChromaSpread: Double
    let avgNonWhiteFill: Double
    /// Sum of `PDFPage.string` lengths on sampled pages (text density hint).
    let totalTextCharsSampled: Int

    /// 0...1 — image-heavy / low extractable text vs born-digital text; includes color scans (not just mono).
    var scanLikelihood: Double {
        guard pageCount > 0 else { return 0 }
        let sampled = min(5, pageCount)
        let avgChars = Double(totalTextCharsSampled) / Double(max(1, sampled))
        if avgChars > 120 { return 0 }
        if avgChars > 50 { return 0.08 }
        let bpp = bytesPerPage
        if bpp < 12_000 { return min(0.15, 1.0 - avgChars / 80.0) }
        if bpp > 4_000_000 { return 0.22 }
        let textEmpty = min(1.0, 1.0 - avgChars / 45.0)
        let densityCue = min(1.0, (bpp - 12_000) / 1_100_000)
        let colorBoost = avgChromaSpread > 0.02 ? 0.22 : 0.05
        let monoBoost = monochromeScanLikelihood >= 0.35 ? 0.18 : 0
        return min(1.0, textEmpty * (0.42 + 0.48 * densityCue) + colorBoost + monoBoost)
    }

    /// 0...1 — likely office / fax-style monochrome scan (flatten path may auto-grayscale).
    var monochromeScanLikelihood: Double {
        guard pageCount > 0 else { return 0 }
        // Typical camera scans and color docs have meaningful chroma; B&W text scans do not.
        if avgChromaSpread > 0.022 { return 0 }
        let bpp = bytesPerPage
        if bpp < 35_000 || bpp > 1_200_000 { return 0 }
        // Heavy ink coverage or very empty pages — both common in scans.
        let extremeFill = avgNonWhiteFill < 0.06 || avgNonWhiteFill > 0.88
        if extremeFill { return min(1, 0.55 + (0.022 - avgChromaSpread) * 12) }
        if avgNonWhiteFill < 0.12, avgChromaSpread < 0.015 { return 0.45 }
        return 0
    }
}

/// Shared PDF page sampling for Smart Quality flatten, preserve heuristics, and mono detection.
enum PDFDocumentSampler {

    static func sample(url: URL) -> PDFDocumentSignals? {
        guard let document = PDFDocument(url: url) else { return nil }
        let pageCount = document.pageCount
        guard pageCount > 0 else { return nil }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        let bytesPerPage = Double(fileSize) / Double(pageCount)

        let indices = samplePageIndices(pageCount: pageCount)
        var spreads: [Double] = []
        var fills: [Double] = []
        var textChars = 0

        for i in indices {
            guard let page = document.page(at: i) else { continue }
            if let stats = thumbnailStats(for: page) {
                spreads.append(stats.avgChromaSpread)
                fills.append(stats.nonWhiteFraction)
            }
            textChars += page.string?.count ?? 0
        }

        guard !spreads.isEmpty else { return nil }

        let avgSpread = spreads.reduce(0, +) / Double(spreads.count)
        let avgFill = fills.reduce(0, +) / Double(fills.count)

        return PDFDocumentSignals(
            pageCount: pageCount,
            bytesPerPage: bytesPerPage,
            avgChromaSpread: avgSpread,
            avgNonWhiteFill: avgFill,
            totalTextCharsSampled: textChars
        )
    }

    static func samplePageIndices(pageCount: Int) -> [Int] {
        let cap = 5
        if pageCount <= cap {
            return Array(0..<pageCount)
        }
        var set = Set<Int>()
        set.insert(0)
        set.insert(pageCount - 1)
        set.insert(pageCount / 2)
        set.insert(pageCount / 4)
        set.insert((3 * pageCount) / 4)
        return Array(set).sorted()
    }

    fileprivate struct ThumbStats {
        let avgChromaSpread: Double
        let nonWhiteFraction: Double
    }

    /// Renders a small bitmap and computes cheap color / coverage stats.
    fileprivate static func thumbnailStats(for page: PDFPage) -> ThumbStats? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let maxEdge: CGFloat = 256
        let scale = min(maxEdge / bounds.width, maxEdge / bounds.height, 4)
        let pixelWidth = max(1, Int(bounds.width * scale))
        let pixelHeight = max(1, Int(bounds.height * scale))

        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.scaleBy(x: scale, y: scale)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = nsCtx
        page.draw(with: .mediaBox, to: ctx)
        NSGraphicsContext.current = nil

        guard let data = ctx.data else { return nil }
        let count = pixelWidth * pixelHeight
        let ptr = data.bindMemory(to: UInt8.self, capacity: count * 4)

        var sumSpread = 0.0
        var nonWhite = 0
        let step = 4
        var samples = 0

        for i in stride(from: 0, to: count, by: step) {
            let o = i * 4
            let r = Double(ptr[o]) / 255
            let g = Double(ptr[o + 1]) / 255
            let b = Double(ptr[o + 2]) / 255
            let mx = max(r, g, b)
            let mn = min(r, g, b)
            sumSpread += mx - mn
            if r + g + b < 2.55 {
                nonWhite += 1
            }
            samples += 1
        }

        guard samples > 0 else { return nil }
        let avgSpread = sumSpread / Double(samples)
        let fill = Double(nonWhite) / Double(samples)
        return ThumbStats(avgChromaSpread: avgSpread, nonWhiteFraction: fill)
    }
}
