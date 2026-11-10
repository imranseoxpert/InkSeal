import AppKit
import PDFKit

/// Produces the sealed, completed PDF: original pages with values burned in + certificate of completion.
enum PDFFinalizer {
    static func render(original: PDFDocument, doc: SignDocument) -> Data {
        let data = NSMutableData()
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let info: [String: Any] = [
            kCGPDFContextTitle as String: doc.title,
            kCGPDFContextCreator as String: "InkSeal",
            kCGPDFContextSubject as String: "Envelope \(doc.id.uuidString)",
        ]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &defaultBox, info as CFDictionary) else {
            return Data()
        }

        for index in 0..<original.pageCount {
            guard let page = original.page(at: index) else { continue }
            let size = PDFGeometry.displaySize(page)
            var box = CGRect(origin: .zero, size: size)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            ctx.saveGState()
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
            Flipped.draw(in: ctx, height: size.height) {
                for field in doc.fields where field.page == index {
                    FieldPainter.paint(field, in: field.rect.rect(in: size), doc: doc)
                }
            }
            ctx.endPDFPage()
        }

        CertificateWriter(ctx: ctx, doc: doc).write()
        ctx.closePDF()
        return data as Data
    }
}

/// Draws a field's value. Expects a flipped (top-left origin) current NSGraphicsContext.
enum FieldPainter {
    static func paint(_ field: DocField, in r: CGRect, doc: SignDocument) {
        switch field.kind {
        case .signature, .initials:
            guard let data = field.imageData, let image = NSImage(data: data) else { return }
            var area = r
            if field.kind == .signature && r.height >= 30 {
                let frameColor = NSColor(srgbRed: 0.16, green: 0.3, blue: 0.62, alpha: 1)
                let caption: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 5, weight: .medium),
                                                              .foregroundColor: frameColor]
                NSAttributedString(string: "InkSeal signed by:", attributes: caption)
                    .draw(at: CGPoint(x: r.minX + 4, y: r.minY))
                let shortID = String(field.recipientID.uuidString.replacingOccurrences(of: "-", with: "").prefix(16))
                NSAttributedString(string: shortID, attributes: caption)
                    .draw(at: CGPoint(x: r.minX + 4, y: r.maxY - 6))
                frameColor.setStroke()
                let bracket = NSBezierPath()
                bracket.lineWidth = 0.8
                bracket.move(to: CGPoint(x: r.minX + 10, y: r.minY + 7))
                bracket.line(to: CGPoint(x: r.minX + 1, y: r.minY + 7))
                bracket.line(to: CGPoint(x: r.minX + 1, y: r.maxY - 7))
                bracket.line(to: CGPoint(x: r.minX + 10, y: r.maxY - 7))
                bracket.stroke()
                area = CGRect(x: r.minX + 4, y: r.minY + 7, width: r.width - 4, height: r.height - 14)
            }
            let fitted = aspectFit(image.size, in: area)
            image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        case .checkbox:
            let side = min(r.width, r.height)
            let box = CGRect(x: r.minX, y: r.midY - side / 2, width: side, height: side).insetBy(dx: 0.5, dy: 0.5)
            NSColor.black.setStroke()
            let border = NSBezierPath(rect: box)
            border.lineWidth = 0.8
            border.stroke()
            if field.checked {
                let check = NSBezierPath()
                check.lineWidth = max(1, side * 0.12)
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: CGPoint(x: box.minX + box.width * 0.2, y: box.minY + box.height * 0.55))
                check.line(to: CGPoint(x: box.minX + box.width * 0.42, y: box.minY + box.height * 0.78))
                check.line(to: CGPoint(x: box.minX + box.width * 0.82, y: box.minY + box.height * 0.24))
                check.stroke()
            }

        default:
            let text = (field.textValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let font = NSFont.systemFont(ofSize: FieldStyle.fontSize(forHeight: r.height))
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black,
                                                                  .paragraphStyle: style])
            let h = s.size().height
            s.draw(with: CGRect(x: r.minX + 2, y: r.midY - h / 2, width: r.width - 4, height: h),
                   options: [.usesLineFragmentOrigin])
        }
    }
}

/// Writes the "Certificate of Completion" pages (summary, signers, audit trail).
final class CertificateWriter {
    private let ctx: CGContext
    private let doc: SignDocument
    private let pageSize = CGSize(width: 612, height: 792)
    private let margin: CGFloat = 50
    private var y: CGFloat = 0
    private var pageOpen = false
    private var pageNumber = 0
    private let navy = NSColor(srgbRed: 0.1, green: 0.15, blue: 0.27, alpha: 1)

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    init(ctx: CGContext, doc: SignDocument) {
        self.ctx = ctx
        self.doc = doc
    }

    private var contentWidth: CGFloat { pageSize.width - margin * 2 }

    func write() {
        newPage(first: true)

        section("Envelope Summary")
        let rows: [(String, String)] = [
            ("Document", doc.title),
            ("Envelope ID", doc.id.uuidString),
            ("Status", "Completed"),
            ("Pages", "\(doc.pageCount) document page\(doc.pageCount == 1 ? "" : "s") + certificate"),
            ("Created", dateFormatter.string(from: doc.createdAt)),
            ("Completed", dateFormatter.string(from: doc.completedAt ?? Date())),
            ("Time zone", TimeZone.current.identifier),
            ("Original SHA-256", doc.originalHash),
        ]
        for (k, v) in rows { keyValue(k, v) }
        y += 10

        section("Recipients")
        for (i, r) in doc.recipients.enumerated() { recipientBlock(r, order: i + 1) }
        y += 6

        section("Audit Trail")
        auditHeader()
        for e in doc.audit { auditRow(e) }

        y += 16
        ensure(40)
        _ = text("This certificate was generated by InkSeal on \(DeviceInfo.name). The SHA-256 fingerprint above identifies the original document that was presented to every recipient.",
                 font: .systemFont(ofSize: 7.5), color: .darkGray, x: margin, width: contentWidth)
        endPage()
    }

    // MARK: Layout primitives

    private func newPage(first: Bool = false) {
        if pageOpen { endPage() }
        ctx.beginPDFPage(nil)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: pageSize.height)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        pageOpen = true
        pageNumber += 1

        let bandHeight: CGFloat = first ? 92 : 44
        navy.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: pageSize.width, height: bandHeight)).fill()
        if first {
            _ = text("Certificate of Completion", font: .systemFont(ofSize: 22, weight: .semibold),
                     color: .white, x: margin, width: contentWidth, at: 28)
            _ = text("InkSeal · Electronic Signature Record", font: .systemFont(ofSize: 10),
                     color: NSColor(white: 1, alpha: 0.7), x: margin, width: contentWidth, at: 58)
        } else {
            _ = text("Certificate of Completion (continued)", font: .systemFont(ofSize: 12, weight: .semibold),
                     color: .white, x: margin, width: contentWidth, at: 15)
        }
        y = bandHeight + 24
    }

    private func endPage() {
        guard pageOpen else { return }
        let footer = "Envelope \(doc.id.uuidString)  ·  Certificate page \(pageNumber)"
        _ = text(footer, font: .systemFont(ofSize: 7), color: .gray, x: margin, width: contentWidth,
                 at: pageSize.height - 30)
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
        ctx.endPDFPage()
        pageOpen = false
    }

    private func ensure(_ height: CGFloat) {
        if y + height > pageSize.height - margin - 10 { newPage() }
    }

    private func measure(_ s: String, font: NSFont, width: CGFloat) -> CGFloat {
        let a = NSAttributedString(string: s, attributes: [.font: font])
        return ceil(a.boundingRect(with: CGSize(width: width, height: 10_000),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    @discardableResult
    private func text(_ s: String, font: NSFont, color: NSColor = .black, x: CGFloat, width: CGFloat,
                      at yPos: CGFloat? = nil) -> CGFloat {
        let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let h = measure(s, font: font, width: width)
        a.draw(with: CGRect(x: x, y: yPos ?? y, width: width, height: h),
               options: [.usesLineFragmentOrigin, .usesFontLeading])
        return h
    }

    private func section(_ title: String) {
        ensure(40)
        _ = text(title.uppercased(), font: .systemFont(ofSize: 9, weight: .bold), color: navy,
                 x: margin, width: contentWidth)
        y += 14
        NSColor(white: 0.82, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 0.7)).fill()
        y += 8
    }

    private func keyValue(_ key: String, _ value: String) {
        let keyWidth: CGFloat = 120
        let valueFont: NSFont = key.contains("SHA") || key.contains("ID")
            ? .monospacedSystemFont(ofSize: 8.5, weight: .regular) : .systemFont(ofSize: 9.5)
        let h = max(measure(value, font: valueFont, width: contentWidth - keyWidth), 12)
        ensure(h + 4)
        text(key, font: .systemFont(ofSize: 9.5, weight: .medium), color: .darkGray, x: margin, width: keyWidth)
        text(value, font: valueFont, x: margin + keyWidth, width: contentWidth - keyWidth)
        y += h + 4
    }

    private func recipientBlock(_ r: Recipient, order: Int) {
        let blockHeight: CGFloat = 62
        ensure(blockHeight + 6)
        let top = y
        NSColor(white: 0.965, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: margin, y: top, width: contentWidth, height: blockHeight),
                     xRadius: 6, yRadius: 6).fill()

        let left = margin + 12
        text("\(order). \(r.displayName)", font: .systemFont(ofSize: 10.5, weight: .semibold),
             x: left, width: 220, at: top + 9)
        text(r.email.isEmpty ? "No email on file" : r.email, font: .systemFont(ofSize: 8.5), color: .darkGray,
             x: left, width: 220, at: top + 25)
        let role = r.roleName.isEmpty ? r.role.title : "\(r.roleName) · \(r.role.title)"
        text(role, font: .systemFont(ofSize: 8.5), color: .gray, x: left, width: 220, at: top + 39)

        let mid = margin + 240
        let status: String
        if let signed = r.signedAt {
            status = "\(r.role == .approver ? "Approved" : "Signed") \(dateFormatter.string(from: signed))"
        } else {
            status = r.role == .viewer ? "Copy delivered on completion" : "Not signed"
        }
        text(status, font: .systemFont(ofSize: 8.5, weight: .medium), x: mid, width: 150, at: top + 11)
        if r.signedAt != nil {
            text("Method: in person on \(DeviceInfo.name)", font: .systemFont(ofSize: 7.5), color: .gray,
                 x: mid, width: 150, at: top + 36)
        }

        let sigData = r.signature ?? doc.fields.first { $0.recipientID == r.id && $0.kind == .signature }?.imageData
        if let sigData, let image = NSImage(data: sigData) {
            let box = CGRect(x: margin + contentWidth - 130, y: top + 8, width: 118, height: blockHeight - 16)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            image.draw(in: aspectFit(image.size, in: box.insetBy(dx: 6, dy: 4)), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        y = top + blockHeight + 6
    }

    private let columns: [CGFloat] = [118, 140, 70]

    private func auditHeader() {
        ensure(20)
        let font = NSFont.systemFont(ofSize: 8, weight: .bold)
        var x = margin
        for (title, w) in zip(["Date & Time", "Actor", "Action"], columns) {
            text(title, font: font, color: .darkGray, x: x, width: w)
            x += w + 8
        }
        text("Details", font: font, color: .darkGray, x: x, width: contentWidth - (x - margin))
        y += 14
    }

    private func auditRow(_ e: AuditEvent) {
        let font = NSFont.systemFont(ofSize: 8)
        let detailX = margin + columns.reduce(0, +) + 24
        let detailWidth = contentWidth - (detailX - margin)
        let values = [dateFormatter.string(from: e.date), e.actor, e.action]
        var h = measure(e.detail, font: font, width: detailWidth)
        for (v, w) in zip(values, columns) { h = max(h, measure(v, font: font, width: w)) }
        let pageBefore = pageNumber
        ensure(h + 8)
        if pageNumber != pageBefore { auditHeader() }
        var x = margin
        for (i, (v, w)) in zip(values, columns).enumerated() {
            text(v, font: i == 2 ? .systemFont(ofSize: 8, weight: .semibold) : font, x: x, width: w)
            x += w + 8
        }
        text(e.detail, font: font, color: .darkGray, x: detailX, width: detailWidth)
        y += h + 4
        NSColor(white: 0.9, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 0.5)).fill()
        y += 4
    }
}
