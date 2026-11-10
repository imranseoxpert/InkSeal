import Foundation
import AppKit
import PDFKit
import CryptoKit
import SwiftUI
import SystemConfiguration
import UniformTypeIdentifiers

enum Hashing {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(fileAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return sha256(data)
    }
}

enum DeviceInfo {
    static let name: String = {
        if let n = SCDynamicStoreCopyComputerName(nil, nil) as String?, !n.isEmpty { return n }
        return "this Mac"
    }()
}

enum PDFGeometry {
    /// Page size as displayed (rotation applied), in PDF points.
    static func displaySize(_ page: PDFPage) -> CGSize {
        let b = page.bounds(for: .mediaBox)
        let r = ((page.rotation % 360) + 360) % 360
        return r % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
    }
}

/// Runs `body` with a top-left origin, flipped NSGraphicsContext over a PDF/bitmap CGContext.
enum Flipped {
    static func draw(in ctx: CGContext, height: CGFloat, _ body: () -> Void) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }
}

enum ImageExport {
    /// Renders a transparent PNG. Drawing coordinates are top-left origin, in points.
    static func png(size: CGSize, scale: CGFloat = 3, _ draw: (CGContext) -> Void) -> Data? {
        let pw = max(1, Int(ceil(size.width * scale)))
        let ph = max(1, Int(ceil(size.height * scale)))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = base.cgContext
        NSGraphicsContext.saveGraphicsState()
        cg.saveGState()
        cg.clear(CGRect(x: 0, y: 0, width: pw, height: ph))
        cg.translateBy(x: 0, y: CGFloat(ph))
        cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw(cg)
        cg.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        rep.size = size
        return rep.representation(using: .png, properties: [:])
    }
}

func aspectFit(_ content: CGSize, in rect: CGRect) -> CGRect {
    guard content.width > 0, content.height > 0 else { return rect }
    let s = min(rect.width / content.width, rect.height / content.height)
    let w = content.width * s, h = content.height * s
    return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
}

enum FieldStyle {
    /// Font size (points) used for text values inside a field of the given height (points).
    static func fontSize(forHeight h: CGFloat) -> CGFloat { max(6, min(h * 0.62, 13)) }
}

final class PageRenderCache {
    static let shared = PageRenderCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for page: PDFPage, key: String) -> NSImage {
        if let img = cache.object(forKey: key as NSString) { return img }
        let size = PDFGeometry.displaySize(page)
        let width: CGFloat = 1800
        let img = page.thumbnail(of: CGSize(width: width, height: width * size.height / max(size.width, 1)), for: .mediaBox)
        cache.setObject(img, forKey: key as NSString)
        return img
    }

    func removeAll() { cache.removeAllObjects() }
}

// MARK: - AppKit helpers

@MainActor
enum Panels {
    static func choosePDFs() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"
        panel.message = "Choose PDF documents to prepare for signing"
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Image"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func savePDF(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
enum Mailer {
    static func compose(to recipients: [String], subject: String, body: String, attachment: URL) {
        guard let service = NSSharingService(named: .composeEmail) else { return }
        service.recipients = recipients.filter { !$0.isEmpty }
        service.subject = subject
        service.perform(withItems: [body, attachment])
    }
}

extension View {
    func sectionTitleStyle() -> some View {
        self.font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
    }
}
