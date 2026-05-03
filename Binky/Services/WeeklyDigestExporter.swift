import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum WeeklyDigestExporter {

    /// Renders the digest card into an `NSImage` suitable for PNG export.
    static func renderNSImage(from model: WeeklyDigestShareModel, logicalSize: CGSize = CGSize(width: 600, height: 300)) -> NSImage? {
        let scale: CGFloat = 2
        let card = WeeklyDigestShareCard(model: model)
            .frame(width: logicalSize.width, height: logicalSize.height)
        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(logicalSize)
        guard let cg = renderer.cgImage else { return nil }
        let px = CGSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)
        return NSImage(cgImage: cg, size: px)
    }

    /// Returns `true` when PNG data landed on the general pasteboard.
    static func copyPNG(of model: WeeklyDigestShareModel) -> Bool {
        guard let image = renderNSImage(from: model),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:])
        else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(pngData, forType: .png)
        return true
    }

    static func presentSavePNGPanel(for model: WeeklyDigestShareModel) {
        guard let image = renderNSImage(from: model),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:])
        else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Binky-weekly-digest.png"
        panel.prompt = String(localized: "Save", comment: "Weekly digest save panel.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? pngData.write(to: url)
    }
}
