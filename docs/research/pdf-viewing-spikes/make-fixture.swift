// Spike (research/pdf-viewing, F-644): writes a deterministic 120-page PDF of invented content.
// Usage: swift make-fixture.swift <out.pdf>
// Pages carry things text extraction tends to lose: charts whose values exist only as bar
// heights, a two-column page (reading order), a table, and an image-only "scanned" page
// with no text layer. Every page ends with a marker "[p N]" so a reader can be checked.
import AppKit
import CoreText

let out = URL(fileURLWithPath: CommandLine.arguments[1])
var box = CGRect(x: 0, y: 0, width: 612, height: 792)
let ctx = CGContext(out as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: "Lantern Bay Ferry Field Manual (invented fixture)"] as CFDictionary)!

let words = "harbour tide berth ramp manifest deck crew bollard ferry lantern ballast hull wake current pier vessel signal fog bell schedule crossing passenger vehicle lane gangway mooring line skipper engine log weather swell channel buoy beacon".split(separator: " ").map(String.init)
var seed: UInt64 = 42
func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
func sentence() -> String {
    let n = 8 + rnd(10)
    var s = (0..<n).map { _ in words[rnd(words.count)] }.joined(separator: " ")
    s = s.prefix(1).uppercased() + s.dropFirst() + "."
    return s
}
func paragraph(_ k: Int = 5) -> String { (0..<k).map { _ in sentence() }.joined(separator: " ") }

func draw(_ text: String, in rect: CGRect, size: CGFloat = 11, bold: Bool = false) {
    let font = NSFont(name: bold ? "Helvetica-Bold" : "Helvetica", size: size)!
    let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
    let fs = CTFramesetterCreateWithAttributedString(attr)
    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), path, nil)
    CTFrameDraw(frame, ctx)
}

func barChart(_ rect: CGRect, values: [Int]) {
    // Axis and bars only: the values are not drawn as text, so text extraction can't see them.
    ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(1)
    ctx.stroke(rect)
    let w = rect.width / CGFloat(values.count)
    for (i, v) in values.enumerated() {
        ctx.setFillColor(NSColor(calibratedHue: CGFloat(i) / CGFloat(values.count), saturation: 0.5, brightness: 0.8, alpha: 1).cgColor)
        ctx.fill(CGRect(x: rect.minX + CGFloat(i) * w + 6, y: rect.minY, width: w - 12, height: rect.height * CGFloat(v) / 100))
    }
}

func scannedPage(_ n: Int) {
    // Render text into a bitmap and place only the bitmap: no text layer, like a scan.
    let img = NSImage(size: NSSize(width: 500, height: 200), flipped: false) { r in
        NSColor.white.setFill(); r.fill()
        let s = "SCANNED NOTICE (image only): Night crossings suspended when fog bell sounds three times. Code word: HERONGATE." as NSString
        s.draw(in: r.insetBy(dx: 10, dy: 10), withAttributes: [.font: NSFont(name: "Times-Roman", size: 22)!])
        return true
    }
    let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    ctx.draw(cg, in: CGRect(x: 56, y: 450, width: 500, height: 200))
}

for p in 1...120 {
    ctx.beginPDFPage(nil)
    let chapter = (p - 1) / 10 + 1
    draw("Chapter \(chapter) · Section \(p)", in: CGRect(x: 56, y: 700, width: 500, height: 40), size: 18, bold: true)
    switch p {
    case let x where x % 10 == 4:
        let vals = (0..<6).map { _ in 10 + rnd(90) }
        draw("Figure \(p): crossings per weekday (values shown only as bars).", in: CGRect(x: 56, y: 640, width: 500, height: 40))
        barChart(CGRect(x: 56, y: 360, width: 500, height: 260), values: vals)
        draw(paragraph(3), in: CGRect(x: 56, y: 120, width: 500, height: 220))
        // Ground truth for the measure script, not drawn on the page:
        FileHandle.standardError.write("chart p\(p) \(vals)\n".data(using: .utf8)!)
    case 33:
        draw("LEFT COLUMN: " + paragraph(6), in: CGRect(x: 56, y: 100, width: 240, height: 580))
        draw("RIGHT COLUMN: " + paragraph(6), in: CGRect(x: 316, y: 100, width: 240, height: 580))
    case 57:
        draw("Table 57: fares", in: CGRect(x: 56, y: 640, width: 500, height: 30), bold: true)
        let rows = [["Ticket", "Adult", "Child", "Vehicle"], ["Single", "4.20", "2.10", "18.00"], ["Return", "7.80", "3.90", "33.00"], ["Season", "96.00", "48.00", "410.00"]]
        for (r, row) in rows.enumerated() {
            for (c, cell) in row.enumerated() {
                draw(cell, in: CGRect(x: 56 + CGFloat(c) * 120, y: 600 - CGFloat(r) * 28, width: 110, height: 24), bold: r == 0)
            }
        }
    case 88:
        scannedPage(p)
    default:
        draw(paragraph(14), in: CGRect(x: 56, y: 100, width: 500, height: 580))
    }
    draw("[p \(p)]", in: CGRect(x: 280, y: 40, width: 80, height: 20), size: 9)
    ctx.endPDFPage()
}
ctx.closePDF()
print("wrote \(out.path)")
