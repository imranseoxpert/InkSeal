import SwiftUI
import PDFKit

/// Scrollable stack of rendered PDF pages, with a caller-supplied overlay per page.
struct PagesCanvas<Overlay: View>: View {
    let pdf: PDFDocument
    let cacheKey: String
    var zoom: CGFloat
    @Binding var scrollTarget: Int?
    let overlay: (Int, CGSize, CGSize) -> Overlay

    init(pdf: PDFDocument, cacheKey: String, zoom: CGFloat = 1, scrollTarget: Binding<Int?> = .constant(nil),
         @ViewBuilder overlay: @escaping (_ page: Int, _ displaySize: CGSize, _ pointSize: CGSize) -> Overlay) {
        self.pdf = pdf
        self.cacheKey = cacheKey
        self.zoom = zoom
        self._scrollTarget = scrollTarget
        self.overlay = overlay
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 22) {
                        ForEach(0..<pdf.pageCount, id: \.self) { i in
                            if let page = pdf.page(at: i) {
                                pageView(page, index: i, available: geo.size.width).id(i)
                            }
                        }
                    }
                    .padding(32)
                    .frame(minWidth: geo.size.width)
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                    DispatchQueue.main.async { scrollTarget = nil }
                }
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func pageView(_ page: PDFPage, index: Int, available: CGFloat) -> some View {
        let points = PDFGeometry.displaySize(page)
        // 100% = fit the visible width (capped so pages don't get huge on wide windows).
        let fitWidth = min(820, max(420, available - 64))
        let width = fitWidth * zoom
        let height = width * points.height / max(points.width, 1)
        let display = CGSize(width: width, height: height)
        return VStack(spacing: 6) {
            PageImageView(page: page, key: "\(cacheKey)#\(index)")
                .frame(width: width, height: height)
                .overlay(alignment: .topLeading) { overlay(index, display, points) }
                .environment(\.colorScheme, .light)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            Text("Page \(index + 1) of \(pdf.pageCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct PageImageView: View {
    let page: PDFPage
    let key: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: key) {
            image = PageRenderCache.shared.image(for: page, key: key)
        }
    }
}

/// Read-only rendering of a field's value on the page.
struct FieldValueView: View {
    let field: DocField
    let fontSize: CGFloat

    var body: some View {
        switch field.kind {
        case .signature, .initials:
            if let data = field.imageData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        case .checkbox:
            Image(systemName: field.checked ? "checkmark.square" : "square")
                .resizable().scaledToFit().foregroundStyle(.black)
        default:
            Text(field.textValue ?? "")
                .font(.system(size: fontSize))
                .foregroundStyle(.black)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
        }
    }
}

// MARK: - Editor field (movable / resizable)

struct EditorFieldBox: View {
    let field: DocField
    let color: Color
    let selected: Bool
    let pageSize: CGSize
    let onSelect: () -> Void
    let onCommit: (NormRect) -> Void

    @State private var move: CGSize = .zero
    @State private var grow: CGSize = .zero

    var body: some View {
        let base = field.rect.rect(in: pageSize)
        let w = max(base.width + grow.width, 12)
        let h = max(base.height + grow.height, 10)
        label(width: w, height: h)
            .frame(width: w, height: h)
            .overlay(alignment: .bottomTrailing) { if selected { resizeHandle } }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        if !selected { onSelect() }
                        move = value.translation
                    }
                    .onEnded { value in
                        var r = field.rect
                        r.x += Double(value.translation.width / pageSize.width)
                        r.y += Double(value.translation.height / pageSize.height)
                        onCommit(r.clamped())
                        move = .zero
                    }
            )
            .onTapGesture { onSelect() }
            .help("\(field.kind.title)\(field.required ? " (required)" : " (optional)") — drag to move")
            .position(x: base.minX + w / 2 + move.width, y: base.minY + h / 2 + move.height)
    }

    private func label(width: CGFloat, height: CGFloat) -> some View {
        let iconSize = min(height * 0.5, 13)
        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(selected ? 0.26 : 0.16))
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(color, style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: field.required ? [] : [4, 3]))
            HStack(spacing: 3) {
                Image(systemName: field.kind.symbol)
                if width > 64 && field.kind != .checkbox {
                    Text(field.label.isEmpty ? field.kind.title : field.label).lineLimit(1)
                }
                if field.required && width > 40 && field.kind != .checkbox {
                    Text("*").fontWeight(.bold)
                }
            }
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 3)
        }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(color, lineWidth: 1.5))
            .frame(width: 11, height: 11)
            .offset(x: 5, y: 5)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { grow = $0.translation }
                    .onEnded { value in
                        let base = field.rect.rect(in: pageSize)
                        var r = field.rect
                        r.w = Double(max(base.width + value.translation.width, 12) / pageSize.width)
                        r.h = Double(max(base.height + value.translation.height, 10) / pageSize.height)
                        onCommit(r.clamped())
                        grow = .zero
                    }
            )
    }
}

// MARK: - Signing field (fillable by the active signer)

struct SigningFieldBox: View {
    @Binding var field: DocField
    let color: Color
    let isActive: Bool
    let ownerName: String
    let pageSize: CGSize
    let scale: CGFloat
    var onSign: () -> Void = {}
    var onReadopt: () -> Void = {}

    var body: some View {
        let r = field.rect.rect(in: pageSize)
        Group {
            if isActive { active(size: r.size) } else { passive }
        }
        .frame(width: r.width, height: r.height)
        .position(x: r.midX, y: r.midY)
    }

    private var fontSize: CGFloat {
        let r = field.rect.rect(in: pageSize)
        return FieldStyle.fontSize(forHeight: r.height / max(scale, 0.01)) * scale
    }

    @ViewBuilder private var passive: some View {
        if field.isFilled {
            FieldValueView(field: field, fontSize: fontSize)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(color.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .background(color.opacity(0.06))
                .help("\(field.kind.title) for \(ownerName)")
        }
    }

    @ViewBuilder private func active(size: CGSize) -> some View {
        switch field.kind {
        case .signature, .initials:
            if field.isFilled {
                FieldValueView(field: field, fontSize: fontSize)
                    .background(color.opacity(0.06))
                    .overlay(alignment: .topTrailing) {
                        Button { field.imageData = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.white, .gray)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .help("Clear")
                    }
                    .contextMenu {
                        Button("Adopt a New \(field.kind.title)…") { onReadopt() }
                        Button("Clear") { field.imageData = nil }
                    }
            } else {
                Button(action: onSign) {
                    VStack(spacing: 1) {
                        Image(systemName: field.kind == .signature ? "signature" : "pencil.tip")
                        Text(field.kind == .signature ? "Sign" : "Initial")
                    }
                    .font(.system(size: max(8, min(size.height * 0.28, 13)), weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.yellow.opacity(0.85)))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.orange, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

        case .checkbox:
            Button { field.checked.toggle() } label: {
                Image(systemName: field.checked ? "checkmark.square.fill" : "square")
                    .resizable().scaledToFit()
                    .foregroundStyle(field.checked ? Color.accentColor : Color.black.opacity(0.6))
                    .background(field.needsInput ? Color.yellow.opacity(0.6) : Color.clear)
            }
            .buttonStyle(.plain)

        case .dateSigned:
            Text(field.textValue ?? "Date (added on finish)")
                .font(.system(size: fontSize))
                .foregroundStyle(field.textValue == nil ? Color.gray : Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .background(color.opacity(0.1))

        default:
            TextField(field.label.isEmpty ? field.kind.title : field.label,
                      text: Binding(get: { field.textValue ?? "" }, set: { field.textValue = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
                .foregroundStyle(.black)
                .padding(.horizontal, 2)
                .frame(maxHeight: .infinity)
                .background(field.needsInput ? Color.yellow.opacity(0.55) : color.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(color.opacity(0.6), lineWidth: 1))
        }
    }
}

// MARK: - PDFKit viewer for sealed documents

struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .underPageBackgroundColor
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
