// Spike (research/pdf-viewing, F-644): what PDFKit text extraction gives a Claude session.
// Usage: swift extract.swift <in.pdf> <out.txt>
// Writes the whole document as text with "--- page N ---" markers and prints timings,
// size, a rough token estimate (chars/4) and checks for things extraction tends to lose.
import Foundation
import PDFKit
import AppKit

let inURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let t0 = Date()
guard let doc = PDFDocument(url: inURL) else { fatalError("open failed") }
let tOpen = Date().timeIntervalSince(t0)

var out = ""
let t1 = Date()
for i in 0..<doc.pageCount {
    out += "--- page \(i + 1) ---\n"
    out += (doc.page(at: i)?.string ?? "") + "\n"
}
let tText = Date().timeIntervalSince(t1)
try out.write(to: outURL, atomically: true, encoding: .utf8)

// Rendering a page image (what a "page images for figures" path would cost).
let t2 = Date()
var pngBytes = 0
for i in [3, 87] { // p4 (chart) and p88 (scan)
    let page = doc.page(at: i)!
    let img = page.thumbnail(of: NSSize(width: 1000, height: 1294), for: .mediaBox)
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    pngBytes += rep.representation(using: .png, properties: [:])!.count
}
let tImg = Date().timeIntervalSince(t2) / 2

let twoCol = doc.page(at: 32)!.string ?? ""
let leftFirst = (twoCol.range(of: "LEFT COLUMN")?.lowerBound ?? twoCol.endIndex) < (twoCol.range(of: "RIGHT COLUMN")?.lowerBound ?? twoCol.startIndex)
print("pages: \(doc.pageCount)")
print(String(format: "open: %.3fs  text (all pages): %.3fs  render one page @1000px: %.3fs (avg png %d KB)", tOpen, tText, tImg, pngBytes / 2 / 1024))
print("chars: \(out.count)  ~tokens (chars/4): \(out.count / 4)")
print("scanned page text has HERONGATE: \(out.contains("HERONGATE"))")
print("two-column page reads left column first: \(leftFirst)")
print("table row kept on one line: \(out.contains("Single 4.20") || out.contains("Single\t4.20"))")
print("chart values present as text: \(out.contains("30, 78"))")
