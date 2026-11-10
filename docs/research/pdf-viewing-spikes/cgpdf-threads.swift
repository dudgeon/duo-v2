// Spike (research/pdf-viewing, F-644): PDFKit hides /IRT and /State from annotationKeyValues,
// so can Core Graphics' CGPDF dictionaries rebuild the comment threads natively?
// Usage: swift cgpdf-threads.swift <in.pdf>
import Foundation
import CoreGraphics

let doc = CGPDFDocument(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL)!
func str(_ d: CGPDFDictionaryRef, _ k: String) -> String? {
    var s: CGPDFStringRef?
    if CGPDFDictionaryGetString(d, k, &s), let s, let c = CGPDFStringCopyTextString(s) { return c as String }
    var n: UnsafePointer<CChar>?
    if CGPDFDictionaryGetName(d, k, &n), let n { return "/" + String(cString: n) }
    return nil
}
for p in 1...doc.numberOfPages {
    guard let page = doc.page(at: p)?.dictionary else { continue }
    var annots: CGPDFArrayRef?
    guard CGPDFDictionaryGetArray(page, "Annots", &annots), let annots else { continue }
    var dicts: [CGPDFDictionaryRef] = []
    for i in 0..<CGPDFArrayGetCount(annots) {
        var d: CGPDFDictionaryRef?
        if CGPDFArrayGetDictionary(annots, i, &d), let d { dicts.append(d) }
    }
    // A dictionary reached through /IRT is the same CGPDFDictionaryRef as the one in /Annots,
    // so pointer identity rebuilds the tree without needing object numbers.
    for d in dicts {
        var parent: CGPDFDictionaryRef?
        let hasIRT = CGPDFDictionaryGetDictionary(d, "IRT", &parent)
        let parentNM = parent.flatMap { str($0, "NM") } ?? "-"
        let parentIndex = parent.flatMap { p in dicts.firstIndex(where: { $0 == p }) }.map(String.init) ?? "-"
        print("p\(p) \(str(d, "Subtype") ?? "?") NM=\(str(d, "NM") ?? "-") T=\(str(d, "T") ?? "-") IRT=\(hasIRT ? "\(parentNM) (index \(parentIndex))" : "-") RT=\(str(d, "RT") ?? "-") State=\(str(d, "State") ?? "-")/\(str(d, "StateModel") ?? "-") CreationDate=\(str(d, "CreationDate") ?? "-")")
    }
}
