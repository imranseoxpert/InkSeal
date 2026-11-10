import SwiftUI
import PDFKit

/// Prepare step: place fields on the document and set up recipients.
struct DocumentEditorView: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var doc: SignDocument
    var zoom: CGFloat

    @State private var selectedField: UUID?
    @State private var activeRecipient: UUID?
    @State private var armedKind: FieldKind?

    var body: some View {
        HStack(spacing: 0) {
            canvas
            Divider()
            EditorInspector(doc: $doc, selectedField: $selectedField,
                            activeRecipient: $activeRecipient, armedKind: $armedKind)
                .frame(width: 320)
        }
        .onAppear {
            if activeRecipient == nil { activeRecipient = doc.recipients.first?.id }
        }
    }

    @ViewBuilder private var canvas: some View {
        if let pdf = store.pdf(for: doc) {
            PagesCanvas(pdf: pdf, cacheKey: "\(doc.id.uuidString)-original", zoom: zoom) { index, size, points in
                pageOverlay(index: index, size: size, points: points)
            }
            .overlay(alignment: .top) {
                if let armedKind { placementBanner(armedKind) }
                else if doc.fields.isEmpty { emptyHint }
            }
        } else {
            ContentUnavailableView("Can't open this PDF", systemImage: "exclamationmark.triangle",
                                   description: Text("The file may have been moved or damaged."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pageOverlay(index: Int, size: CGSize, points: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    if let kind = armedKind {
                        addField(kind, page: index, at: location, size: size, points: points)
                        armedKind = nil
                    } else {
                        selectedField = nil
                    }
                }
            ForEach(doc.fields.filter { $0.page == index }) { field in
                EditorFieldBox(
                    field: field,
                    color: doc.recipient(field.recipientID)?.color ?? .gray,
                    selected: selectedField == field.id,
                    pageSize: size,
                    onSelect: {
                        selectedField = field.id
                        activeRecipient = field.recipientID
                    },
                    onCommit: { rect in
                        if let i = doc.fields.firstIndex(where: { $0.id == field.id }) { doc.fields[i].rect = rect }
                    }
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .dropDestination(for: String.self) { items, location in
            guard let raw = items.first, let kind = FieldKind(rawValue: raw) else { return false }
            addField(kind, page: index, at: location, size: size, points: points)
            return true
        }
    }

    private func placementBanner(_ kind: FieldKind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
            Text("Click on the page to place a **\(kind.title)** field for \(activeName)")
            Button("Cancel") { armedKind = nil }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 10)
    }

    private var emptyHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.point.up.left")
            Text("Drag fields from the right panel onto the page, or click a field and then click the page.")
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 10)
    }

    private var activeName: String {
        if let id = activeRecipient, let r = doc.recipient(id) { return r.displayName }
        return doc.recipients.first?.displayName ?? "you"
    }

    private func addField(_ kind: FieldKind, page: Int, at location: CGPoint, size: CGSize, points: CGSize) {
        let recipientID = ensureRecipient()
        let w = kind.defaultSize.width / points.width
        let h = kind.defaultSize.height / points.height
        let rect = NormRect(x: location.x / size.width - w / 2, y: location.y / size.height - h / 2, w: w, h: h).clamped()
        var field = DocField(kind: kind, page: page, rect: rect, recipientID: recipientID)
        if kind == .checkbox || kind == .text { field.required = false }
        doc.fields.append(field)
        selectedField = field.id
    }

    private func ensureRecipient() -> UUID {
        if let id = activeRecipient, doc.recipient(id) != nil { return id }
        if let first = doc.recipients.first {
            activeRecipient = first.id
            return first.id
        }
        let me = Recipient(name: store.profile.name, email: store.profile.email, colorIndex: 0)
        doc.recipients.append(me)
        activeRecipient = me.id
        return me.id
    }
}

// MARK: - Inspector

struct EditorInspector: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var doc: SignDocument
    @Binding var selectedField: UUID?
    @Binding var activeRecipient: UUID?
    @Binding var armedKind: FieldKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                recipientsSection
                Divider()
                paletteSection
                if let id = selectedField, doc.fields.contains(where: { $0.id == id }) {
                    Divider()
                    FieldPropertiesView(doc: $doc, fieldID: id, onDelete: { delete(id) })
                }
                Divider()
                summary
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // Recipients

    private var recipientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(doc.isTemplate ? "Roles" : "Recipients").sectionTitleStyle()
                Spacer()
                Menu {
                    Button("Add Recipient") { addRecipient(name: "", email: "") }
                    Button("Add Me (\(store.profile.name))") { addRecipient(name: store.profile.name, email: store.profile.email) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if doc.recipients.isEmpty {
                Text("Add the people who need to sign, in signing order. Or just drop a field on the page and you'll be added as the signer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Signing order runs top to bottom. Click a recipient to place fields for them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(doc.recipients.enumerated()), id: \.element.id) { index, recipient in
                RecipientEditorRow(
                    recipient: recipientBinding(recipient),
                    order: index + 1,
                    isActive: activeRecipient == recipient.id,
                    fieldCount: doc.fields(for: recipient.id).count,
                    isFirst: index == 0,
                    isLast: index == doc.recipients.count - 1,
                    onActivate: { activeRecipient = recipient.id },
                    onMove: { move(recipient.id, by: $0) },
                    onDelete: { removeRecipient(recipient.id) }
                )
            }
        }
    }

    private func recipientBinding(_ recipient: Recipient) -> Binding<Recipient> {
        Binding(
            get: { doc.recipient(recipient.id) ?? recipient },
            set: { new in
                if let i = doc.recipients.firstIndex(where: { $0.id == recipient.id }) { doc.recipients[i] = new }
            }
        )
    }

    private func addRecipient(name: String, email: String) {
        let used = Set(doc.recipients.map(\.colorIndex))
        let color = (0..<Palette.nsColors.count).first { !used.contains($0) } ?? doc.recipients.count
        let r = Recipient(name: name, email: email, colorIndex: color)
        doc.recipients.append(r)
        activeRecipient = r.id
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let i = doc.recipients.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard doc.recipients.indices.contains(j) else { return }
        doc.recipients.swapAt(i, j)
    }

    private func removeRecipient(_ id: UUID) {
        var d = doc
        d.recipients.removeAll { $0.id == id }
        d.fields.removeAll { $0.recipientID == id }
        doc = d
        if activeRecipient == id { activeRecipient = doc.recipients.first?.id }
        if let s = selectedField, !doc.fields.contains(where: { $0.id == s }) { selectedField = nil }
    }

    // Palette

    private var paletteSection: some View {
        let color = activeRecipient.flatMap { doc.recipient($0)?.color } ?? .accentColor
        return VStack(alignment: .leading, spacing: 10) {
            Text("Fields").sectionTitleStyle()
            Text("Drag onto the page, or click one and then click where it goes.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(FieldKind.allCases) { kind in
                    PaletteItem(kind: kind, color: color, armed: armedKind == kind)
                        .onTapGesture { armedKind = armedKind == kind ? nil : kind }
                        .draggable(kind.rawValue) {
                            PaletteItem(kind: kind, color: color, armed: true).frame(width: 140)
                        }
                }
            }
        }
    }

    private func delete(_ id: UUID) {
        selectedField = nil
        doc.fields.removeAll { $0.id == id }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summary").sectionTitleStyle()
            let signers = doc.recipients.filter { $0.role == .signer }
            Label("\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")", systemImage: "doc")
            Label("\(doc.fields.count) field\(doc.fields.count == 1 ? "" : "s") placed", systemImage: "square.dashed")
            Label("\(signers.count) signer\(signers.count == 1 ? "" : "s")", systemImage: "person.2")
            Text("Tip: ⌘⌫ deletes the selected field.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .font(.callout)
    }
}

struct PaletteItem: View {
    let kind: FieldKind
    let color: Color
    let armed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.symbol).frame(width: 16)
            Text(kind.title).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(armed ? color.opacity(0.25) : color.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(armed ? color : color.opacity(0.35), lineWidth: armed ? 1.5 : 1))
        .contentShape(Rectangle())
    }
}

struct RecipientEditorRow: View {
    @Binding var recipient: Recipient
    let order: Int
    let isActive: Bool
    let fieldCount: Int
    let isFirst: Bool
    let isLast: Bool
    let onActivate: () -> Void
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(recipient.color)
                Text("\(order)").font(.caption.bold()).foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 5) {
                if !recipient.roleName.isEmpty {
                    Text(recipient.roleName).font(.caption.weight(.semibold)).foregroundStyle(recipient.color)
                }
                TextField("Full name", text: $recipient.name).textFieldStyle(.roundedBorder)
                TextField("Email address", text: $recipient.email).textFieldStyle(.roundedBorder)
                HStack {
                    Picker("Role", selection: $recipient.role) {
                        ForEach(RecipientRole.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    Spacer()
                    Text("\(fieldCount) field\(fieldCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Menu {
                Button("Move Up") { onMove(-1) }.disabled(isFirst)
                Button("Move Down") { onMove(1) }.disabled(isLast)
                Divider()
                Button("Remove Recipient", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(isActive ? recipient.color.opacity(0.12) : Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isActive ? recipient.color : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onActivate() })
    }
}

struct FieldPropertiesView: View {
    @Binding var doc: SignDocument
    let fieldID: UUID
    let onDelete: () -> Void

    private var field: Binding<DocField> {
        Binding(
            get: { doc.fields.first { $0.id == fieldID } ?? DocField(kind: .text, page: 0, rect: NormRect(x: 0, y: 0, w: 0.1, h: 0.1), recipientID: UUID()) },
            set: { new in
                if let i = doc.fields.firstIndex(where: { $0.id == fieldID }) { doc.fields[i] = new }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Selected Field").sectionTitleStyle()
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.delete, modifiers: .command)
            }
            Picker("Type", selection: field.kind) {
                ForEach(FieldKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            Picker("Recipient", selection: field.recipientID) {
                ForEach(doc.recipients) { r in Text(r.displayName).tag(r.id) }
            }
            Toggle("Required", isOn: field.required)
            if field.wrappedValue.kind == .text {
                TextField("Placeholder (e.g. Job title)", text: field.label)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Page \(field.wrappedValue.page + 1)")
                Spacer()
                Button("Duplicate") { duplicate() }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func duplicate() {
        var copy = field.wrappedValue
        copy.id = UUID()
        copy.rect.y += copy.rect.h + 0.01
        copy.rect = copy.rect.clamped()
        doc.fields.append(copy)
    }
}
