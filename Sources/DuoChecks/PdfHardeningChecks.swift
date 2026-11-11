import CoreGraphics
import DuoControl
import DuoKit
import DuoSearch
import Foundation
import PDFKit

// The PDF parser's edge cases (from a 48-file corpus run): junk in front of %PDF-, a startxref far from the end, a damaged compressed stream.

@MainActor func pdfHardeningChecks(scratch: URL) throws {
    print("PDF parser edge cases: junk before the header, startxref far from the end, damaged Flate data")
    let fm = FileManager.default
    func annots(_ u: URL, _ page: Int = 0) -> Int { PDFDocument(url: u)?.page(at: page)?.annotations.count ?? -1 }
    let box = [CGRect(x: 72, y: 698, width: 150, height: 14)]

    // Junk in front: offsets count from %PDF-, the way Acrobat and CoreGraphics read them.
    let base = scratch.appending(path: "base.pdf")
    cgFixture(base)
    let clean = try Data(contentsOf: base)
    let junk = Data("JUNKJUNKJUNKJUNKJUNKJUNKJUNK\r\n".utf8)   // 30 bytes
    check(junk.count == 30, "the junk is 30 bytes")
    let pre = scratch.appending(path: "prefixed.pdf")
    try (junk + clean).write(to: pre)
    check(PDFDocument(url: pre)?.pageCount == 4 && CGPDFDocument(pre as CFURL)?.numberOfPages == 4 && ((try? PdfComments.pageCount(pre)) ?? 0) == 4, "a file with 30 junk bytes before %PDF- opens in PDFKit, CGPDF and Duo's parser")
    let original = try Data(contentsOf: pre)
    let w = try PdfComments.add(pre, page: 1, quads: box, author: "geoff", text: "after junk")
    let after = try Data(contentsOf: pre)
    check(after.starts(with: original) && after.count > original.count, "the update is appended after the junk-prefixed original")
    check(annots(pre) == 1 && CGPDFDocument(pre as CFURL)?.numberOfPages == 4, "PDFKit sees the annotation and CGPDF opens it (\(annots(pre)))")
    let th = try PdfComments.threads(pre)
    check(th.count == 1 && th[0].id == w.id && th[0].root.text == "after junk" && abs(th[0].rects[0].minX - 72) < 0.01, "Duo reads the thread back")
    _ = try PdfComments.reply(pre, to: w.id, author: "claude", text: "ok")
    check(try PdfComments.threads(pre)[0].items.count == 2 && annots(pre) == 2, "a second update on top of it reads back as well")

    // Offsets that count from byte 0 of the file (a writer that ignored the junk): either read that way or refused cleanly.
    func handMade(junkBefore: Int, absolute: Bool) -> Data {
        var out = Data(String(repeating: "J", count: junkBefore).utf8)
        let h = out.count
        out.append(Data("%PDF-1.4\n".utf8))
        var offs: [Int: Int] = [:]
        let objs: [Int: String] = [1: "<< /Type /Catalog /Pages 2 0 R >>", 2: "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                                   3: "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>"]
        for n in objs.keys.sorted() { offs[n] = out.count - (absolute ? 0 : h); out.append(Data("\(n) 0 obj\n\(objs[n]!)\nendobj\n".utf8)) }
        let x = out.count - (absolute ? 0 : h)
        var t = "xref\n0 4\n0000000000 65535 f \n"
        for n in 1...3 { t += String(format: "%010d 00000 n \n", offs[n]!) }
        t += "trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n\(x)\n%%EOF\n"
        out.append(Data(t.utf8))
        return out
    }
    for (name, absolute) in [("counted from %PDF-", false), ("counted from byte 0", true)] {
        let u = scratch.appending(path: "hand-\(absolute).pdf")
        try handMade(junkBefore: 30, absolute: absolute).write(to: u)
        let before = try Data(contentsOf: u)
        do {
            _ = try PdfComments.add(u, page: 1, quads: [CGRect(x: 10, y: 10, width: 100, height: 12)], author: "g", text: "t")
            check(annots(u) == 1 && CGPDFDocument(u as CFURL)?.numberOfPages == 1 && ((try? PdfComments.threads(u)) ?? []).count == 1, "30 junk bytes, offsets \(name): appended, and PDFKit and CGPDF open it with the annotation")
        } catch {
            check(((try? Data(contentsOf: u)) ?? Data()) == before && "\(error)".contains("cross-reference"), "30 junk bytes, offsets \(name): refused cleanly and the file is untouched (\(error))")
        }
    }

    // startxref beyond the last 2 KB.
    let tail = scratch.appending(path: "tail.pdf")
    try (clean + Data(String(repeating: "% trailing padding line\n", count: 400).utf8)).write(to: tail)   // ~9 KB after %%EOF
    check(try PdfComments.pageCount(tail) == 4, "startxref 9 KB from the end of the file is found")
    _ = try PdfComments.add(tail, page: 1, quads: box, author: "geoff", text: "after padding")
    check(try PdfComments.threads(tail).count == 1 && annots(tail) == 1, "…and a comment is appended and read back")

    // A damaged Flate stream fails with a message, and returns.
    var bad = Data("%PDF-1.5\n".utf8)
    let at = bad.count
    let garbage = Data([0x78, 0x9C, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
    bad.append(Data("1 0 obj\n<< /Type /XRef /Size 2 /W [1 2 1] /Root 1 0 R /Filter /FlateDecode /Length \(garbage.count) >>\nstream\n".utf8))
    bad.append(garbage)
    bad.append(Data("\nendstream\nendobj\nstartxref\n\(at)\n%%EOF\n".utf8))
    let badURL = scratch.appending(path: "damaged.pdf")
    try bad.write(to: badURL)
    let started = Date()
    do { _ = try PdfComments.threads(badURL); check(false, "a damaged compressed cross-reference stream is refused") }
    catch { check("\(error)".contains("damaged") && Date().timeIntervalSince(started) < 5, "a damaged compressed stream is refused with a message, at once (\(error))") }
}
