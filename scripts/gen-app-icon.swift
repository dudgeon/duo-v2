// Draws Duo's app icon (DL-131, docs/design/icon-handoff/) at every size and builds AppIcon.icns, and the
// dev build's icon (DL-140: the same art with a hazard stripe across the foot) as AppIconDev.icns.
//
//   swift scripts/gen-app-icon.swift
//
// Writes docs/design/icon-handoff/AppIcon.iconset/, AppIconDev.iconset/ and their .icns (iconutil). bundle.sh
// copies AppIcon.icns into `release` builds and AppIconDev.icns into dev builds, so run this only when the
// drawing changes, and commit the outputs.
// AppIconClassic.icns (DL-252) is the same drawing in Classic's colours, read from tokens.json (color.classic), so it follows the
// tokens: Duo shows it in the Dock while Settings › Appearance is Classic (NSApplication.applicationIconImage).
// The geometry is the canvas's 1024 grid (the squircle is 824 at 100,100, as macOS icons are). 16 and 32 pt, at
// 1x and 2x, use the simplified small art; 128 pt and up use the full art.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The drawing's colours. v2's are the approved icon's own; Classic's come from tokens.json.
struct Palette {
    var shadowBase, consoleTop, consoleBottom, pageTop, pageBottom, stroke, ink, rule, dimPill, highlight, page2, prompt: UInt32
    static let v2 = Palette(shadowBase: 0x121418, consoleTop: 0x24272d, consoleBottom: 0x121418, pageTop: 0xffffff, pageBottom: 0xe9edf1,
                            stroke: 0xe6e8eb, ink: 0x1f2328, rule: 0xc9cdd3, dimPill: 0x9aa1ab, highlight: 0xdfe3e8, page2: 0x8b939c, prompt: 0xe6e8eb)
    static func classic(root: URL) -> Palette {
        let t = try! JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("docs/design/build-handoff/tokens.json"))) as! [String: Any]
        let color = t["color"] as! [String: Any]
        let c = color["classic"] as! [String: Any]
        func hex(_ k: String) -> UInt32 {
            let v = ((c[k] ?? (color["light"] as! [String: Any])[k] ?? (color["console"] as! [String: Any])[k]) as! [String: Any])["value"] as! String
            return UInt32(v.dropFirst(), radix: 16)!
        }
        return Palette(shadowBase: hex("console"), consoleTop: hex("consoleHover"), consoleBottom: hex("console"), pageTop: hex("pane"), pageBottom: hex("ground"),
                       stroke: hex("consoleText"), ink: hex("text"), rule: hex("rule"), dimPill: hex("consoleText2"), highlight: hex("selected"), page2: hex("text2"),
                       prompt: hex("paneFocusOnConsole"))
    }
}

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

func draw(_ cg: CGContext, small: Bool, dev: Bool, _ pal: Palette) {
    // Drop shadow under the squircle, as macOS icons carry.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 10), blur: 20, color: rgb(0x000000, 0.28))
    cg.addPath(squircle())
    cg.setFillColor(rgb(pal.shadowBase))
    cg.fillPath()
    cg.restoreGState()

    // Two panes, full bleed: the console on the left, the page on the right, and a shadowed seam.
    cg.saveGState()
    cg.addPath(squircle())
    cg.clip()
    gradient(cg, CGRect(x: 100, y: 100, width: 372, height: 824), pal.consoleTop, pal.consoleBottom)
    gradient(cg, CGRect(x: 472, y: 100, width: 452, height: 824), pal.pageTop, pal.pageBottom)
    cg.setFillColor(rgb(0x000000, small ? 0.2 : 0.18))
    cg.fill(CGRect(x: 472, y: 100, width: small ? 8 : 6, height: 824))
    cg.restoreGState()

    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setStrokeColor(rgb(pal.prompt))
    if small {
        cg.setLineWidth(66)
        cg.addLines(between: [CGPoint(x: 228, y: 418), CGPoint(x: 344, y: 512), CGPoint(x: 228, y: 606)])
        cg.strokePath()
        pill(cg, 566, 367, 264, 66, 33, rgb(pal.ink))
        pill(cg, 566, 491, 264, 54, 27, rgb(pal.rule))
        pill(cg, 566, 603, 200, 54, 27, rgb(pal.rule))
    } else {
        cg.setLineWidth(30)
        cg.addLines(between: [CGPoint(x: 206, y: 364), CGPoint(x: 270, y: 416), CGPoint(x: 206, y: 468)])
        cg.strokePath()
        pill(cg, 206, 538, 176, 26, 13, rgb(pal.dimPill))
        pill(cg, 206, 594, 128, 26, 13, rgb(pal.dimPill))
        pill(cg, 206, 650, 156, 26, 13, rgb(pal.dimPill))
        pill(cg, 556, 317, 240, 34, 17, rgb(pal.ink))
        pill(cg, 556, 395, 268, 24, 12, rgb(pal.rule))
        pill(cg, 556, 447, 226, 24, 12, rgb(pal.rule))
        pill(cg, 538, 509, 320, 126, 16, rgb(pal.highlight))   // Claude's highlight
        pill(cg, 556, 537, 252, 24, 12, rgb(pal.page2))
        pill(cg, 556, 585, 182, 24, 12, rgb(pal.page2))
        pill(cg, 556, 683, 240, 24, 12, rgb(pal.rule))
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

func render(pixels: Int, small: Bool, dev: Bool, _ pal: Palette, to url: URL) {
    let cg = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(pixels) / 1024
    // Top-left origin, so the numbers read as on the canvas.
    cg.translateBy(x: 0, y: CGFloat(pixels))
    cg.scaleBy(x: s, y: -s)
    cg.interpolationQuality = .high
    draw(cg, small: small, dev: dev, pal)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("docs/design/icon-handoff")
let classicPalette = Palette.classic(root: root)
for (name, dev, pal) in [("AppIcon", false, Palette.v2), ("AppIconDev", true, Palette.v2), ("AppIconClassic", false, classicPalette)] {
    let set = out.appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: set)
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let file = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
            render(pixels: pt * scale, small: pt <= 32, dev: dev, pal, to: set.appendingPathComponent(file))
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
