import AppKit

// Uso: make-icon <carpeta.iconset>
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let r = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.05, dy: s * 0.05)
    let bg = NSBezierPath(roundedRect: r, xRadius: s * 0.225, yRadius: s * 0.225)
    NSGradient(colors: [NSColor(red: 0.11, green: 0.14, blue: 0.27, alpha: 1), NSColor(red: 0.03, green: 0.04, blue: 0.09, alpha: 1)])!
        .draw(in: bg, angle: -90)
    // resplandor
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    NSGradient(colors: [NSColor(red: 0.2, green: 0.78, blue: 1, alpha: 0.5), .clear])!
        .draw(fromCenter: NSPoint(x: s * 0.82, y: s * 0.86), radius: 0, toCenter: NSPoint(x: s * 0.82, y: s * 0.86), radius: s * 0.7, options: [])
    NSGraphicsContext.restoreGraphicsState()
    // pantalla vertical
    let sw = s * 0.34, sh = s * 0.52
    let sr = NSRect(x: (s - sw) / 2, y: (s - sh) / 2, width: sw, height: sh)
    let screen = NSBezierPath(roundedRect: sr, xRadius: s * 0.045, yRadius: s * 0.045)
    NSColor.black.setFill(); screen.fill()
    NSColor(white: 1, alpha: 0.35).setStroke(); screen.lineWidth = s * 0.012; screen.stroke()
    // anillo y barras dentro
    let c = NSPoint(x: sr.midX, y: sr.midY + sh * 0.12)
    let ring = NSBezierPath()
    ring.appendArc(withCenter: c, radius: sw * 0.27, startAngle: 90, endAngle: -150, clockwise: true)
    ring.lineWidth = s * 0.03; ring.lineCapStyle = .round
    NSColor(red: 0.2, green: 0.78, blue: 1, alpha: 1).setStroke(); ring.stroke()
    for (i, w) in [0.58, 0.4].enumerated() {
        let b = NSRect(x: sr.minX + sw * 0.17, y: sr.minY + sh * (0.2 - 0.09 * CGFloat(i)), width: sw * w, height: sh * 0.045)
        let p = NSBezierPath(roundedRect: b, xRadius: b.height / 2, yRadius: b.height / 2)
        NSColor(white: 1, alpha: i == 0 ? 0.75 : 0.4).setFill(); p.fill()
    }
    img.unlockFocus()
    return img
}

for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                     ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let img = draw(CGFloat(size))
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
