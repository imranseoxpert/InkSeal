import SwiftUI

private struct Party: Identifiable, Hashable {
    let id = UUID()
    var name: String
}

/// Compose a new document from a template (or from scratch), with signature blocks for each party.
struct NewDocumentView: View {
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    @State private var templateID: String? = DocumentTemplate.all[0].id
    @State private var title = ""
    @State private var bodyText = ""
    @State private var parties: [Party] = []
    @State private var asTemplate = false

    var body: some View {
        HStack(spacing: 0) {
            List(DocumentTemplate.all, selection: $templateID) { t in
                HStack(spacing: 10) {
                    Image(systemName: t.symbol).frame(width: 22).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.name)
                        Text(t.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
                .tag(t.id)
            }
            .listStyle(.sidebar)
            .frame(width: 250)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("New Document").font(.title2.weight(.semibold))

                TextField("Document title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)

                partiesEditor

                VStack(alignment: .leading, spacing: 6) {
                    Text("Content").font(.headline)
                    TextEditor(text: $bodyText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                    Text("Start a line with “## ” for a heading. Replace [bracketed] placeholders before sending. Templates are starting points, not legal advice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Import PDF Instead…") {
                        let urls = Panels.choosePDFs()
                        if !urls.isEmpty {
                            dismiss()
                            store.importURLs(urls)
                        }
                    }
                    Toggle("Save as template", isOn: $asTemplate)
                        .toggleStyle(.checkbox)
                        .padding(.leading, 8)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(asTemplate ? "Create Template" : "Create Document") { create() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
        }
        .frame(width: 940, height: 660)
        .onAppear { apply(DocumentTemplate.all[0]) }
        .onChange(of: templateID) { _, id in
            if let t = DocumentTemplate.all.first(where: { $0.id == id }) { apply(t) }
        }
    }

    private var partiesEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Signature blocks").font(.headline)
                Text("— one per party, added at the end of the document")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach($parties) { $party in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Palette.color(parties.firstIndex(where: { $0.id == party.id }) ?? 0))
                                .frame(width: 8, height: 8)
                            TextField("Role", text: $party.name)
                                .textFieldStyle(.plain)
                                .frame(width: 130)
                            Button {
                                parties.removeAll { $0.id == party.id }
                            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }
                    Button {
                        parties.append(Party(name: "Signer \(parties.count + 1)"))
                    } label: { Label("Add", systemImage: "plus") }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private func apply(_ t: DocumentTemplate) {
        title = t.title
        bodyText = t.body
        parties = t.parties.map { Party(name: $0) }
    }

    private func create() {
        let names = parties.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let composed = PDFComposer.compose(title: title, body: bodyText, parties: names)
        let recipients: [Recipient] = names.enumerated().map { i, role in
            Recipient(name: "", email: "", roleName: role, colorIndex: i)
        }
        let fields: [DocField] = composed.fields.compactMap { f in
            guard recipients.indices.contains(f.party) else { return nil }
            return DocField(kind: f.kind, page: f.page, rect: f.rect, recipientID: recipients[f.party].id)
        }
        let templateName = DocumentTemplate.all.first { $0.id == templateID }?.name ?? "Blank Document"
        do {
            let doc = try store.createDocument(title: title, pdfData: composed.data, recipients: recipients,
                                               fields: fields, isTemplate: asTemplate,
                                               source: "Composed in InkSeal from “\(templateName)”")
            store.filter = asTemplate ? .templates : .drafts
            store.selection = doc.id
            dismiss()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
