import SwiftUI
import PDFKit

struct SigningRequest: Identifiable {
    let id: UUID // recipient id
}

private struct CaptureRequest: Identifiable {
    let id = UUID()
    let fieldID: UUID
    let kind: FieldKind
}

/// In-person signing session for one recipient.
struct SigningSessionView: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var doc: SignDocument
    let recipientID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var agreed = false
    @State private var capture: CaptureRequest?
    @State private var scrollTarget: Int?
    @State private var zoom: CGFloat = 1
    @State private var showDecline = false
    @State private var declineReason = ""

    private var recipient: Recipient? { doc.recipient(recipientID) }
    private var myFields: [DocField] { doc.fields(for: recipientID) }
    private var remaining: [DocField] { myFields.filter(\.needsInput) }
    private var isMe: Bool {
        guard let r = recipient else { return false }
        let p = store.profile
        if !p.email.isEmpty && r.email.caseInsensitiveCompare(p.email) == .orderedSame { return true }
        return !p.name.isEmpty && r.name.caseInsensitiveCompare(p.name) == .orderedSame
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !agreed { disclosure }
            canvas
            Divider()
            footer
        }
        .frame(minWidth: 1020, idealWidth: 1180, minHeight: 720, idealHeight: 880)
        .sheet(item: $capture) { req in
            SignatureCaptureView(kind: req.kind, name: recipient?.name ?? "",
                                 saved: isMe ? (req.kind == .initials ? store.profile.initials : store.profile.signature) : nil,
                                 offerDefault: isMe) { data, saveToProfile in
                adopt(data, kind: req.kind, fieldID: req.fieldID, saveToProfile: saveToProfile)
            }
        }
        .alert("Decline to sign?", isPresented: $showDecline) {
            TextField("Reason (optional)", text: $declineReason)
            Button("Decline", role: .destructive) { decline() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The document will be voided and no one else will be able to sign it.")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            if let r = recipient {
                ZStack {
                    Circle().fill(r.color)
                    Text(r.initialsText).font(.caption.bold()).foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signing as \(r.displayName)").font(.headline)
                    Text(r.email.isEmpty ? doc.title : "\(r.email) · \(doc.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Button { zoom = max(0.6, zoom - 0.15) } label: { Image(systemName: "minus.magnifyingglass") }
                Button { zoom = min(2, zoom + 0.15) } label: { Image(systemName: "plus.magnifyingglass") }
            }
            .buttonStyle(.borderless)
            Button("Finish Later") { dismiss() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var disclosure: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass").font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Please review the electronic record and signature disclosure").font(.headline)
                Text("By continuing, you agree to use electronic records and signatures for this document. You can review the document below before agreeing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("I Agree — Continue") { agree() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(Color.blue.opacity(0.08))
    }

    @ViewBuilder private var canvas: some View {
        if let pdf = store.pdf(for: doc) {
            PagesCanvas(pdf: pdf, cacheKey: "\(doc.id.uuidString)-original", zoom: zoom,
                        scrollTarget: $scrollTarget) { index, size, points in
                ZStack(alignment: .topLeading) {
                    ForEach(doc.fields.filter { $0.page == index }) { field in
                        let owner = doc.recipient(field.recipientID)
                        SigningFieldBox(
                            field: fieldBinding(field),
                            color: owner?.color ?? .gray,
                            isActive: agreed && field.recipientID == recipientID,
                            ownerName: owner?.displayName ?? "another recipient",
                            pageSize: size,
                            scale: size.width / max(points.width, 1),
                            onSign: { sign(field) },
                            onReadopt: { capture = CaptureRequest(fieldID: field.id, kind: field.kind) }
                        )
                    }
                }
                .frame(width: size.width, height: size.height)
            }
        } else {
            ContentUnavailableView("Can't open this PDF", systemImage: "exclamationmark.triangle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        let total = myFields.filter { $0.required && $0.kind != .dateSigned }.count
        let done = total - remaining.count
        let isApprover = recipient?.role == .approver
        return HStack(spacing: 14) {
            if total > 0 {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .frame(width: 160)
                Text("\(done) of \(total) required field\(total == 1 ? "" : "s") complete")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(isApprover ? "Review the document, then approve it." : "No fields to fill — review and finish.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Decline…", role: .destructive) { showDecline = true }
            if !remaining.isEmpty {
                Button("Next Field") { scrollTarget = remaining.first?.page }
                    .disabled(!agreed)
            }
            Button(isApprover ? "Approve" : "Finish") { finish() }
                .buttonStyle(.borderedProminent)
                .disabled(!agreed || !remaining.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: Actions

    private func fieldBinding(_ field: DocField) -> Binding<DocField> {
        Binding(
            get: { doc.fields.first { $0.id == field.id } ?? field },
            set: { new in
                if let i = doc.fields.firstIndex(where: { $0.id == field.id }) { doc.fields[i] = new }
            }
        )
    }

    private func agree() {
        guard let r = recipient else { return }
        var d = doc
        for i in d.fields.indices where d.fields[i].recipientID == recipientID {
            let empty = (d.fields[i].textValue ?? "").isEmpty
            switch d.fields[i].kind {
            case .fullName where empty: d.fields[i].textValue = r.name
            case .email where empty: d.fields[i].textValue = r.email
            default: break
            }
        }
        d.audit.append(AuditEvent(actor: r.auditName, action: "Viewed",
                                  detail: "Opened the document and agreed to the electronic record and signature disclosure on \(DeviceInfo.name)."))
        doc = d
        agreed = true
        scrollTarget = remaining.first?.page
    }

    private func sign(_ field: DocField) {
        guard let r = recipient else { return }
        let adopted = field.kind == .initials ? r.initials : r.signature
        if let adopted {
            if let i = doc.fields.firstIndex(where: { $0.id == field.id }) { doc.fields[i].imageData = adopted }
        } else {
            capture = CaptureRequest(fieldID: field.id, kind: field.kind)
        }
    }

    private func adopt(_ data: Data, kind: FieldKind, fieldID: UUID, saveToProfile: Bool) {
        var d = doc
        if let i = d.fields.firstIndex(where: { $0.id == fieldID }) { d.fields[i].imageData = data }
        if let ri = d.recipients.firstIndex(where: { $0.id == recipientID }) {
            if kind == .initials { d.recipients[ri].initials = data } else { d.recipients[ri].signature = data }
        }
        doc = d
        if saveToProfile {
            if kind == .initials { store.profile.initials = data } else { store.profile.signature = data }
        }
    }

    private func finish() {
        var d = doc
        let now = Date()
        let dateText = now.formatted(date: .abbreviated, time: .omitted)
        for i in d.fields.indices where d.fields[i].recipientID == recipientID && d.fields[i].kind == .dateSigned {
            d.fields[i].textValue = dateText
        }
        guard let ri = d.recipients.firstIndex(where: { $0.id == recipientID }) else { return }
        d.recipients[ri].signedAt = now
        let r = d.recipients[ri]
        let filled = d.fields.filter { $0.recipientID == recipientID && $0.isFilled }.count
        d.audit.append(AuditEvent(actor: r.auditName, action: r.role == .approver ? "Approved" : "Signed",
                                  detail: "Completed \(filled) field\(filled == 1 ? "" : "s") in person on \(DeviceInfo.name)."))
        doc = d
        if d.nextSigner == nil {
            do { try store.finalize(d.id) } catch {
                store.errorMessage = "Signing finished, but the final PDF could not be created: \(error.localizedDescription)"
            }
        }
        dismiss()
    }

    private func decline() {
        store.void(doc.id, reason: declineReason, actor: recipient?.auditName, declined: true)
        dismiss()
    }
}
