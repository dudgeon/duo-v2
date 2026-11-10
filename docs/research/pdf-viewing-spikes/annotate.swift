// Spike (research/pdf-viewing, F-644): can PDFKit write and read back portable PDF comments
// (ISO 32000 markup annotations): a sticky note, a reply (IRT), a review state reply
// (State/StateModel), a highlight with a popup, author (T), dates (M, CreationDate), NM?
// Usage: swift annotate.swift <in.pdf> <out.pdf>
import Foundation
import PDFKit
import AppKit

let inURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let doc = PDFDocument(url: inURL)!
let page = doc.page(at: 0)!
let now = Date()
func key(_ s: String) -> PDFAnnotationKey { PDFAnnotationKey(rawValue: s) }

// 1. Sticky note (Text annotation) from Geoff.
let note = PDFAnnotation(bounds: CGRect(x: 520, y: 690, width: 20, height: 20), forType: .text, withProperties: nil)
note.contents = "@claude is this paragraph accurate?"
note.userName = "Geoff"                                   // /T
note.modificationDate = now                               // /M
note.setValue("duo-c-0001", forAnnotationKey: key("/NM"))
note.setValue("Comment", forAnnotationKey: key("/Subj"))
note.setValue(now, forAnnotationKey: key("/CreationDate"))
page.addAnnotation(note)

// 2. Reply from Claude: a Text annotation with /IRT -> note, /RT /R.
let reply = PDFAnnotation(bounds: note.bounds, forType: .text, withProperties: nil)
reply.contents = "Mostly. The second sentence repeats the first."
reply.userName = "Claude"
reply.modificationDate = now
reply.setValue("duo-c-0002", forAnnotationKey: key("/NM"))
reply.setValue(note, forAnnotationKey: key("/IRT"))
reply.setValue("/R", forAnnotationKey: key("/RT"))
page.addAnnotation(reply)

// 3. Resolve: a state reply (StateModel Review, State Completed), as Acrobat writes it.
let state = PDFAnnotation(bounds: note.bounds, forType: .text, withProperties: nil)
state.contents = "Completed set by Geoff"
state.userName = "Geoff"
state.modificationDate = now
state.setValue("duo-c-0003", forAnnotationKey: key("/NM"))
state.setValue(note, forAnnotationKey: key("/IRT"))
state.setValue("Review", forAnnotationKey: key("/StateModel"))
state.setValue("Completed", forAnnotationKey: key("/State"))
state.setValue(NSNumber(value: 32), forAnnotationKey: key("/F")) // hidden flag, as Acrobat does for state replies
page.addAnnotation(state)

// 4. Highlight over the first body line, with a popup and a comment.
let sel = page.selection(for: CGRect(x: 56, y: 655, width: 500, height: 14))!
var quads: [NSValue] = []
for line in sel.selectionsByLine() {
    let b = line.bounds(for: page)
    quads += [CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY)].map { NSValue(point: $0) }
}
let hl = PDFAnnotation(bounds: sel.bounds(for: page), forType: .highlight, withProperties: nil)
hl.quadrilateralPoints = quads.map { NSValue(point: NSPoint(x: $0.pointValue.x - sel.bounds(for: page).minX, y: $0.pointValue.y - sel.bounds(for: page).minY)) }
hl.color = NSColor.systemYellow
hl.contents = "Highlight: check the berth numbers"
hl.userName = "Geoff"
hl.modificationDate = now
hl.setValue("duo-c-0004", forAnnotationKey: key("/NM"))
let popup = PDFAnnotation(bounds: CGRect(x: 560, y: 600, width: 180, height: 100), forType: .popup, withProperties: nil)
hl.popup = popup
page.addAnnotation(hl)
page.addAnnotation(popup)

let t0 = Date()
let ok = doc.write(to: outURL)
print("write ok: \(ok) in \(String(format: "%.3f", Date().timeIntervalSince(t0)))s")

// Read back with a fresh PDFDocument.
let back = PDFDocument(url: outURL)!
let annots = back.page(at: 0)!.annotations
print("annotations on p1 after reload: \(annots.count)")
for a in annots {
    let kv = a.annotationKeyValues
    let irt = kv[key("/IRT")] as? PDFAnnotation
    print("- \(a.type ?? "?") T=\(a.userName ?? "-") NM=\(kv[key("/NM")] ?? "-") IRT->\(irt.map { ($0.annotationKeyValues[key("/NM")] as? String) ?? "annot" } ?? "-") RT=\(kv[key("/RT")] ?? "-") State=\(kv[key("/State")] ?? "-")/\(kv[key("/StateModel")] ?? "-") M=\(a.modificationDate.map { "\($0)" } ?? "-") CreationDate=\(kv[key("/CreationDate")] ?? "-") contents=\(a.contents ?? "-")")
}

// Was the save incremental? An incremental save keeps the original bytes as a prefix.
let orig = try Data(contentsOf: inURL), saved = try Data(contentsOf: outURL)
print("original \(orig.count) B, saved \(saved.count) B, original is byte prefix of saved: \(saved.starts(with: orig))")
