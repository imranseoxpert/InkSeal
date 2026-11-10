import Foundation
import SwiftUI
import AppKit

// MARK: - Fields

enum FieldKind: String, Codable, CaseIterable, Identifiable {
    case signature, initials, fullName, email, dateSigned, text, checkbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signature: return "Signature"
        case .initials: return "Initials"
        case .fullName: return "Full Name"
        case .email: return "Email"
        case .dateSigned: return "Date Signed"
        case .text: return "Text"
        case .checkbox: return "Checkbox"
        }
    }

    var symbol: String {
        switch self {
        case .signature: return "signature"
        case .initials: return "textformat.abc"
        case .fullName: return "person.crop.rectangle"
        case .email: return "envelope"
        case .dateSigned: return "calendar"
        case .text: return "character.cursor.ibeam"
        case .checkbox: return "checkmark.square"
        }
    }

    /// Default size in PDF points.
    var defaultSize: CGSize {
        switch self {
        case .signature: return CGSize(width: 170, height: 46)
        case .initials: return CGSize(width: 64, height: 40)
        case .checkbox: return CGSize(width: 16, height: 16)
        case .text: return CGSize(width: 180, height: 22)
        case .dateSigned: return CGSize(width: 120, height: 22)
        default: return CGSize(width: 170, height: 22)
        }
    }
}

/// A rectangle normalised to the page (0...1), origin at the top-left.
struct NormRect: Codable, Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
    }

    static func from(_ r: CGRect, in size: CGSize) -> NormRect {
        NormRect(x: r.minX / size.width, y: r.minY / size.height, w: r.width / size.width, h: r.height / size.height)
    }

    func clamped() -> NormRect {
        var r = self
        r.w = min(max(r.w, 0.015), 1)
        r.h = min(max(r.h, 0.01), 1)
        r.x = min(max(r.x, 0), 1 - r.w)
        r.y = min(max(r.y, 0), 1 - r.h)
        return r
    }
}

struct DocField: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: FieldKind
    var page: Int
    var rect: NormRect
    var recipientID: UUID
    var required: Bool = true
    var label: String = ""
    var textValue: String? = nil
    var imageData: Data? = nil
    var checked: Bool = false

    var isFilled: Bool {
        switch kind {
        case .signature, .initials: return imageData != nil
        case .checkbox: return checked
        default: return !(textValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Whether the signer still has to act on this field before finishing.
    var needsInput: Bool { required && !isFilled && kind != .dateSigned }

    mutating func clearValue() {
        textValue = nil
        imageData = nil
        checked = false
    }
}

// MARK: - Recipients

enum RecipientRole: String, Codable, CaseIterable, Identifiable {
    case signer, approver, viewer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signer: return "Needs to sign"
        case .approver: return "Needs to approve"
        case .viewer: return "Receives a copy"
        }
    }

    var short: String {
        switch self {
        case .signer: return "Signer"
        case .approver: return "Approver"
        case .viewer: return "CC"
        }
    }
}

struct Recipient: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var email: String
    var roleName: String = ""
    var role: RecipientRole = .signer
    var colorIndex: Int = 0
    var signedAt: Date? = nil
    var signature: Data? = nil
    var initials: Data? = nil

    var color: Color { Palette.color(colorIndex) }

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        if !roleName.isEmpty { return roleName }
        return "Unnamed recipient"
    }

    var auditName: String {
        email.isEmpty ? displayName : "\(displayName) <\(email)>"
    }

    var initialsText: String { Recipient.initials(of: displayName) }

    static func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(3)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

// MARK: - Documents

enum DocStatus: String, Codable {
    case draft, sent, completed, voided

    var title: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Waiting for Others"
        case .completed: return "Completed"
        case .voided: return "Voided"
        }
    }

    var symbol: String {
        switch self {
        case .draft: return "doc.text"
        case .sent: return "clock.fill"
        case .completed: return "checkmark.seal.fill"
        case .voided: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .draft: return .gray
        case .sent: return .orange
        case .completed: return .green
        case .voided: return .red
        }
    }
}

struct AuditEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var actor: String
    var action: String
    var detail: String
}

struct SignDocument: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    var status: DocStatus = .draft
    var isTemplate = false
    var pageCount: Int
    var originalHash: String
    var completedHash: String? = nil
    var completedAt: Date? = nil
    var recipients: [Recipient] = []
    var fields: [DocField] = []
    var audit: [AuditEvent] = []

    /// Recipients who must act, in signing order.
    var actionable: [Recipient] { recipients.filter { $0.role != .viewer } }
    var nextSigner: Recipient? { actionable.first { $0.signedAt == nil } }

    func recipient(_ id: UUID) -> Recipient? { recipients.first { $0.id == id } }
    func fields(for recipientID: UUID) -> [DocField] { fields.filter { $0.recipientID == recipientID } }

    var statusLine: String {
        if isTemplate {
            return "Template · \(recipients.count) role\(recipients.count == 1 ? "" : "s") · \(fields.count) field\(fields.count == 1 ? "" : "s")"
        }
        switch status {
        case .draft:
            return recipients.isEmpty ? "Draft · no recipients yet" : "Draft · \(recipients.count) recipient\(recipients.count == 1 ? "" : "s")"
        case .sent:
            let done = actionable.filter { $0.signedAt != nil }.count
            if let next = nextSigner { return "Waiting for \(next.displayName) · \(done)/\(actionable.count) signed" }
            return "Waiting for others"
        case .completed:
            if let c = completedAt { return "Completed \(c.formatted(date: .abbreviated, time: .shortened))" }
            return "Completed"
        case .voided:
            return "Voided"
        }
    }
}

// MARK: - Palette

enum Palette {
    static let nsColors: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple,
                                      .systemPink, .systemTeal, .systemIndigo, .systemBrown]
    static func nsColor(_ i: Int) -> NSColor { nsColors[((i % nsColors.count) + nsColors.count) % nsColors.count] }
    static func color(_ i: Int) -> Color { Color(nsColor: nsColor(i)) }
}
