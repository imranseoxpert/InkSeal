import SwiftUI
import PDFKit
import AppKit

struct DocumentWorkspace: View {
    @EnvironmentObject private var store: DocumentStore
    let id: UUID

    var body: some View {
        if let binding = store.binding(for: id) {
            WorkspaceContent(doc: binding)
        } else {
            ContentUnavailableView("Document not found", systemImage: "questionmark.folder")
        }
    }
}

private struct WorkspaceContent: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var doc: SignDocument

    @State private var zoom: CGFloat = 1
    @State private var signing: SigningRequest?
    @State private var alertMessage: String?
    @State private var showVoid = false
    @State private var voidReason = ""
    @State private var shareURL: URL?

    private var editable: Bool { doc.isTemplate || doc.status == .draft }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(item: $signing) { req in
            SigningSessionView(doc: $doc, recipientID: req.id)
                .environmentObject(store)
        }
        .alert("InkSeal", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("Void this document?", isPresented: $showVoid) {
            TextField("Reason", text: $voidReason)
            Button("Void", role: .destructive) { store.void(doc.id, reason: voidReason) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recipients who haven't signed will no longer be able to sign.")
        }
        .task(id: doc.status) {
            shareURL = doc.status == .completed ? store.shareableCopy(of: doc) : nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if editable {
                    TextField("Untitled Document", text: $doc.title)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                } else {
                    Text(doc.title).font(.title2.weight(.semibold)).lineLimit(1)
                }
                HStack(spacing: 8) {
                    StatusPill(doc: doc)
                    Text(doc.statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 16)
            if doc.status != .completed {
                HStack(spacing: 2) {
                    Button { zoom = max(0.6, zoom - 0.15) } label: { Image(systemName: "minus.magnifyingglass") }
                        .help("Zoom Out")
                    Button { zoom = 1 } label: { Text("\(Int(zoom * 100))%").monospacedDigit().frame(width: 42) }
                        .help("Actual Size")
                    Button { zoom = min(2, zoom + 0.15) } label: { Image(systemName: "plus.magnifyingglass") }
                        .help("Zoom In")
                }
                .buttonStyle(.borderless)
            }
            actions
            moreMenu
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder private var actions: some View {
        if doc.isTemplate {
            Button { useTemplate() } label: { Label("Use Template", systemImage: "doc.badge.plus") }
                .buttonStyle(.borderedProminent)
        } else {
            switch doc.status {
            case .draft:
                if isSoloSigning {
                    Button { signNow() } label: { Label("Sign Now", systemImage: "signature") }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { sendForSigning() } label: { Label("Send for Signing", systemImage: "paperplane.fill") }
                        .buttonStyle(.borderedProminent)
                }
            case .sent:
                Button { emailSigners() } label: { Label("Email", systemImage: "envelope") }
                if let next = doc.nextSigner {
                    Button { signing = SigningRequest(id: next.id) } label: {
                        Label("Sign as \(next.displayName)", systemImage: "signature")
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .completed:
                Button { exportPDF() } label: { Label("Export PDF", systemImage: "square.and.arrow.down") }
                if let shareURL {
                    ShareLink(item: shareURL) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Button { emailCompleted() } label: { Label("Email Copy", systemImage: "envelope") }
                    .buttonStyle(.borderedProminent)
            case .voided:
                Button { duplicate() } label: { Label("Create a Copy", systemImage: "doc.on.doc") }
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if doc.status == .completed {
                Button("Open in Preview") { NSWorkspace.shared.open(store.completedURL(doc.id)) }
                Button("Verify Integrity") { verify() }
                Divider()
            }
            if doc.status == .draft && !doc.isTemplate {
                Button("Send for Signing") { sendForSigning() }
                Button("Sign Now (in person)") { signNow() }
                Divider()
            }
            if !doc.isTemplate { Button("Duplicate") { duplicate() } }
            Button("Save as Template") { saveAsTemplate() }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([store.displayURL(for: doc)])
            }
            if doc.status == .sent {
                Divider()
                Button("Void Document…", role: .destructive) { showVoid = true }
            }
            Divider()
            Button("Delete…", role: .destructive) { store.pendingDelete = doc.id }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if editable {
            DocumentEditorView(doc: $doc, zoom: zoom)
        } else if doc.status == .completed {
            HStack(spacing: 0) {
                PDFKitView(url: store.displayURL(for: doc))
                Divider()
                EnvelopePanel(doc: doc).frame(width: 320)
            }
        } else {
            HStack(spacing: 0) {
                trackingCanvas
                Divider()
                EnvelopePanel(doc: doc).frame(width: 320)
            }
        }
    }

    @ViewBuilder private var trackingCanvas: some View {
        if let pdf = store.pdf(for: doc) {
            PagesCanvas(pdf: pdf, cacheKey: "\(doc.id.uuidString)-original", zoom: zoom) { index, size, points in
                ZStack(alignment: .topLeading) {
                    ForEach(doc.fields.filter { $0.page == index }) { field in
                        let owner = doc.recipient(field.recipientID)
                        SigningFieldBox(field: .constant(field), color: owner?.color ?? .gray, isActive: false,
                                        ownerName: owner?.displayName ?? "", pageSize: size,
                                        scale: size.width / max(points.width, 1))
                    }
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
            }
        } else {
            ContentUnavailableView("Can't open this PDF", systemImage: "exclamationmark.triangle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Actions

    private var isSoloSigning: Bool {
        doc.recipients.count <= 1 && (doc.recipients.first?.role ?? .signer) == .signer
    }

    private func validationError() -> String? {
        if doc.recipients.isEmpty { return "Add at least one recipient before sending." }
        if doc.actionable.isEmpty { return "At least one recipient needs to sign or approve." }
        for r in doc.actionable where r.name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter a name for \(r.roleName.isEmpty ? "every recipient" : "“\(r.roleName)”")."
        }
        for r in doc.recipients where r.role == .signer && doc.fields(for: r.id).isEmpty {
            return "\(r.displayName) has no fields. Drag at least a Signature field onto the document for them."
        }
        return nil
    }

    private func sendForSigning() {
        if let error = validationError() { alertMessage = error; return }
        store.send(doc.id)
        if let next = store.document(doc.id)?.nextSigner {
            alertMessage = "Sent. Hand this Mac to \(next.displayName) and choose “Sign as \(next.displayName)”, or use Email to send them a copy of the document."
        }
    }

    private func signNow() {
        var d = doc
        if d.recipients.isEmpty {
            d.recipients.append(Recipient(name: store.profile.name, email: store.profile.email, colorIndex: 0))
        }
        guard let me = d.recipients.first else { return }
        if d.recipients[0].name.trimmingCharacters(in: .whitespaces).isEmpty {
            d.recipients[0].name = store.profile.name
        }
        if d.fields(for: me.id).isEmpty, let pdf = store.pdf(for: d), let last = pdf.page(at: pdf.pageCount - 1) {
            let pts = PDFGeometry.displaySize(last)
            let page = pdf.pageCount - 1
            let sig = FieldKind.signature.defaultSize
            let dateSize = FieldKind.dateSigned.defaultSize
            let sigRect = CGRect(x: pts.width - 72 - sig.width, y: pts.height - 72 - sig.height - 28,
                                 width: sig.width, height: sig.height)
            let dateRect = CGRect(x: sigRect.minX, y: sigRect.maxY + 6, width: dateSize.width, height: dateSize.height)
            d.fields.append(DocField(kind: .signature, page: page, rect: NormRect.from(sigRect, in: pts), recipientID: me.id))
            d.fields.append(DocField(kind: .dateSigned, page: page, rect: NormRect.from(dateRect, in: pts), recipientID: me.id))
        }
        doc = d
        if let error = validationError() { alertMessage = error; return }
        store.send(doc.id)
        if let next = store.document(doc.id)?.nextSigner { signing = SigningRequest(id: next.id) }
    }

    private func useTemplate() {
        if let new = store.duplicate(doc, asTemplate: false) {
            store.filter = .drafts
            store.selection = new.id
        }
    }

    private func duplicate() {
        if let new = store.duplicate(doc, asTemplate: false) {
            if store.filter != .all { store.filter = .drafts }
            store.selection = new.id
        }
    }

    private func saveAsTemplate() {
        if let new = store.duplicate(doc, asTemplate: true) {
            store.filter = .templates
            store.selection = new.id
        }
    }

    private func exportPDF() {
        let suggested = DocumentStore.safeFileName(doc.title + " (Signed)") + ".pdf"
        if let url = Panels.savePDF(suggestedName: suggested) {
            store.export(doc, to: url)
            store.log(doc.id, action: "Exported", detail: "Saved a copy as \(url.lastPathComponent).")
        }
    }

    private func emailSigners() {
        guard let url = store.shareableCopy(of: doc) else { return }
        let emails = doc.recipients.map(\.email).filter { !$0.isEmpty }
        let body = "Hello,\n\nPlease review and sign “\(doc.title)”. The document is attached for your review.\n\nThank you."
        Mailer.compose(to: emails, subject: "Please review and sign: \(doc.title)", body: body, attachment: url)
        store.log(doc.id, action: "Emailed", detail: "Opened a Mail draft to \(emails.isEmpty ? "no addresses" : emails.joined(separator: ", ")).")
    }

    private func emailCompleted() {
        guard let url = shareURL ?? store.shareableCopy(of: doc) else { return }
        let emails = doc.recipients.map(\.email).filter { !$0.isEmpty }
        let body = "Hello,\n\nAll parties have completed “\(doc.title)”. The signed document, including its certificate of completion, is attached.\n\nThank you."
        Mailer.compose(to: emails, subject: "Completed: \(doc.title)", body: body, attachment: url)
        store.log(doc.id, action: "Emailed", detail: "Opened a Mail draft with the completed document to \(emails.isEmpty ? "no addresses" : emails.joined(separator: ", ")).")
    }

    private func verify() {
        let report = store.verifyIntegrity(doc)
        var lines = [report.originalOK ? "✓ Original document matches its recorded fingerprint."
                                       : "✗ Original document does NOT match its recorded fingerprint."]
        if let ok = report.completedOK {
            lines.append(ok ? "✓ Completed PDF is unchanged since it was sealed."
                            : "✗ Completed PDF has been modified since it was sealed.")
        }
        alertMessage = lines.joined(separator: "\n")
    }
}

extension DocumentStore {
    func log(_ id: UUID, action: String, detail: String) {
        guard var d = document(id) else { return }
        d.audit.append(AuditEvent(actor: actorName, action: action, detail: detail))
        update(d)
    }
}

// MARK: - Shared pieces

struct StatusPill: View {
    let doc: SignDocument

    var body: some View {
        let color: Color = doc.isTemplate ? .purple : doc.status.color
        Label(doc.isTemplate ? "Template" : doc.status.title,
              systemImage: doc.isTemplate ? "doc.on.doc.fill" : doc.status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct RecipientAvatar: View {
    let recipient: Recipient
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(recipient.color)
            Text(recipient.initialsText)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Right-hand panel for sent / completed envelopes: recipients, integrity, activity.
struct EnvelopePanel: View {
    let doc: SignDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Recipients").sectionTitleStyle()
                ForEach(Array(doc.recipients.enumerated()), id: \.element.id) { index, r in
                    RecipientStatusRow(recipient: r, order: index + 1,
                                       isNext: doc.status == .sent && doc.nextSigner?.id == r.id,
                                       docStatus: doc.status)
                }

                if doc.status == .completed {
                    Divider()
                    Text("Integrity").sectionTitleStyle()
                    HashRow(title: "Original SHA-256", value: doc.originalHash)
                    if let h = doc.completedHash { HashRow(title: "Sealed PDF SHA-256", value: h) }
                    Text("The sealed PDF ends with a Certificate of Completion listing every recipient and this audit trail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                Text("Activity").sectionTitleStyle()
                ForEach(doc.audit.reversed()) { AuditRow(event: $0) }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct RecipientStatusRow: View {
    let recipient: Recipient
    let order: Int
    let isNext: Bool
    let docStatus: DocStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RecipientAvatar(recipient: recipient)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(order). \(recipient.displayName)").font(.callout.weight(.semibold))
                if !recipient.email.isEmpty {
                    Text(recipient.email).font(.caption).foregroundStyle(.secondary)
                }
                status.font(.caption)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var status: some View {
        if let signed = recipient.signedAt {
            Label("\(recipient.role == .approver ? "Approved" : "Signed") \(signed.formatted(date: .abbreviated, time: .shortened))",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if recipient.role == .viewer {
            Label(docStatus == .completed ? "Copy available" : "Receives a copy", systemImage: "eye")
                .foregroundStyle(.secondary)
        } else if docStatus == .voided {
            Label("Did not sign", systemImage: "xmark.circle").foregroundStyle(.red)
        } else if isNext {
            Label("Waiting to sign", systemImage: "clock.fill").foregroundStyle(.orange)
        } else {
            Label("Pending", systemImage: "circle.dotted").foregroundStyle(.secondary)
        }
    }
}

struct HashRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(.borderless)
                    .help("Copy")
            }
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AuditRow: View {
    let event: AuditEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.action).font(.callout.weight(.semibold))
                    Spacer()
                    Text(event.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(event.actor).font(.caption).foregroundStyle(.secondary)
                Text(event.detail).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var icon: String {
        switch event.action {
        case "Signed": return "signature"
        case "Approved": return "checkmark.seal"
        case "Completed": return "checkmark.seal.fill"
        case "Sent": return "paperplane"
        case "Viewed": return "eye"
        case "Voided", "Declined": return "xmark.octagon"
        case "Emailed": return "envelope"
        case "Exported": return "square.and.arrow.down"
        default: return "doc"
        }
    }

    private var color: Color {
        switch event.action {
        case "Signed", "Approved", "Completed": return .green
        case "Voided", "Declined": return .red
        case "Sent": return .blue
        default: return .secondary
        }
    }
}
