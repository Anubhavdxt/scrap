// Draws the scrap logo and writes every asset derived from it.
// Usage: swift scripts/make_icon.swift <output-dir>
// Writes: AppIcon.iconset/ (then run iconutil), MenuBarIcon.png, MenuBarIcon@2x.png, logo.png, social-preview.png
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func bitmap(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    gc.cgContext.setAllowsAntialiasing(true)
    gc.cgContext.interpolationQuality = .high
    draw(gc.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    let url = out.appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: Shapes (1024 design space, y up)

/// The paper scrap: folded top-right corner, torn bottom edge.
func scrapPath(left: CGFloat = 250, right: CGFloat = 774, top: CGFloat = 790, bottom: CGFloat = 260, fold: CGFloat = 90, tooth: CGFloat = 38, depth: CGFloat = 22) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: left, y: top))
    p.addLine(to: CGPoint(x: right - fold, y: top))
    p.addLine(to: CGPoint(x: right, y: top - fold))
    p.addLine(to: CGPoint(x: right, y: bottom + depth))
    var x = right, i = 0
    while x > left {
        x = max(x - tooth, left)
        p.addLine(to: CGPoint(x: x, y: bottom + (i % 2 == 0 ? 0 : depth)))
        i += 1
    }
    p.addLine(to: CGPoint(x: left, y: top))
    p.closeSubpath()
    return p
}

func roundedBar(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
    ctx.fillPath()
}

let padColors: [UInt32] = [0xFF453A, 0xFF9F0A, 0xFFD60A, 0x30D158, 0x0A84FF, 0xBF5AF2, 0xFF375F]

// MARK: App icon

func drawAppIcon(_ ctx: CGContext, size: CGFloat, withMargin: Bool = true) {
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)
    let box = withMargin ? CGRect(x: 100, y: 100, width: 824, height: 824) : CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let radius: CGFloat = withMargin ? 186 : 230

    // Tile with a soft shadow, filled with a deep blue gradient (the Cobalt theme).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.45))
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(rgb(0x193549))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(0x24557a), rgb(0x0d2235)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: box.maxY), end: CGPoint(x: 512, y: box.minY), options: [])
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: box.insetBy(dx: 1.5, dy: 1.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
    ctx.setLineWidth(3)
    ctx.strokePath()

    // The paper, tilted a little.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 525)
    ctx.rotate(by: -5 * .pi / 180)
    ctx.translateBy(x: -512, y: -525)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: rgb(0x000000, 0.5))
    ctx.addPath(scrapPath())
    ctx.setFillColor(rgb(0xFBF6E9))
    ctx.fillPath()
    ctx.restoreGState()

    // Folded corner.
    ctx.setFillColor(rgb(0xDCD3B8))
    ctx.move(to: CGPoint(x: 684, y: 790)); ctx.addLine(to: CGPoint(x: 774, y: 700)); ctx.addLine(to: CGPoint(x: 684, y: 700)); ctx.closePath()
    ctx.fillPath()

    // Pad dots: the first is the current pad (filled), the rest are rings.
    let dot: CGFloat = 44, gap: CGFloat = 60
    let startX: CGFloat = 322
    for (i, c) in padColors.enumerated() {
        let cx = startX + gap * CGFloat(i), cy: CGFloat = 705
        let r = CGRect(x: cx - dot / 2, y: cy - dot / 2, width: dot, height: dot)
        if i == 0 {
            ctx.setFillColor(rgb(c)); ctx.fillEllipse(in: r)
        } else {
            ctx.setStrokeColor(rgb(c)); ctx.setLineWidth(9); ctx.strokeEllipse(in: r.insetBy(dx: 4.5, dy: 4.5))
        }
    }

    // Text lines and a caret.
    ctx.setFillColor(rgb(0x1F4663, 0.85))
    let lines: [(CGFloat, CGFloat)] = [(400, 0), (310, 0), (360, 0)]
    for (i, l) in lines.enumerated() { roundedBar(ctx, x: 322, y: 585 - CGFloat(i) * 78, w: l.0, h: 28) }
    roundedBar(ctx, x: 322, y: 585 - 3 * 78, w: 180, h: 28)
    ctx.setFillColor(rgb(0xFFC600))
    ctx.fill(CGRect(x: 516, y: 585 - 3 * 78 - 8, width: 14, height: 44))
    ctx.restoreGState()
}

func appIcon(_ px: Int) -> NSBitmapImageRep { bitmap(px, px) { drawAppIcon($0, size: CGFloat(px)) } }

// MARK: Menu bar template (black on clear, macOS tints it)

func menuBarIcon(_ px: Int) -> NSBitmapImageRep {
    bitmap(px, px) { ctx in
        let s = CGFloat(px) / 18
        ctx.scaleBy(x: s, y: s)
        // Scrap silhouette in an 18pt box.
        ctx.addPath(scrapPath(left: 3, right: 15, top: 16.5, bottom: 1.5, fold: 3, tooth: 1.5, depth: 0.9))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        // Cut-outs: three dots and two lines.
        ctx.setBlendMode(.clear)
        for i in 0..<3 {
            ctx.fillEllipse(in: CGRect(x: 5.1 + CGFloat(i) * 2.6, y: 11.3, width: 1.8, height: 1.8))
        }
        roundedBar(ctx, x: 5.2, y: 7.8, w: 7.6, h: 1.3)
        roundedBar(ctx, x: 5.2, y: 5.2, w: 5.2, h: 1.3)
    }
}

// MARK: Social preview

func socialPreview() -> NSBitmapImageRep {
    bitmap(1280, 640) { ctx in
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(0x1b3c57), rgb(0x0a1b2a)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 640), end: CGPoint(x: 1280, y: 0), options: [])
        ctx.saveGState()
        ctx.translateBy(x: 90, y: 60)
        drawAppIcon(ctx, size: 520)
        ctx.restoreGState()
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 150, weight: .bold), .foregroundColor: NSColor(cgColor: rgb(0xFFFFFF))!]
        let sub: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40, weight: .regular), .foregroundColor: NSColor(cgColor: rgb(0xC9DCEB))!]
        ("scrap" as NSString).draw(at: CGPoint(x: 660, y: 340), withAttributes: title)
        ("A free, open-source scratchpad" as NSString).draw(at: CGPoint(x: 664, y: 280), withAttributes: sub)
        ("for your Mac's menu bar." as NSString).draw(at: CGPoint(x: 664, y: 228), withAttributes: sub)
    }
}

// MARK: Write everything

let iconset = "AppIcon.iconset"
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    write(appIcon(px), "\(iconset)/\(name).png")
}
write(menuBarIcon(18), "MenuBarIcon.png")
write(menuBarIcon(36), "MenuBarIcon@2x.png")
write(appIcon(512), "logo.png")
write(socialPreview(), "social-preview.png")
print("wrote assets to \(out.path)")
