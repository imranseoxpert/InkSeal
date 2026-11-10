import SwiftUI
import AppKit

struct InkColor: Identifiable, Hashable {
    let id: String
    let ns: NSColor
    var color: Color { Color(nsColor: ns) }

    static let all: [InkColor] = [
        InkColor(id: "Black", ns: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1)),
        InkColor(id: "Blue", ns: NSColor(srgbRed: 0.06, green: 0.22, blue: 0.66, alpha: 1)),
        InkColor(id: "Navy", ns: NSColor(srgbRed: 0.08, green: 0.12, blue: 0.33, alpha: 1)),
    ]
}

enum SignatureFonts {
    static let candidates = ["SnellRoundhand", "SavoyeLetPlain", "BradleyHandITCTT-Bold", "Apple-Chancery",
                             "Noteworthy-Light", "MarkerFelt-Thin"]
    static let available: [String] = {
        let found = candidates.filter { NSFont(name: $0, size: 12) != nil }
        return found.isEmpty ? ["Helvetica-Oblique"] : found
    }()
}

enum SignaturePath {
    static func path(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        if points.count == 1 {
            p.addLine(to: CGPoint(x: first.x + 0.5, y: first.y + 0.5))
            return p
        }
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            p.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
        }
        p.addLine(to: points[points.count - 1])
        return p
    }
}

enum SignatureRenderer {
    static func typed(_ text: String, font: String, color: NSColor) -> Data? {
        let f = NSFont(name: font, size: 72) ?? NSFont.systemFont(ofSize: 72)
        let s = NSAttributedString(string: text, attributes: [.font: f, .foregroundColor: color])
        let size = s.size()
        let pad: CGFloat = 10
        return ImageExport.png(size: CGSize(width: ceil(size.width + pad * 2), height: ceil(size.height + pad * 2)), scale: 2) { _ in
            s.draw(at: CGPoint(x: pad, y: pad))
        }
    }

    static func drawn(_ strokes: [[CGPoint]], color: NSColor) -> Data? {
        let pts = strokes.flatMap { $0 }
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return nil }
        let pad: CGFloat = 6
        let box = CGRect(x: minX - pad, y: minY - pad, width: max(maxX - minX, 1) + pad * 2, height: max(maxY - minY, 1) + pad * 2)
        return ImageExport.png(size: box.size, scale: 3) { ctx in
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(2.6)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for s in strokes {
                ctx.addPath(SignaturePath.path(s).cgPath)
                ctx.strokePath()
            }
        }
    }

    static func image(_ img: NSImage) -> Data? {
        var size = img.size
        guard size.width > 0, size.height > 0 else { return nil }
        let maxWidth: CGFloat = 900
        if size.width > maxWidth { size = CGSize(width: maxWidth, height: size.height * maxWidth / size.width) }
        return ImageExport.png(size: size, scale: 1) { _ in
            img.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .sourceOver,
                     fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

/// "Adopt your signature" sheet: type, draw, or upload.
struct SignatureCaptureView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case type = "Type", draw = "Draw", upload = "Upload"
        var id: String { rawValue }
    }

    let kind: FieldKind
    let name: String
    var saved: Data? = nil
    var offerDefault: Bool = false
    let onAdopt: (Data, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .type
    @State private var typed = ""
    @State private var fontName = SignatureFonts.available[0]
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var ink = InkColor.all[0]
    @State private var uploaded: NSImage?
    @State private var makeDefault = true

    private var noun: String { kind == .initials ? "initials" : "signature" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Adopt Your \(noun.capitalized)").font(.title2.weight(.semibold))
                Text("Choose how your \(noun) will appear on documents.").foregroundStyle(.secondary)
            }

            if let saved, let image = NSImage(data: saved) {
                HStack {
                    Image(nsImage: image).resizable().scaledToFit().frame(height: 40)
                    Spacer()
                    Button("Use Saved \(noun.capitalized)") {
                        onAdopt(saved, false)
                        dismiss()
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                .environment(\.colorScheme, .light)
            }

            Picker("Method", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch mode {
                case .type: typePane
                case .draw: drawPane
                case .upload: uploadPane
                }
            }
            .frame(height: 230)

            if mode != .upload {
                HStack(spacing: 10) {
                    Text("Ink").foregroundStyle(.secondary)
                    ForEach(InkColor.all) { c in
                        Circle()
                            .fill(c.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: ink == c ? 2.5 : 0).padding(-3))
                            .onTapGesture { ink = c }
                            .help(c.id)
                    }
                }
            }

            if offerDefault {
                Toggle("Save to my profile for next time", isOn: $makeDefault)
            }

            Text("By selecting Adopt and Sign, I agree that the \(noun) above is the electronic representation of my \(noun) for all purposes when I use it on documents, just the same as a pen-and-paper \(noun).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Adopt and Sign") { adopt() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdopt)
            }
        }
        .padding(24)
        .frame(width: 640)
        .onAppear {
            if typed.isEmpty { typed = kind == .initials ? Recipient.initials(of: name) : name }
        }
    }

    private var typePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(kind == .initials ? "Your initials" : "Your full name", text: $typed)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(SignatureFonts.available, id: \.self) { font in
                        Button { fontName = font } label: {
                            Text(typed.isEmpty ? "Your Name" : typed)
                                .font(.custom(font, size: 28))
                                .foregroundStyle(ink.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, minHeight: 66)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(fontName == font ? Color.accentColor : Color.gray.opacity(0.3),
                                                  lineWidth: fontName == font ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var drawPane: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.white)
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "xmark").foregroundStyle(.gray)
                        Rectangle().fill(Color.gray.opacity(0.5)).frame(height: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 46)
                }
                if strokes.isEmpty && current.isEmpty {
                    Text("Draw your \(noun) here with your trackpad or mouse").foregroundStyle(.gray)
                }
                Canvas { ctx, _ in
                    for s in strokes + [current] where !s.isEmpty {
                        ctx.stroke(SignaturePath.path(s), with: .color(ink.color),
                                   style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.35)))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { current.append($0.location) }
                    .onEnded { _ in
                        if !current.isEmpty { strokes.append(current) }
                        current = []
                    }
            )
            HStack {
                Button("Undo Stroke") { _ = strokes.popLast() }.disabled(strokes.isEmpty)
                Button("Clear") { strokes = []; current = [] }.disabled(strokes.isEmpty)
            }
            .controlSize(.small)
        }
    }

    private var uploadPane: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.white)
                if let uploaded {
                    Image(nsImage: uploaded).resizable().scaledToFit().padding(16)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle").font(.largeTitle)
                        Text("Upload a photo or scan of your \(noun). A transparent PNG looks best.")
                    }
                    .foregroundStyle(.gray)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.35)))
            Button("Choose Image…") {
                if let url = Panels.chooseImage(), let img = NSImage(contentsOf: url) { uploaded = img }
            }
        }
    }

    private var canAdopt: Bool {
        switch mode {
        case .type: return !typed.trimmingCharacters(in: .whitespaces).isEmpty
        case .draw: return !strokes.isEmpty
        case .upload: return uploaded != nil
        }
    }

    private func adopt() {
        let data: Data?
        switch mode {
        case .type: data = SignatureRenderer.typed(typed.trimmingCharacters(in: .whitespaces), font: fontName, color: ink.ns)
        case .draw: data = SignatureRenderer.drawn(strokes, color: ink.ns)
        case .upload: data = uploaded.flatMap { SignatureRenderer.image($0) }
        }
        guard let data else { return }
        onAdopt(data, offerDefault && makeDefault)
        dismiss()
    }
}
