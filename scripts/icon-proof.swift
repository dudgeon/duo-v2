// Draws apps' icons as macOS shows them (NSWorkspace.icon(forFile:), the Finder's and the Dock's source) beside
// their targets, at 1024, 128, 32 and 16 pt, on a light and a dark ground (F-142, DL-140).
//
//   swift scripts/icon-proof.swift <out.png> <label>=<app>=<target-1024.png>=<target-small.png> ...
//
// Each row: the target art, then the system's render at each size on light, then on dark, then the difference
// between the target and the render at 1024, both on white (black is identical; macOS adds its own rim light). Prints each
// row's mean difference at 1024 and at 16 pt @2x against the small target.
import AppKit

func cgImage(_ image: NSImage, pixels: Int) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

func load(_ path: String) -> CGImage {
    guard let i = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("can't read \(path)") }
    return i
}

func pixels(_ image: CGImage, _ n: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: n * n * 4)
    let cg = CGContext(data: &data, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // On white, so a target saved without transparency compares like one with it.
    cg.setFillColor(.white)
    cg.fill(CGRect(x: 0, y: 0, width: n, height: n))
    cg.interpolationQuality = .high
    cg.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
    return data
}

func meanDiff(_ a: CGImage, _ b: CGImage, _ n: Int) -> Double {
    let x = pixels(a, n), y = pixels(b, n)
    var sum = 0
    for i in 0..<x.count { sum += abs(Int(x[i]) - Int(y[i])) }
    return Double(sum) / Double(x.count)
}

func diffImage(_ a: CGImage, _ b: CGImage, _ n: Int) -> CGImage {
    var x = pixels(a, n), y = pixels(b, n)
    for i in stride(from: 0, to: x.count, by: 4) {
        for c in 0..<3 { x[i + c] = UInt8(min(255, abs(Int(x[i + c]) - Int(y[i + c])) * 3)) }
        x[i + 3] = 255
    }
    let cg = CGContext(data: &x, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return cg.makeImage()!
}

let args = CommandLine.arguments.dropFirst()
guard let out = args.first, args.count > 1 else { fatalError("usage: icon-proof.swift <out.png> <label>=<app>=<target-1024>=<target-small> ...") }
let rows = args.dropFirst().map { $0.split(separator: "=", maxSplits: 3).map(String.init) }

// Layout in pixels (2x): label 360, target 256, light cell, dark cell, diff 256.
let rowH = 300, sizesW = 256 + 128 + 32 + 16 + 4 * 24 + 48
let width = 360 + 256 + 24 + sizesW * 2 + 24 + 256 + 48
let height = rowH * rows.count + 80
let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
cg.setFillColor(.white)
cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
let ctx = NSGraphicsContext(cgContext: cg, flipped: false)
NSGraphicsContext.current = ctx

func text(_ s: String, _ x: Int, _ y: Int, size: CGFloat = 26, bold: Bool = false) {
    (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                                                                   .foregroundColor: NSColor(srgbRed: 0.12, green: 0.14, blue: 0.16, alpha: 1)])
}
text("TARGET", 360, height - 50, size: 22, bold: true)
text("SYSTEM RENDER, LIGHT  ·  1024 (at 128), 128, 32, 16 pt", 360 + 256 + 24, height - 50, size: 22, bold: true)
text("DARK", 360 + 256 + 24 + sizesW, height - 50, size: 22, bold: true)
text("DIFFERENCE AT 1024", 360 + 256 + 24 + sizesW * 2 + 24, height - 50, size: 22, bold: true)

for (i, r) in rows.enumerated() {
    let (label, app, target, small) = (r[0], r[1], r[2], r[3])
    let icon = NSWorkspace.shared.icon(forFile: app)
    let y0 = height - 80 - rowH * (i + 1) + 22
    text(label, 24, y0 + 140, size: 28, bold: true)
    text((app as NSString).lastPathComponent, 24, y0 + 100, size: 20)
    let t = load(target), s = load(small)
    cg.draw(t, in: CGRect(x: 360, y: y0, width: 256, height: 256))
    for (k, ground) in [CGColor(srgbRed: 0.79, green: 0.84, blue: 0.89, alpha: 1), CGColor(srgbRed: 0.125, green: 0.137, blue: 0.169, alpha: 1)].enumerated() {
        let x0 = 360 + 256 + 24 + sizesW * k
        cg.setFillColor(ground)
        cg.addPath(CGPath(roundedRect: CGRect(x: x0, y: y0 - 10, width: sizesW - 24, height: 276), cornerWidth: 20, cornerHeight: 20, transform: nil))
        cg.fillPath()
        var x = x0 + 24
        // Each size is rendered at its own pixel count (@2x), so the small art shows where macOS picks it.
        for (pt, shown) in [(1024, 256), (128, 128), (32, 32), (16, 16)] {
            let img = cgImage(icon, pixels: pt == 1024 ? 1024 : pt * 2)
            cg.interpolationQuality = .high
            cg.draw(img, in: CGRect(x: x, y: y0 + (256 - shown) / 2, width: shown, height: shown))
            x += shown + 24
        }
    }
    let sys1024 = cgImage(icon, pixels: 1024)
    cg.draw(diffImage(t, sys1024, 1024), in: CGRect(x: 360 + 256 + 24 + sizesW * 2 + 24, y: y0, width: 256, height: 256))
    let sys32 = cgImage(icon, pixels: 32)
    print(String(format: "%@: mean difference %.2f at 1024, %.2f at 16 pt @2x (0-255 per channel)", label, meanDiff(t, sys1024, 1024), meanDiff(s, sys32, 32)))
}
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(out)") }
print(out)
