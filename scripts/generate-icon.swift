#!/usr/bin/env swift
import AppKit

// Random-ish but deterministic PDFReader icon:
// warm gradient rounded square + white doc + highlight strokes.
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/PDFReader.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.225
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Gradient background: deep plum -> vivid orange-pink (matches Monokai/Dark Pro vibes)
    let top = NSColor(srgbRed: 0.56, green: 0.18, blue: 0.89, alpha: 1.0)
    let bottom = NSColor(srgbRed: 1.0, green: 0.37, blue: 0.23, alpha: 1.0)
    let grad = NSGradient(colors: [top, bottom])!
    grad.draw(in: bg, angle: -45)

    // Subtle inner highlight
    let gloss = NSBezierPath(roundedRect: NSRect(x: size*0.06, y: size*0.52, width: size*0.88, height: size*0.42), xRadius: radius*0.7, yRadius: radius*0.7)
    NSColor.white.withAlphaComponent(0.10).setFill()
    gloss.fill()

    // White document
    let docW = size * 0.52
    let docH = size * 0.64
    let docX = (size - docW) / 2
    let docY = (size - docH) / 2 - size*0.02
    let docRect = NSRect(x: docX, y: docY, width: docW, height: docH)
    let doc = NSBezierPath(roundedRect: docRect, xRadius: size*0.04, yRadius: size*0.04)
    NSColor.white.setFill()
    // shadow
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = size*0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size*0.015)
    shadow.set()
    doc.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Folded corner
    let fold = size*0.14
    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: docX+docW-fold, y: docY+docH))
    corner.line(to: NSPoint(x: docX+docW, y: docY+docH))
    corner.line(to: NSPoint(x: docX+docW, y: docY+docH-fold))
    corner.close()
    NSColor(srgbRed: 0.85, green: 0.86, blue: 0.90, alpha: 1.0).setFill()
    corner.fill()

    // Text lines: gray + yellow highlight + green + pink (palette nod)
    func bar(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: NSColor) {
        let r = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: h/2, yRadius: h/2)
        color.setFill()
        r.fill()
    }
    let lh = size*0.035
    let lx = docX + docW*0.14
    let lw = docW*0.72
    var ly = docY + docH*0.62
    bar(x: lx, y: ly, w: lw, h: lh, color: NSColor(white: 0.75, alpha: 1))
    ly -= lh*2.1
    // highlight row with yellow behind
    bar(x: lx - 2, y: ly - 2, w: lw + 4, h: lh + 4, color: NSColor(srgbRed: 1.0, green: 0.95, blue: 0.45, alpha: 1))
    bar(x: lx, y: ly, w: lw*0.85, h: lh, color: NSColor(white: 0.35, alpha: 1))
    ly -= lh*2.1
    bar(x: lx, y: ly, w: lw*0.6, h: lh, color: NSColor(srgbRed: 0.65, green: 0.95, blue: 0.65, alpha: 1))
    ly -= lh*2.1
    bar(x: lx, y: ly, w: lw*0.7, h: lh, color: NSColor(srgbRed: 1.0, green: 0.7, blue: 0.8, alpha: 1))

    // Magnifier badge bottom-right
    let badgeC = NSPoint(x: docX+docW*0.88, y: docY+docH*0.12)
    let badgeR = size*0.155
    let badge = NSBezierPath(ovalIn: NSRect(x: badgeC.x-badgeR, y: badgeC.y-badgeR, width: badgeR*2, height: badgeR*2))
    NSColor.white.setFill()
    let outer = NSBezierPath(ovalIn: NSRect(x: badgeC.x-badgeR-size*0.012, y: badgeC.y-badgeR-size*0.012, width: (badgeR+size*0.012)*2, height: (badgeR+size*0.012)*2))
    NSColor.white.setFill()
    outer.fill()
    NSColor(srgbRed: 0.15, green: 0.16, blue: 0.18, alpha: 1).setFill()
    badge.fill()
    // handle
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: badgeC.x+badgeR*0.55, y: badgeC.y-badgeR*0.55))
    handle.line(to: NSPoint(x: badgeC.x+badgeR*1.15, y: badgeC.y-badgeR*1.15))
    NSColor.white.setStroke()
    handle.lineWidth = size*0.055
    handle.lineCapStyle = .round
    handle.stroke()
    NSColor(srgbRed: 0.15, green: 0.16, blue: 0.18, alpha: 1).setStroke()
    handle.lineWidth = size*0.032
    handle.stroke()
    // magnifier glass: small highlight dot, not a full bar
    let glassDot = NSBezierPath(ovalIn: NSRect(x: badgeC.x-badgeR*0.5, y: badgeC.y+badgeR*0.1, width: badgeR*0.35, height: badgeR*0.22))
    NSColor.white.withAlphaComponent(0.85).setFill()
    // rotate slightly via transform skipped — simple dot is fine
    glassDot.fill()

    img.unlockFocus()
    return img
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    let img = drawIcon(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("png fail \(name)") }
    let path = (outDir as NSString).appendingPathComponent("\(name).png")
    try png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
