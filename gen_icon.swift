// 生成终端风应用图标：gen_icon.swift 输出 ConsoleIcon.iconset/，再由 iconutil 转 icns
import AppKit

let outDir = "ConsoleIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let spec: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func draw(size px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let f = CGFloat(px)
    let inset = f * 0.09
    let side = f - inset * 2
    let rect = NSRect(x: inset, y: inset, width: side, height: side)
    let radius = side * 0.225

    // 深色渐变底
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.19, alpha: 1),
                              ending: NSColor(calibratedRed: 0.085, green: 0.09, blue: 0.10, alpha: 1))!
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.current?.cgContext.saveGState()
    path.addClip()
    gradient.draw(in: rect, angle: -90)
    NSGraphicsContext.current?.cgContext.restoreGState()

    // 内描边
    path.lineWidth = max(1, f * 0.012)
    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    path.stroke()

    // 终端提示符 ">_"：白色 > + 绿色 _
    func glyph(_ str: String, color: NSColor, size: CGFloat) -> NSAttributedString {
        let font = NSFont(name: "Menlo-Bold", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = size * 0.08
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.05)
        return NSAttributedString(string: str, attributes: [
            .font: font, .foregroundColor: color, .shadow: shadow,
        ])
    }

    let glyphSize = f * 0.36
    let gt = glyph(">", color: NSColor(calibratedWhite: 0.92, alpha: 1), size: glyphSize)
    let us = glyph("_", color: NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.34, alpha: 1), size: glyphSize)
    let gtSize = gt.size()
    let usSize = us.size()
    let gap = f * 0.03
    let totalW = gtSize.width + gap + usSize.width
    let x0 = rect.midX - totalW / 2
    let yTop = rect.midY + max(gtSize.height, usSize.height) / 2
    gt.draw(at: NSPoint(x: x0, y: yTop - gtSize.height))
    us.draw(at: NSPoint(x: x0 + gtSize.width + gap, y: yTop - usSize.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in spec {
    let rep = draw(size: px)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("wrote \(outDir)/\(name)")
}
