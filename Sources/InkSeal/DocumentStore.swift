import Foundation
import AppKit
import PDFKit
import SwiftUI

struct UserProfile: Codable, Equatable {
    var name: String
    var email: String
    var signature: Data? = nil
    var initials: Data? = nil
}

enum LibraryFilter: String, CaseIterable, Identifiable, Hashable {
    case all, drafts, waiting, completed, voided, templates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Documents"
        case .drafts: return "Drafts"
        case .waiting: return "Waiting for Others"
        case .completed: return "Completed"
        case .voided: return "Voided & Declined"
        case .templates: return "Templates"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "tray.full"
        case .drafts: return "doc.text"
        case .waiting: return "clock"
        case .completed: return "checkmark.seal"
        case .voided: return "xmark.octagon"
        case .templates: return "doc.on.doc"
        }
    }

    func matches(_ d: SignDocument) -> Bool {
        switch self {
        case .all: return !d.isTemplate
        case .drafts: return !d.isTemplate && d.status == .draft
        case .waiting: return !d.isTemplate && d.status == .sent
        case .completed: return !d.isTemplate && d.status == .completed
        case .voided: return !d.isTemplate && d.status == .voided
        case .templates: return d.isTemplate
        }
    }
}

enum StoreError: LocalizedError {
    case invalidPDF, lockedPDF

    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "The file isn't a readable PDF."
        case .lockedPDF: return "The PDF is password-protected. Remove the password and try again."
        }
    }
}

final class DocumentStore: ObservableObject {
    @Published private(set) var documents: [SignDocument] = []
    @Published var profile: UserProfile { didSet { saveProfile() } }
    @Published var filter: LibraryFilter? = .all
    @Published var selection: UUID?
    @Published var showNewDocument = false
    @Published var pendingDelete: UUID?
    @Published var errorMessage: String?

    let root: URL
    private var pdfCache: [String: PDFDocument] = [:]
    private var pendingSave: DispatchWorkItem?

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        if let custom = ProcessInfo.processInfo.environment["INKSEAL_LIBRARY"], !custom.isEmpty {
            root = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            root = base.appendingPathComponent("InkSeal", isDirectory: true)
        }
        profile = UserProfile(name: NSFullUserName(), email: "")
        try? FileManager.default.createDirectory(at: documentsFolder, withIntermediateDirectories: true)
        load()
    }

    // MARK: Paths

    var documentsFolder: URL { root.appendingPathComponent("Documents", isDirectory: true) }
    private var libraryURL: URL { root.appendingPathComponent("library.json") }
    private var profileURL: URL { root.appendingPathComponent("profile.json") }

    func folder(_ id: UUID) -> URL { documentsFolder.appendingPathComponent(id.uuidString, isDirectory: true) }
    func originalURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("original.pdf") }
    func completedURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("completed.pdf") }

    func hasCompletedFile(_ doc: SignDocument) -> Bool {
        FileManager.default.fileExists(atPath: completedURL(doc.id).path)
    }

    func displayURL(for doc: SignDocument) -> URL {
        doc.status == .completed && hasCompletedFile(doc) ? completedURL(doc.id) : originalURL(doc.id)
    }

    func pdf(for doc: SignDocument) -> PDFDocument? {
        let url = originalURL(doc.id)
        if let cached = pdfCache[url.path] { return cached }
        guard let pdf = PDFDocument(url: url) else { return nil }
        pdfCache[url.path] = pdf
        return pdf
    }

    // MARK: Lookup

    func document(_ id: UUID) -> SignDocument? { documents.first { $0.id == id } }

    func binding(for id: UUID) -> Binding<SignDocument>? {
        guard let initial = document(id) else { return nil }
        return Binding(
            get: { [weak self] in self?.document(id) ?? initial },
            set: { [weak self] in self?.update($0) }
        )
    }

    func count(_ filter: LibraryFilter) -> Int { documents.filter { filter.matches($0) }.count }

    var actorName: String {
        let n = profile.name.trimmingCharacters(in: .whitespaces)
        let name = n.isEmpty ? NSFullUserName() : n
        return profile.email.isEmpty ? name : "\(name) <\(profile.email)>"
    }

    // MARK: Mutations

    func update(_ doc: SignDocument) {
        guard let i = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        var d = doc
        d.updatedAt = Date()
        documents[i] = d
        scheduleSave()
    }

    @discardableResult
    func createDocument(title: String, pdfData: Data, recipients: [Recipient] = [], fields: [DocField] = [],
                        isTemplate: Bool = false, source: String) throws -> SignDocument {
        guard let pdf = PDFDocument(data: pdfData) else { throw StoreError.invalidPDF }
        if pdf.isLocked { throw StoreError.lockedPDF }
        var doc = SignDocument(title: title.isEmpty ? "Untitled Document" : title,
                               pageCount: pdf.pageCount,
                               originalHash: Hashing.sha256(pdfData))
        doc.isTemplate = isTemplate
        doc.recipients = recipients
        doc.fields = fields
        doc.audit.append(AuditEvent(actor: actorName, action: isTemplate ? "Template created" : "Created", detail: source))
        try FileManager.default.createDirectory(at: folder(doc.id), withIntermediateDirectories: true)
        try pdfData.write(to: originalURL(doc.id), options: .atomic)
        documents.insert(doc, at: 0)
        saveNow()
        return doc
    }

    @discardableResult
    func importPDF(at url: URL) throws -> SignDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try createDocument(title: url.deletingPathExtension().lastPathComponent, pdfData: data,
                                  source: "Imported \(url.lastPathComponent)")
    }

    func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var last: SignDocument?
        var failures: [String] = []
        for url in urls {
            guard url.pathExtension.lowercased() == "pdf" else {
                failures.append("\(url.lastPathComponent): only PDF files can be imported.")
                continue
            }
            do { last = try importPDF(at: url) } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if let last {
            if filter != .all { filter = .drafts }
            selection = last.id
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }

    /// Copies a document (or template) into a fresh draft or template with all values cleared.
    @discardableResult
    func duplicate(_ doc: SignDocument, asTemplate: Bool) -> SignDocument? {
        guard let data = try? Data(contentsOf: originalURL(doc.id)) else {
            errorMessage = "The original PDF for “\(doc.title)” could not be read."
            return nil
        }
        var idMap: [UUID: UUID] = [:]
        let recipients: [Recipient] = doc.recipients.map { old in
            var r = old
            let newID = UUID()
            idMap[old.id] = newID
            r.id = newID
            r.signedAt = nil
            r.signature = nil
            r.initials = nil
            if asTemplate { r.name = ""; r.email = "" }
            return r
        }
        let fields: [DocField] = doc.fields.map { old in
            var f = old
            f.id = UUID()
            f.recipientID = idMap[old.recipientID] ?? old.recipientID
            f.clearValue()
            return f
        }
        let title: String
        let source: String
        if asTemplate {
            title = doc.title
            source = "Saved as a template from “\(doc.title)”"
        } else if doc.isTemplate {
            title = doc.title
            source = "Created from template “\(doc.title)”"
        } else {
            title = "\(doc.title) (Copy)"
            source = "Duplicated from “\(doc.title)”"
        }
        do {
            return try createDocument(title: title, pdfData: data, recipients: recipients, fields: fields,
                                      isTemplate: asTemplate, source: source)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func delete(_ id: UUID) {
        documents.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: folder(id))
        pdfCache = pdfCache.filter { !$0.key.contains(id.uuidString) }
        if selection == id { selection = nil }
        saveNow()
    }

    func send(_ id: UUID) {
        guard var d = document(id) else { return }
        d.status = .sent
        let names = d.recipients.map { "\($0.displayName) (\($0.role.short))" }.joined(separator: ", ")
        d.audit.append(AuditEvent(actor: actorName, action: "Sent", detail: "Sent for signature to \(names)."))
        update(d)
    }

    func void(_ id: UUID, reason: String, actor: String? = nil, declined: Bool = false) {
        guard var d = document(id) else { return }
        d.status = .voided
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        d.audit.append(AuditEvent(actor: actor ?? actorName,
                                  action: declined ? "Declined" : "Voided",
                                  detail: why.isEmpty ? "No reason given." : "Reason: \(why)"))
        update(d)
    }

    /// Burns all field values into the PDF, appends the certificate of completion and seals the envelope.
    func finalize(_ id: UUID) throws {
        guard var d = document(id), let original = pdf(for: d) else { return }
        d.status = .completed
        d.completedAt = Date()
        d.audit.append(AuditEvent(actor: "InkSeal", action: "Completed",
                                  detail: "All recipients finished. Final PDF sealed with a certificate of completion."))
        let data = PDFFinalizer.render(original: original, doc: d)
        try data.write(to: completedURL(d.id), options: .atomic)
        d.completedHash = Hashing.sha256(data)
        update(d)
        saveNow()
    }

    struct IntegrityReport {
        var originalOK: Bool
        var completedOK: Bool?
    }

    func verifyIntegrity(_ doc: SignDocument) -> IntegrityReport {
        let original = Hashing.sha256(fileAt: originalURL(doc.id)) == doc.originalHash
        var completed: Bool? = nil
        if let expected = doc.completedHash {
            completed = Hashing.sha256(fileAt: completedURL(doc.id)) == expected
        }
        return IntegrityReport(originalOK: original, completedOK: completed)
    }

    /// A copy of the current PDF with a human-friendly file name, for sharing or emailing.
    func shareableCopy(of doc: SignDocument) -> URL? {
        let source = displayURL(for: doc)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InkSeal-\(doc.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suffix = doc.status == .completed ? " (Signed)" : ""
        let dest = dir.appendingPathComponent(Self.safeFileName(doc.title + suffix) + ".pdf")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func export(_ doc: SignDocument, to url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.copyItem(at: displayURL(for: doc), to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Document" : cleaned
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: profileURL),
           let p = try? Self.decoder.decode(UserProfile.self, from: data) {
            profile = p
        }
        if let data = try? Data(contentsOf: libraryURL) {
            do {
                documents = try Self.decoder.decode([SignDocument].self, from: data)
            } catch {
                errorMessage = "Your library could not be read: \(error.localizedDescription)"
            }
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let data = try Self.encoder.encode(documents)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            NSLog("InkSeal: failed to save library: \(error)")
        }
    }

    private func saveProfile() {
        guard let data = try? Self.encoder.encode(profile) else { return }
        try? data.write(to: profileURL, options: .atomic)
    }
}
