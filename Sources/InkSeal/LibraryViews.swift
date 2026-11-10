import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } content: {
            LibraryListView(search: $search)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
        } detail: {
            if let id = store.selection, store.document(id) != nil {
                DocumentWorkspace(id: id).id(id)
            } else {
                WelcomeView()
            }
        }
        .sheet(isPresented: $store.showNewDocument) {
            NewDocumentView().environmentObject(store)
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .confirmationDialog("Delete this document?",
                            isPresented: Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = store.pendingDelete { store.delete(id) }
                store.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { store.pendingDelete = nil }
        } message: {
            Text("The document, its signatures and its audit trail will be permanently removed from InkSeal. This can't be undone.")
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        List(selection: $store.filter) {
            Section("Envelopes") {
                ForEach([LibraryFilter.all, .drafts, .waiting, .completed, .voided]) { f in
                    Label(f.title, systemImage: f.symbol)
                        .badge(store.count(f))
                        .tag(f)
                }
            }
            Section("Library") {
                Label(LibraryFilter.templates.title, systemImage: LibraryFilter.templates.symbol)
                    .badge(store.count(.templates))
                    .tag(LibraryFilter.templates)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { ProfileCard().padding(10) }
    }
}

struct ProfileCard: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var capturing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RecipientAvatar(recipient: Recipient(name: store.profile.name, email: store.profile.email), size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.profile.name.isEmpty ? "Your Profile" : store.profile.name)
                        .font(.callout.weight(.semibold)).lineLimit(1)
                    Text(store.profile.email.isEmpty ? "Add your email in Settings" : store.profile.email)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Button { capturing = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white)
                    if let data = store.profile.signature, let img = NSImage(data: data) {
                        Image(nsImage: img).resizable().scaledToFit().padding(6)
                    } else {
                        Label("Adopt a signature", systemImage: "signature")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .help("Change your saved signature")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
        .sheet(isPresented: $capturing) {
            SignatureCaptureView(kind: .signature, name: store.profile.name) { data, _ in
                store.profile.signature = data
            }
        }
    }
}

// MARK: - Document list

struct LibraryListView: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var search: String

    private var activeFilter: LibraryFilter { store.filter ?? .all }

    private var documents: [SignDocument] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return store.documents
            .filter { activeFilter.matches($0) }
            .filter { d in
                q.isEmpty || d.title.localizedCaseInsensitiveContains(q)
                    || d.recipients.contains { $0.name.localizedCaseInsensitiveContains(q) || $0.email.localizedCaseInsensitiveContains(q) }
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List(selection: $store.selection) {
            ForEach(documents) { doc in
                DocumentRow(doc: doc)
                    .tag(doc.id)
                    .contextMenu { contextMenu(for: doc) }
            }
        }
        .overlay {
            if documents.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? emptyTitle : "No Results", systemImage: activeFilter.symbol)
                } description: {
                    Text(search.isEmpty ? "Create a document, or drop PDFs here to import them." : "Try a different search.")
                } actions: {
                    if search.isEmpty {
                        Button("New Document") { store.showNewDocument = true }
                    }
                }
            }
        }
        .navigationTitle(activeFilter.title)
        .searchable(text: $search, prompt: "Search documents")
        .toolbar {
            ToolbarItemGroup {
                Button { store.importURLs(Panels.choosePDFs()) } label: {
                    Label("Import PDF", systemImage: "square.and.arrow.down")
                }
                .help("Import PDF (⌘O)")
                Button { store.showNewDocument = true } label: {
                    Label("New Document", systemImage: "square.and.pencil")
                }
                .help("New Document (⌘N)")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.importURLs(urls)
            return !urls.isEmpty
        }
    }

    private var emptyTitle: String {
        switch activeFilter {
        case .templates: return "No Templates Yet"
        case .waiting: return "Nothing Waiting"
        case .completed: return "Nothing Completed Yet"
        case .voided: return "Nothing Voided"
        default: return "No Documents"
        }
    }

    @ViewBuilder private func contextMenu(for doc: SignDocument) -> some View {
        if doc.isTemplate {
            Button("Use Template") {
                if let new = store.duplicate(doc, asTemplate: false) { store.filter = .drafts; store.selection = new.id }
            }
        } else {
            Button("Duplicate") {
                if let new = store.duplicate(doc, asTemplate: false) { store.selection = new.id }
            }
            Button("Save as Template") {
                if let new = store.duplicate(doc, asTemplate: true) { store.filter = .templates; store.selection = new.id }
            }
        }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.displayURL(for: doc)]) }
        Divider()
        Button("Delete…", role: .destructive) { store.pendingDelete = doc.id }
    }
}

struct DocumentRow: View {
    let doc: SignDocument

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: doc.isTemplate ? "doc.on.doc.fill" : doc.status.symbol)
                .font(.title3)
                .foregroundStyle(doc.isTemplate ? .purple : doc.status.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.headline).lineLimit(1)
                Text(doc.statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 4) {
                    Text(doc.createdAt.formatted(date: .abbreviated, time: .omitted))
                    if !doc.recipients.isEmpty {
                        Text("·")
                        Text(doc.recipients.map(\.displayName).joined(separator: ", ")).lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "signature")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.tint)
                Text("InkSeal").font(.largeTitle.weight(.semibold))
                Text("Create documents, place fields, collect signatures and seal them with an audit trail.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            HStack(spacing: 14) {
                Button { store.showNewDocument = true } label: {
                    Label("New Document", systemImage: "square.and.pencil").frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button { store.importURLs(Panels.choosePDFs()) } label: {
                    Label("Import PDF", systemImage: "square.and.arrow.down").frame(minWidth: 150)
                }
                .controlSize(.large)
            }
            HStack(alignment: .top, spacing: 18) {
                StepCard(number: 1, symbol: "doc.badge.plus", title: "Create",
                         text: "Start from a template, write your own, or import any PDF.")
                StepCard(number: 2, symbol: "square.dashed", title: "Prepare",
                         text: "Add recipients and drag signature, date, text and checkbox fields onto the page.")
                StepCard(number: 3, symbol: "checkmark.seal", title: "Sign & Seal",
                         text: "Everyone signs in order. InkSeal locks the PDF and adds a certificate of completion.")
            }
            .frame(maxWidth: 760)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StepCard: View {
    let number: Int
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol).font(.title2).foregroundStyle(.tint)
                Spacer()
                Text("\(number)").font(.caption.bold()).foregroundStyle(.secondary)
            }
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
    }
}
