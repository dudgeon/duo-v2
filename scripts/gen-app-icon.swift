// Draws Duo's app icon (DL-131, docs/design/icon-handoff/) at every size and builds AppIcon.icns, and the
// dev build's icon (DL-140: the same art with a hazard stripe across the foot) as AppIconDev.icns.
//
//   swift scripts/gen-app-icon.swift
//
// Writes docs/design/icon-handoff/AppIcon.iconset/, AppIconDev.iconset/ and their .icns (iconutil). bundle.sh
// copies AppIcon.icns into `release` builds and AppIconDev.icns into dev builds, so run this only when the
// drawing changes, and commit the outputs.
// The geometry is the canvas's 1024 grid (the squircle is 824 at 100,100, as macOS icons are). 16 and 32 pt, at
// 1x and 2x, use the simplified small art; 128 pt and up use the full art.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// The icon's squircle, as on the approved canvas: 824 x 824 at (100, 100), corner radius 185.
func squircle(inset: CGFloat = 0) -> CGPath {
    CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824).insetBy(dx: inset, dy: inset),
           cornerWidth: 185 - inset, cornerHeight: 185 - inset, transform: nil)
}

func pill(_ cg: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: CGColor) {
    cg.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
    cg.setFillColor(color)
    cg.fillPath()
}

func gradient(_ cg: CGContext, _ rect: CGRect, _ top: UInt32, _ bottom: UInt32) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
    cg.saveGState()
    cg.clip(to: rect)
    cg.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    cg.restoreGState()
}

func draw(_ cg: CGContext, small: Bool, dev: Bool) {
    // Drop shadow under the squircle, as macOS icons carry.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 10), blur: 20, color: rgb(0x000000, 0.28))
    cg.addPath(squircle())
    cg.setFillColor(rgb(0x121418))
    cg.fillPath()
    cg.restoreGState()

    // Two panes, full bleed: the console on the left, the page on the right, and a shadowed seam.
    cg.saveGState()
    cg.addPath(squircle())
    cg.clip()
    gradient(cg, CGRect(x: 100, y: 100, width: 372, height: 824), 0x24272d, 0x121418)
    gradient(cg, CGRect(x: 472, y: 100, width: 452, height: 824), 0xffffff, 0xe9edf1)
    cg.setFillColor(rgb(0x000000, small ? 0.2 : 0.18))
    cg.fill(CGRect(x: 472, y: 100, width: small ? 8 : 6, height: 824))
    cg.restoreGState()

    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setStrokeColor(rgb(0xe6e8eb))
    if small {
        cg.setLineWidth(66)
        cg.addLines(between: [CGPoint(x: 228, y: 418), CGPoint(x: 344, y: 512), CGPoint(x: 228, y: 606)])
        cg.strokePath()
        pill(cg, 566, 367, 264, 66, 33, rgb(0x1f2328))
        pill(cg, 566, 491, 264, 54, 27, rgb(0xc9cdd3))
        pill(cg, 566, 603, 200, 54, 27, rgb(0xc9cdd3))
    } else {
        cg.setLineWidth(30)
        cg.addLines(between: [CGPoint(x: 206, y: 364), CGPoint(x: 270, y: 416), CGPoint(x: 206, y: 468)])
        cg.strokePath()
        pill(cg, 206, 538, 176, 26, 13, rgb(0x9aa1ab))
        pill(cg, 206, 594, 128, 26, 13, rgb(0x9aa1ab))
        pill(cg, 206, 650, 156, 26, 13, rgb(0x9aa1ab))
        pill(cg, 556, 317, 240, 34, 17, rgb(0x1f2328))
        pill(cg, 556, 395, 268, 24, 12, rgb(0xc9cdd3))
        pill(cg, 556, 447, 226, 24, 12, rgb(0xc9cdd3))
        pill(cg, 538, 509, 320, 126, 16, rgb(0xdfe3e8))   // Claude's highlight
        pill(cg, 556, 537, 252, 24, 12, rgb(0x8b939c))
        pill(cg, 556, 585, 182, 24, 12, rgb(0x8b939c))
        pill(cg, 556, 683, 240, 24, 12, rgb(0xc9cdd3))
    }

    if dev { hazard(cg, small: small) }

    // A faint edge, so the white page holds its shape on white.
    cg.addPath(squircle(inset: small ? 4 : 3))
    cg.setStrokeColor(rgb(0x000000, 0.12))
    cg.setLineWidth(small ? 8 : 6)
    cg.strokePath()
}

/// The dev build's mark (DL-140): yellow and black stripes across the foot of the squircle, taller and wider at
/// 16 and 32 pt, under a 6 px shadow line.
func hazard(_ cg: CGContext, small: Bool) {
    let top: CGFloat = small ? 740 : 780, step: CGFloat = small ? 92 : 56, h = 924 - top
    cg.saveGState()
    cg.addPath(squircle())
    cg.clip()
    cg.setFillColor(rgb(0xf2c230))
    cg.fill(CGRect(x: 100, y: top, width: 824, height: h))
    cg.setFillColor(rgb(0x1f2328))
    var x = 100 - h
    while x < 924 {
        cg.addLines(between: [CGPoint(x: x, y: 924), CGPoint(x: x + h, y: top), CGPoint(x: x + h + step, y: top), CGPoint(x: x + step, y: 924)])
        cg.closePath()
        x += step * 2
    }
    cg.fillPath()
    cg.setFillColor(rgb(0x000000, 0.2))
    cg.fill(CGRect(x: 100, y: top, width: 824, height: 6))
    cg.restoreGState()
}

func render(pixels: Int, small: Bool, dev: Bool, to url: URL) {
    let cg = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(pixels) / 1024
    // Top-left origin, so the numbers read as on the canvas.
    cg.translateBy(x: 0, y: CGFloat(pixels))
    cg.scaleBy(x: s, y: -s)
    cg.interpolationQuality = .high
    draw(cg, small: small, dev: dev)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("docs/design/icon-handoff")
for (name, dev) in [("AppIcon", false), ("AppIconDev", true)] {
    let set = out.appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: set)
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let file = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
            render(pixels: pt * scale, small: pt <= 32, dev: dev, to: set.appendingPathComponent(file))
        }
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", set.path, "-o", out.appendingPathComponent("\(name).icns").path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
    print(out.appendingPathComponent("\(name).icns").path)
}
