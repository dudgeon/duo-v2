// Spike (research/pdf-viewing, F-644): what PDFKit reads from a PDF's comment thread, and
// what a PDFKit save does to a thread it didn't write (e.g. one made in Acrobat).
// Usage: swift readback.swift <in.pdf> [<resaved.pdf>]
import Foundation
import PDFKit

let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
func key(_ s: String) -> PDFAnnotationKey { PDFAnnotationKey(rawValue: s) }
let annots = doc.page(at: 0)!.annotations
for a in annots {
    var kv: [String: Any] = [:]
    for (k, v) in a.annotationKeyValues { kv["\(k.base)"] = v }
    let keys = kv.keys.sorted().joined(separator: " ")
    var irt = "-"
    if let v = kv["/IRT"] { irt = (v as? PDFAnnotation).map { "annotation NM=\($0.annotationKeyValues[AnyHashable("/NM")] ?? "?")" } ?? "\(type(of: v))" }
    print("\(a.type ?? "?") T=\(a.userName ?? "-") NM=\(kv["/NM"] ?? "-") IRT=\(irt) State=\(kv["/State"] ?? "-") hidden=\(a.shouldDisplay == false)\n    keys: \(keys)")
}
if CommandLine.arguments.count > 2 {
    // Touch an unrelated annotation, then save with PDFKit, as an editor would.
    annots.first?.contents = (annots.first?.contents ?? "") + " (edited)"
    let out = URL(fileURLWithPath: CommandLine.arguments[2])
    _ = doc.write(to: out)
    let raw = try Data(contentsOf: out)
    let s = String(decoding: raw, as: UTF8.self)
    print("after PDFKit resave: /IRT count \(s.components(separatedBy: "/IRT").count - 1), /State count \(s.components(separatedBy: "/State ").count - 1), annotations \(PDFDocument(url: out)!.page(at: 0)!.annotations.count)")
}
