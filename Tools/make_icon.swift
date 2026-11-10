// Renders the InkSeal app icon (1024×1024 PNG). Usage: swift Tools/make_icon.swift out.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let px = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
rep.size = NSSize(width: px, height: px)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

let blue = NSColor(srgbRed: 0.18, green: 0.36, blue: 0.96, alpha: 1)
let deep = NSColor(srgbRed: 0.08, green: 0.13, blue: 0.42, alpha: 1)

// Rounded-square background (macOS icon grid: 824pt body inside a 1024 canvas)
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
NSGradient(colors: [blue, deep])!.draw(in: bg, angle: -90)

// Paper with soft shadow
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -14)
NSGraphicsContext.saveGraphicsState()
shadow.set()
let paper = NSBezierPath(roundedRect: NSRect(x: 292, y: 214, width: 440, height: 580), xRadius: 30, yRadius: 30)
NSColor.white.setFill()
paper.fill()
NSGraphicsContext.restoreGraphicsState()

// Text lines
NSColor(white: 0.84, alpha: 1).setFill()
for i in 0..<5 {
    let w: CGFloat = i == 4 ? 190 : 340
    NSBezierPath(roundedRect: NSRect(x: 342, y: 700 - CGFloat(i) * 50, width: w, height: 20), xRadius: 10, yRadius: 10).fill()
}

// Signature line + flourish
NSColor(white: 0.62, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 342, y: 318, width: 300, height: 5)).fill()
let sig = NSBezierPath()
sig.lineWidth = 17
sig.lineCapStyle = .round
sig.lineJoinStyle = .round
sig.move(to: NSPoint(x: 348, y: 350))
sig.curve(to: NSPoint(x: 462, y: 392), controlPoint1: NSPoint(x: 380, y: 470), controlPoint2: NSPoint(x: 432, y: 300))
sig.curve(to: NSPoint(x: 612, y: 378), controlPoint1: NSPoint(x: 500, y: 480), controlPoint2: NSPoint(x: 548, y: 300))
blue.setStroke()
sig.stroke()

// Seal badge
let seal = NSBezierPath(ovalIn: NSRect(x: 596, y: 168, width: 210, height: 210))
NSColor(srgbRed: 0.99, green: 0.64, blue: 0.14, alpha: 1).setFill()
seal.fill()
NSColor.white.setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 616, y: 188, width: 170, height: 170))
ring.lineWidth = 6
ring.stroke()
let check = NSBezierPath()
check.lineWidth = 22
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.move(to: NSPoint(x: 652, y: 276))
check.line(to: NSPoint(x: 690, y: 238))
check.line(to: NSPoint(x: 752, y: 316))
check.stroke()

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
