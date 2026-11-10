import AppKit

// MARK: - Starter templates

struct DocumentTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let summary: String
    let title: String
    let parties: [String]
    let body: String

    static let all: [DocumentTemplate] = [
        DocumentTemplate(
            id: "blank", name: "Blank Document", symbol: "doc", summary: "Write anything from scratch",
            title: "", parties: ["Signer"], body: ""),
        DocumentTemplate(
            id: "nda", name: "Mutual NDA", symbol: "lock.doc", summary: "Keep shared information confidential",
            title: "Mutual Non-Disclosure Agreement", parties: ["First Party", "Second Party"],
            body: """
            This Mutual Non-Disclosure Agreement (the "Agreement") is entered into as of [Effective Date] by and between [First Party Name] and [Second Party Name] (each a "Party").

            ## 1. Purpose
            The Parties wish to explore [describe the business opportunity] (the "Purpose") and may disclose confidential information to each other for that Purpose.

            ## 2. Confidential Information
            "Confidential Information" means any non-public business, technical or financial information disclosed by one Party to the other, in any form, that is marked confidential or would reasonably be understood to be confidential.

            ## 3. Obligations
            Each Party will (a) use the other Party's Confidential Information only for the Purpose, (b) not disclose it to any third party except employees and advisors who need to know and are bound by similar obligations, and (c) protect it with at least reasonable care.

            ## 4. Exclusions
            These obligations do not apply to information that is or becomes public through no fault of the receiving Party, was already known to it, is independently developed, or is rightfully received from a third party without restriction.

            ## 5. Term
            This Agreement remains in effect for [two (2)] years from the Effective Date. Obligations for information disclosed during the term survive for [three (3)] years after termination.

            ## 6. Return of Materials
            On request, each Party will promptly return or destroy the other Party's Confidential Information.

            ## 7. General
            This Agreement is governed by the laws of [Jurisdiction]. It is the entire agreement on this subject and may be amended only in writing signed by both Parties.
            """),
        DocumentTemplate(
            id: "services", name: "Services Agreement", symbol: "briefcase", summary: "Freelance or consulting work",
            title: "Independent Services Agreement", parties: ["Client", "Contractor"],
            body: """
            This Services Agreement is made on [Date] between [Client Name] ("Client") and [Contractor Name] ("Contractor").

            ## 1. Services
            Contractor will provide the following services: [describe deliverables, milestones and acceptance criteria].

            ## 2. Fees and Payment
            Client will pay Contractor [amount / hourly rate]. Contractor will invoice [monthly / on milestone completion] and Client will pay within [15] days of receiving each invoice.

            ## 3. Timeline
            Work begins on [Start Date] and is expected to be completed by [End Date], unless extended in writing.

            ## 4. Intellectual Property
            On full payment, all deliverables created specifically for Client under this Agreement are assigned to Client. Contractor keeps ownership of pre-existing tools and know-how.

            ## 5. Independent Contractor
            Contractor is an independent contractor and is responsible for their own taxes, equipment and insurance.

            ## 6. Confidentiality
            Contractor will keep Client's non-public information confidential during and after this engagement.

            ## 7. Termination
            Either party may terminate with [14] days' written notice. Client will pay for work performed up to the termination date.
            """),
        DocumentTemplate(
            id: "offer", name: "Offer Letter", symbol: "person.badge.plus", summary: "Extend a job offer",
            title: "Offer of Employment", parties: ["Company Representative", "Candidate"],
            body: """
            Dear [Candidate Name],

            We are delighted to offer you the position of [Job Title] at [Company Name], reporting to [Manager Name]. We were impressed by your experience and believe you will be a great addition to the team.

            ## Start Date and Location
            Your anticipated start date is [Start Date]. You will work from [Office Location / Remote].

            ## Compensation
            Your annual base salary will be [Amount], paid [bi-weekly / monthly] in accordance with the Company's payroll practices.

            ## Benefits
            You will be eligible for the Company's standard benefits, including [health insurance, paid time off, retirement plan], subject to the terms of each plan.

            ## At-Will Employment
            Your employment is at-will, meaning either you or the Company may end it at any time, with or without cause or notice, subject to applicable law.

            ## Conditions
            This offer is contingent on [background check / proof of eligibility to work].

            Please sign below to accept this offer by [Offer Expiry Date]. We look forward to working with you.
            """),
        DocumentTemplate(
            id: "lease", name: "Lease Agreement", symbol: "house", summary: "Residential rental terms",
            title: "Residential Lease Agreement", parties: ["Landlord", "Tenant"],
            body: """
            This Lease Agreement is made on [Date] between [Landlord Name] ("Landlord") and [Tenant Name] ("Tenant") for the property located at [Property Address] (the "Premises").

            ## 1. Term
            The lease begins on [Start Date] and ends on [End Date].

            ## 2. Rent
            Tenant will pay rent of [Amount] per month, due on the [1st] day of each month, by [payment method]. A late fee of [Amount] applies after [5] days.

            ## 3. Security Deposit
            Tenant will pay a security deposit of [Amount], which will be returned within [30] days after move-out, less lawful deductions for damage beyond normal wear and tear.

            ## 4. Utilities
            Tenant is responsible for [list utilities]. Landlord is responsible for [list utilities].

            ## 5. Use and Occupancy
            The Premises will be used only as a private residence for the Tenant and [number] occupants. No subletting without Landlord's written consent.

            ## 6. Maintenance
            Tenant will keep the Premises clean and report needed repairs promptly. Landlord will handle structural and major system repairs.

            ## 7. Entry
            Landlord may enter with [24] hours' notice, except in emergencies.
            """),
        DocumentTemplate(
            id: "sale", name: "Bill of Sale", symbol: "cart", summary: "Transfer ownership of an item",
            title: "Bill of Sale", parties: ["Seller", "Buyer"],
            body: """
            For the sum of [Amount] (the "Purchase Price"), received on [Date], [Seller Name] ("Seller") sells and transfers to [Buyer Name] ("Buyer") the following property:

            ## Description of Property
            [Item description, make, model, serial number / VIN, condition]

            ## Condition
            The property is sold "as is", without warranties of any kind, except that Seller confirms they are the lawful owner, the property is free of liens and encumbrances, and they have the right to sell it.

            ## Payment
            Buyer has paid the Purchase Price in full by [payment method].

            ## Transfer
            Ownership and risk of loss transfer to Buyer on the date of signing.
            """),
    ]
}

// MARK: - Text → PDF

struct ComposedField {
    let party: Int
    let kind: FieldKind
    let page: Int
    let rect: NormRect
}

struct ComposedPDF {
    let data: Data
    let fields: [ComposedField]
}

/// Turns plain text (with `## ` headings) into a paginated Letter-size PDF, followed by signature blocks.
enum PDFComposer {
    static let pageWidth: CGFloat = 612
    static let pageHeight: CGFloat = 792
    static let margin: CGFloat = 72

    static func compose(title: String, body: String, parties: [String]) -> ComposedPDF {
        let W = pageWidth, H = pageHeight, M = margin

        let storage = NSTextStorage(attributedString: attributed(title: title, body: body))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var containers: [NSTextContainer] = []
        repeat {
            let c = NSTextContainer(size: CGSize(width: W - 2 * M, height: H - 2 * M))
            c.lineFragmentPadding = 0
            layout.addTextContainer(c)
            containers.append(c)
            let range = layout.glyphRange(for: c)
            if NSMaxRange(range) >= layout.numberOfGlyphs || range.length == 0 { break }
        } while containers.count < 400

        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: W, height: H)
        let info: [String: Any] = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "InkSeal"]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else {
            return ComposedPDF(data: Data(), fields: [])
        }

        var cursor = M
        for (i, container) in containers.enumerated() {
            ctx.beginPDFPage(nil)
            Flipped.draw(in: ctx, height: H) {
                let range = layout.glyphRange(for: container)
                layout.drawBackground(forGlyphRange: range, at: CGPoint(x: M, y: M))
                layout.drawGlyphs(forGlyphRange: range, at: CGPoint(x: M, y: M))
                if i == containers.count - 1 {
                    cursor = M + layout.usedRect(for: container).maxY
                }
            }
            if i < containers.count - 1 { ctx.endPDFPage() }
        }

        var pageIndex = containers.count - 1
        var fields: [ComposedField] = []
        let names = parties.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if !names.isEmpty {
            let blockHeight: CGFloat = 136
            let columnWidth: CGFloat = 220
            let gap: CGFloat = 28
            var top = cursor + 34
            if top + 22 + blockHeight > H - M {
                ctx.endPDFPage()
                ctx.beginPDFPage(nil)
                pageIndex += 1
                top = M
            }
            Flipped.draw(in: ctx, height: H) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: NSColor(white: 0.35, alpha: 1),
                    .kern: 1.2,
                ]
                NSAttributedString(string: "SIGNATURES", attributes: attrs).draw(at: CGPoint(x: M, y: top))
                NSColor(white: 0.8, alpha: 1).setFill()
                NSBezierPath(rect: CGRect(x: M, y: top + 14, width: W - 2 * M, height: 0.6)).fill()
            }
            top += 26
            for row in stride(from: 0, to: names.count, by: 2) {
                if top + blockHeight > H - M {
                    ctx.endPDFPage()
                    ctx.beginPDFPage(nil)
                    pageIndex += 1
                    top = M
                }
                let page = pageIndex
                let rowTop = top
                Flipped.draw(in: ctx, height: H) {
                    for col in 0..<2 {
                        let idx = row + col
                        guard idx < names.count else { continue }
                        let x = M + CGFloat(col) * (columnWidth + gap)
                        fields += signatureBlock(party: names[idx], index: idx, x: x, top: rowTop,
                                                 width: columnWidth, page: page)
                    }
                }
                top += blockHeight
            }
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return ComposedPDF(data: data as Data, fields: fields)
    }

    private static func signatureBlock(party: String, index: Int, x: CGFloat, top: CGFloat,
                                       width: CGFloat, page: Int) -> [ComposedField] {
        let W = pageWidth, H = pageHeight
        func norm(_ r: CGRect) -> NormRect { NormRect(x: r.minX / W, y: r.minY / H, w: r.width / W, h: r.height / H) }
        func line(_ x1: CGFloat, _ x2: CGFloat, _ y: CGFloat) {
            NSColor(white: 0.25, alpha: 1).setFill()
            NSBezierPath(rect: CGRect(x: x1, y: y, width: x2 - x1, height: 0.7)).fill()
        }
        let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8.5, weight: .semibold),
                                                    .foregroundColor: NSColor(white: 0.3, alpha: 1)]
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 7.5),
                                                    .foregroundColor: NSColor(white: 0.45, alpha: 1)]

        NSAttributedString(string: party.uppercased(), attributes: label).draw(at: CGPoint(x: x, y: top))

        let sigRect = CGRect(x: x, y: top + 14, width: width - 20, height: 44)
        line(x, x + width, sigRect.maxY + 1)
        NSAttributedString(string: "Signature", attributes: small).draw(at: CGPoint(x: x, y: sigRect.maxY + 4))

        let nameRect = CGRect(x: x + 36, y: top + 78, width: width - 36, height: 18)
        NSAttributedString(string: "Name:", attributes: small).draw(at: CGPoint(x: x, y: nameRect.minY + 6))
        line(nameRect.minX, x + width, nameRect.maxY + 1)

        let dateRect = CGRect(x: x + 36, y: top + 104, width: 130, height: 18)
        NSAttributedString(string: "Date:", attributes: small).draw(at: CGPoint(x: x, y: dateRect.minY + 6))
        line(dateRect.minX, x + width, dateRect.maxY + 1)

        return [
            ComposedField(party: index, kind: .signature, page: page, rect: norm(sigRect)),
            ComposedField(party: index, kind: .fullName, page: page, rect: norm(nameRect)),
            ComposedField(party: index, kind: .dateSigned, page: page, rect: norm(dateRect)),
        ]
    }

    private static func attributed(title: String, body: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let bodyFont = NSFont(name: "Charter-Roman", size: 11.5) ?? NSFont.systemFont(ofSize: 11.5)
        let headingFont = NSFont(name: "Charter-Bold", size: 12.5) ?? NSFont.boldSystemFont(ofSize: 12.5)
        let titleFont = NSFont(name: "Charter-Bold", size: 21) ?? NSFont.boldSystemFont(ofSize: 21)

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        titleStyle.paragraphSpacing = 22

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = 2.5
        bodyStyle.paragraphSpacing = 7

        let headingStyle = NSMutableParagraphStyle()
        headingStyle.paragraphSpacingBefore = 8
        headingStyle.paragraphSpacing = 4

        let ink = NSColor.black
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        if !trimmedTitle.isEmpty {
            out.append(NSAttributedString(string: trimmedTitle + "\n",
                                          attributes: [.font: titleFont, .paragraphStyle: titleStyle, .foregroundColor: ink]))
        }
        let lines = body.components(separatedBy: .newlines)
        for (i, raw) in lines.enumerated() {
            let newline = i == lines.count - 1 ? "" : "\n"
            if raw.hasPrefix("## ") {
                out.append(NSAttributedString(string: String(raw.dropFirst(3)) + newline,
                                              attributes: [.font: headingFont, .paragraphStyle: headingStyle, .foregroundColor: ink]))
            } else {
                out.append(NSAttributedString(string: raw + newline,
                                              attributes: [.font: bodyFont, .paragraphStyle: bodyStyle, .foregroundColor: ink]))
            }
        }
        return out
    }
}
