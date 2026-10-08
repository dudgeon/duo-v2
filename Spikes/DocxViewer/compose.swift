// Puts snapshots side by side with a label over each (docx viewer spike):
//   swift compose.swift <out.png> <column-width> <max-height> "<label>=<png>[@x,y,w,h]" ...
// The optional @x,y,w,h crops the source first (in its pixels).
import AppKit

let a = CommandLine.arguments
let out = a[1], colW = CGFloat(Double(a[2])!), maxH = CGFloat(Double(a[3])!)
var cols: [(String, NSImage)] = []
for spec in a.dropFirst(4) {
    let parts = spec.split(separator: "=", maxSplits: 1).map(String.init)
    var path = parts[1], crop: CGRect?
    if let at = path.firstIndex(of: "@") { let n = path[path.index(after: at)...].split(separator: ",").map { CGFloat(Double($0)!) }; crop = CGRect(x: n[0], y: n[1], width: n[2], height: n[3]); path = String(path[..<at]) }
    guard let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: path))) else { fatalError(path) }
    var cg = rep.cgImage!
    if let c = crop { cg = cg.cropping(to: c.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height)))! }
    cols.append((parts[0], NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))))
}
let label: CGFloat = 34, gap: CGFloat = 12
let heights = cols.map { min(maxH, $0.1.size.height * colW / $0.1.size.width) }
let W = CGFloat(cols.count) * colW + CGFloat(cols.count + 1) * gap, H = (heights.max() ?? 0) + label + gap
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
NSColor(white: 0.96, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
for (i, (name, im)) in cols.enumerated() {
    let x = gap + CGFloat(i) * (colW + gap), h = heights[i], scale = colW / im.size.width
    let srcH = h / scale
    im.draw(in: NSRect(x: x, y: H - label - h, width: colW, height: h), from: NSRect(x: 0, y: im.size.height - srcH, width: im.size.width, height: srcH), operation: .copy, fraction: 1)
    NSString(string: name).draw(at: NSPoint(x: x, y: H - label + 8), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 17), .foregroundColor: NSColor.black])
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote", out, Int(W), "x", Int(H))
