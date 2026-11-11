import Compression
import CoreGraphics
import CoreText
import DuoControl
import DuoKit
import DuoSearch
import Foundation
import PDFKit

// DL-335 / DL-334: comments appended to a PDF as standard annotations in one incremental update, and what `doc read` gives a session.
// Fixtures are built here: a CGContext PDF (text pages, an image-only page, a chart page), hand-written classic-xref PDFs (one with an
// Acrobat-style thread in an indirect /Annots array), and a hand-written xref-stream + object-stream PDF (Flate, PNG-up predictor).

// MARK: Fixtures

func cgFixture(_ url: URL, encrypted: Bool = false) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    var aux: [CFString: Any] = [:]
    if encrypted { aux[kCGPDFContextUserPassword] = "user"; aux[kCGPDFContextOwnerPassword] = "owner" }
    let ctx = CGContext(url as CFURL, mediaBox: &box, aux as CFDictionary)!
    func line(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 14) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let a = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(a), ctx)
    }
    // 1: a short text page
    ctx.beginPDFPage(nil)
    line("Alpha beta gamma delta epsilon", 72, 700)
    line("The second line has a unique phrase: turquoise walrus.", 72, 676)
    ctx.endPDFPage()
    // 2: a long text page (over 400 characters)
    ctx.beginPDFPage(nil)
    for i in 0..<14 { line("Line \(i + 1) of the long page: the quick brown fox jumps over the lazy dog again and again.", 72, CGFloat(740 - i * 20), size: 11) }
    ctx.endPDFPage()
    // 3: an image and no text
    ctx.beginPDFPage(nil)
    let cs = CGColorSpaceCreateDeviceRGB()
    let bm = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for i in 0..<8 { bm.setFillColor(red: CGFloat(i) / 8, green: 0.4, blue: 1 - CGFloat(i) / 8, alpha: 1); bm.fill(CGRect(x: i * 8, y: 0, width: 8, height: 64)) }
    ctx.draw(bm.makeImage()!, in: CGRect(x: 100, y: 300, width: 400, height: 300))
    ctx.endPDFPage()
    // 4: a chart of filled bars with a short title
    ctx.beginPDFPage(nil)
    line("Quarterly revenue, a short chart title", 72, 720)
    for i in 0..<8 { ctx.setFillColor(red: 0.2, green: CGFloat(i) / 8, blue: 0.7, alpha: 1); ctx.fill(CGRect(x: 80 + i * 55, y: 100, width: 40, height: 60 + i * 40)) }
    ctx.endPDFPage()
    ctx.closePDF()
}

/// A classic-xref PDF from numbered object bodies (`"<< … >>"`, or a stream built with `streamBody`).
private func classicPDF(_ objs: [Int: String], catalogExtra: String = "") -> Data {
    var out = Data("%PDF-1.4\n".utf8)
    var offsets: [Int: Int] = [:]
    for n in objs.keys.sorted() {
        offsets[n] = out.count
        out.append(Data("\(n) 0 obj\n\(objs[n]!)\nendobj\n".utf8))
    }
    let size = (objs.keys.max() ?? 0) + 1
    let xref = out.count
    var t = "xref\n0 \(size)\n0000000000 65535 f \n"
    for n in 1..<size { t += offsets[n].map { String(format: "%010d 00000 n \n", $0) } ?? "0000000000 00000 f \n" }
    t += "trailer\n<< /Size \(size) /Root 1 0 R /ID [<0123456789ABCDEF0123456789ABCDEF> <0123456789ABCDEF0123456789ABCDEF>] >>\nstartxref\n\(xref)\n%%EOF\n"
    out.append(Data(t.utf8))
    return out
}
private func streamBody(_ content: String, extra: String = "") -> String { "<< /Length \(content.utf8.count)\(extra) >>\nstream\n\(content)\nendstream" }

private let helloContent = "BT /F1 18 Tf 72 700 Td (Hello hello world of PDF comments) Tj ET"
private let helloFont = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

/// One page, with an Acrobat-style thread: a Highlight (6), a reply (8), a reply to the reply (10), a Group member (11), and an Accepted
/// state reply (9), all in an INDIRECT /Annots array (7). Dates carry a time zone.
private func threadFixture(perms: String = "") -> Data {
    classicPDF([
        1: "<< /Type /Catalog /Pages 2 0 R\(perms) >>",
        2: "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        3: "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> /Annots 7 0 R >>",
        4: streamBody(helloContent), 5: helloFont,
        6: "<< /Type /Annot /Subtype /Highlight /Rect [72 695 300 715] /QuadPoints [72 715 300 715 72 695 300 695] /Contents (Original comment) /T (Ann Reviewer) /NM (x1) /M (D:20260101120000+01'00') /P 3 0 R >>",
        7: "[6 0 R 8 0 R 9 0 R 10 0 R 11 0 R]",
        8: "<< /Type /Annot /Subtype /Text /Rect [300 700 320 720] /Contents (First reply) /T (Bob) /NM (x1.2) /M (D:20260102090000Z) /IRT 6 0 R /RT /R /P 3 0 R >>",
        9: "<< /Type /Annot /Subtype /Text /Rect [300 700 320 720] /F 32 /Contents (Accepted) /T (Bob) /M (D:20260103090000Z) /IRT 6 0 R /StateModel (Review) /State (Accepted) /P 3 0 R >>",
        10: "<< /Type /Annot /Subtype /Text /Rect [300 700 320 720] /Contents (Reply to the reply) /T (Cy) /M (D:20260104090000Z) /IRT 8 0 R /RT /R /P 3 0 R >>",
        11: "<< /Type /Annot /Subtype /Text /Rect [300 700 320 720] /Contents (Grouped, not a reply) /T (Di) /M (D:20260105090000Z) /IRT 6 0 R /RT /Group /P 3 0 R >>",
    ])
}

private func zlib(_ raw: [UInt8]) -> [UInt8] {
    var dst = [UInt8](repeating: 0, count: raw.count + 1024)
    let n = compression_encode_buffer(&dst, dst.count, raw, raw.count, nil, COMPRESSION_ZLIB)
    var a: UInt32 = 1, b: UInt32 = 0
    for x in raw { a = (a + UInt32(x)) % 65521; b = (b + a) % 65521 }
    let adler = b << 16 | a
    return [0x78, 0x9C] + dst[0..<n] + [UInt8(adler >> 24), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)]
}

/// A PDF 1.5 file: catalog (1) and contents (4) direct, Pages (2) and the page (3) inside object stream 5, the cross-reference stream
/// (6) Flate-compressed with the PNG-up predictor (/W [1 3 2], /DecodeParms /Predictor 12 /Columns 6).
private func xrefStreamPDF() -> Data {
    var out = [UInt8]("%PDF-1.5\n".utf8)
    func obj(_ n: Int, _ body: [UInt8]) -> Int { let at = out.count; out += [UInt8]("\(n) 0 obj\n".utf8) + body + [UInt8]("\nendobj\n".utf8); return at }
    let o1 = obj(1, [UInt8]("<< /Type /Catalog /Pages 2 0 R >>".utf8))
    let content = [UInt8](helloContent.utf8)
    let o4 = obj(4, [UInt8]("<< /Length \(content.count) >>\nstream\n".utf8) + content + [UInt8]("\nendstream".utf8))
    let pages = "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
    let page = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>"
    let header = "2 0 3 \(pages.utf8.count + 1) "
    let packed = [UInt8]((header + pages + " " + page).utf8)
    let z5 = zlib(packed)
    let o5 = obj(5, [UInt8]("<< /Type /ObjStm /N 2 /First \(header.utf8.count) /Filter /FlateDecode /Length \(z5.count) >>\nstream\n".utf8) + z5 + [UInt8]("\nendstream".utf8))
    let o6 = out.count
    // Rows: type, offset (3 bytes), gen/index (2 bytes).
    func row(_ t: Int, _ a: Int, _ b: Int) -> [UInt8] { [UInt8(t), UInt8(a >> 16 & 0xFF), UInt8(a >> 8 & 0xFF), UInt8(a & 0xFF), UInt8(b >> 8 & 0xFF), UInt8(b & 0xFF)] }
    let rows = [row(0, 0, 0xFFFF), row(1, o1, 0), row(2, 5, 0), row(2, 5, 1), row(1, o4, 0), row(1, o5, 0), row(1, o6, 0)]
    var filtered: [UInt8] = []
    var prev = [UInt8](repeating: 0, count: 6)
    for r in rows { filtered.append(2); filtered += zip(r, prev).map { $0 &- $1 }; prev = r }
    let z6 = zlib(filtered)
    out += [UInt8]("6 0 obj\n<< /Type /XRef /Size 7 /W [1 3 2] /Root 1 0 R /Filter /FlateDecode /DecodeParms << /Predictor 12 /Columns 6 >> /Length \(z6.count) >>\nstream\n".utf8) + z6
    out += [UInt8]("\nendstream\nendobj\nstartxref\n\(o6)\n%%EOF\n".utf8)
    return Data(out)
}

// MARK: Checks

@MainActor func pdfChecks() throws {
    print("comments appended to PDF files, and what doc read gives a session (DL-334, DL-335)")
    let scratch = FileManager.default.temporaryDirectory.appending(path: "duo-pdf-checks-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let now = ISO8601DateFormatter().date(from: "2026-11-10T09:30:00Z")!
    let later = now.addingTimeInterval(60)
    let backups = scratch.appending(path: "backups")

    func bytes(_ u: URL) -> Data { (try? Data(contentsOf: u)) ?? Data() }
    func annotCount(_ u: URL, page: Int = 0) -> Int { PDFDocument(url: u)?.page(at: page)?.annotations.count ?? -1 }
    func count(_ needle: String, in d: Data) -> Int { String(decoding: d, as: UTF8.self).components(separatedBy: needle).count - 1 }

    // MARK: classic xref, made by CoreGraphics
    let classic = scratch.appending(path: "classic.pdf")
    cgFixture(classic)
    let orig = bytes(classic)
    let pc = try PdfComments.pageCount(classic)
    check(PDFDocument(url: classic)?.pageCount == 4 && pc == 4, "the CoreGraphics fixture has four pages, read by PDFKit and by Duo's page tree")
    check(try PdfComments.threads(classic).isEmpty, "it starts with no comment threads")

    let w1 = try PdfComments.add(classic, page: 1, quads: [CGRect(x: 72, y: 698, width: 150, height: 16), CGRect(x: 72, y: 676, width: 100, height: 16)],
                                 author: "Geoff Q", text: "@claude is this right?\nSecond line, with “quotes” and ünïcode ✓.", now: now, backups: backups)
    check(w1.id == "c1", "the first comment is c1")
    let d1 = bytes(classic)
    check(d1.count > orig.count && d1.starts(with: orig), "after add, the original is an exact byte prefix (\(d1.count - orig.count) bytes appended)")
    let t1 = try PdfComments.threads(classic)
    check(t1.count == 1 && t1[0].id == "c1" && t1[0].page == 1 && t1[0].place == "page 1" && t1[0].kind == "Highlight" && t1[0].rects.count == 2 && !t1[0].resolved,
          "the thread reads back: id, page, place, kind, two quad rects, open")
    check(t1[0].root.author == "Geoff Q" && t1[0].root.date == "2026-11-10T09:30:00" && t1[0].root.text == "@claude is this right?\nSecond line, with “quotes” and ünïcode ✓.",
          "…with its author, ISO date and text (non-ASCII survives as UTF-16BE)")
    check(abs(t1[0].rects[0].minX - 72) < 0.01 && abs(t1[0].rects[0].width - 150) < 0.01 && abs(t1[0].rects[0].minY - 698) < 0.01, "…and the quads in page space")
    check(PDFDocument(url: classic) != nil && annotCount(classic) == 1 && CGPDFDocument(classic as CFURL)?.numberOfPages == 4, "the result opens in PDFKit (one annotation on page 1) and CGPDFDocument")
    check(PDFDocument(url: classic)?.page(at: 0)?.annotations.first?.type == "Highlight", "PDFKit sees a Highlight")
    check(count("%%EOF", in: d1) == count("%%EOF", in: orig) + 1 && count("startxref", in: d1) == count("startxref", in: orig) + 1, "one xref section was appended")
    check(count("/Prev", in: d1) == count("/Prev", in: orig) + 1, "…chained to the previous with /Prev")

    // The routing adapter and the turn
    let rv = try AppModel.pdfReviewThreads(classic)
    check(rv.count == 1 && rv[0].id == "c1" && rv[0].comments.first?.author == "geoff-q" && rv[0].comments.first?.mentionsClaude == true, "routing sees it as a Review thread that names @claude, signed geoff-q")
    check(rv[0].anchor == "Alpha beta gamma delta epsilon The second line has a unique phrase: turquoise walrus." || (rv[0].anchor ?? "").contains("Alpha"),
          "the anchor is the highlighted text, read by PDFKit (\(rv[0].anchor ?? "nil"))")
    let turn = AppModel.pdfTurnText(name: "Paper.pdf", place: "page 1", thread: rv[0])
    check(turn.hasPrefix("@claude comment in Paper.pdf, page 1 (thread c1), from geoff-q") && turn.contains("duo2 comment reply c1 \"<text>\" --file \"Paper.pdf\"") && !turn.contains("line 0"),
          "the turn names the file and page and tells Claude to reply with --file")

    // reply
    let r1 = try PdfComments.reply(classic, to: "c1", author: "claude", text: "Yes: it is.", now: later, backups: backups)
    let d2 = bytes(classic)
    check(r1.id == "c1.2" && d2.starts(with: d1) && d2.starts(with: orig), "a reply is c1.2, and the file before it is an exact prefix")
    var t2 = try PdfComments.threads(classic)
    check(t2.count == 1 && t2[0].items.count == 2 && t2[0].items[1].author == "claude" && t2[0].items[1].id == "c1.2" && t2[0].items[1].text == "Yes: it is.", "the reply is in the thread")
    check(annotCount(classic) == 2 && PDFDocument(url: classic) != nil, "PDFKit opens it and counts the reply as an annotation")
    check(count("/Prev", in: d2) == count("/Prev", in: orig) + 2, "a second append chains /Prev again; both appends read back")
    let r2 = try PdfComments.reply(classic, to: "c1", author: "Geoff Q", text: "Thanks.", now: later)
    check(r2.id == "c1.3", "the next reply is c1.3")

    // resolve and reopen
    let before = bytes(classic)
    _ = try PdfComments.resolve(classic, thread: "c1", resolved: true, author: "Geoff Q", now: later.addingTimeInterval(60))
    check(bytes(classic).starts(with: before), "resolve leaves the earlier bytes alone")
    t2 = try PdfComments.threads(classic)
    check(t2[0].resolved && t2[0].items.count == 3, "Close: the thread is resolved and the state reply is not a comment")
    check((try AppModel.pdfReviewThreads(classic))[0].closed, "…and the review model sees it closed")
    _ = try PdfComments.resolve(classic, thread: "c1", resolved: false, author: "Geoff Q", now: later.addingTimeInterval(120))
    check(try PdfComments.threads(classic)[0].resolved == false, "Reopen: the thread is open again (the latest state reply wins)")
    _ = try PdfComments.resolve(classic, thread: "c1", resolved: true, author: "claude", now: later.addingTimeInterval(180))
    check(try PdfComments.threads(classic)[0].resolved, "…and closes again")
    check(try PdfComments.resolve(classic, thread: "c1", resolved: true, author: "x").summary.contains("already closed"), "closing a closed thread says so")

    // a note on a spot, a second thread, delete
    let w2 = try PdfComments.add(classic, page: 2, point: CGPoint(x: 500, y: 700), author: "claude", text: "A note on the long page.", now: later)
    let kinds = try PdfComments.threads(classic)
    check(w2.id == "c2" && kinds.first { $0.id == "c2" }?.kind == "Text" && annotCount(classic, page: 1) == 1, "a Text note on page 2 is c2")
    let beforeDelete = bytes(classic)
    _ = try PdfComments.delete(classic, thread: "c1")
    check(bytes(classic).starts(with: beforeDelete) && bytes(classic).starts(with: orig), "delete is an update too: the earlier bytes stay a prefix")
    let left = try PdfComments.threads(classic)
    check(left.count == 1 && left[0].id == "c2" && annotCount(classic, page: 0) == 0 && annotCount(classic, page: 1) == 1, "delete drops the thread (root, replies, state replies) from the page's /Annots")
    let w3 = try PdfComments.add(classic, page: 1, quads: [CGRect(x: 72, y: 698, width: 50, height: 16)], author: "x", text: "again", now: later)
    check(w3.id == "c1", "ids are unique in the file, and a deleted thread's id is free again")

    // refusals
    check((try? PdfComments.add(classic, page: 9, quads: [.zero], author: "x", text: "y")) == nil, "a page that isn't there is refused")
    check((try? PdfComments.reply(classic, to: "nope", author: "x", text: "y")) == nil, "a reply to a thread that isn't there is refused")
    let kept = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []
    check(kept.filter { $0.hasSuffix("classic.pdf") }.count == 1 && kept.contains { (try? Data(contentsOf: backups.appending(path: $0))) == orig }, "one backup of the file as it was is kept before the first write, and later writes add no second copy")

    // MARK: encrypted
    let enc = scratch.appending(path: "enc.pdf")
    cgFixture(enc, encrypted: true)
    let encBefore = bytes(enc)
    check(count("/Encrypt", in: encBefore) >= 1, "the encrypted fixture has /Encrypt")
    do { _ = try PdfComments.add(enc, page: 1, quads: [CGRect(x: 1, y: 1, width: 5, height: 5)], author: "x", text: "y"); check(false, "an encrypted PDF is refused") }
    catch { check("\(error)".contains("encrypted"), "an encrypted PDF is refused, and says why (\(error))") }
    check(bytes(enc) == encBefore, "…and the file is untouched")

    // MARK: certification
    let cert = scratch.appending(path: "cert.pdf")
    let certData = classicPDF([
        1: "<< /Type /Catalog /Pages 2 0 R /Perms << /DocMDP 6 0 R >> >>", 2: "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        3: "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
        6: "<< /Type /Sig /Filter /Adobe.PPKLite /Reference [<< /Type /SigRef /TransformMethod /DocMDP /TransformParams << /Type /TransformParams /P 1 /V /1.2 >> >>] >>",
    ])
    try certData.write(to: cert)
    do { _ = try PdfComments.add(cert, page: 1, point: CGPoint(x: 10, y: 10), author: "x", text: "y"); check(false, "a DocMDP P=1 PDF is refused") }
    catch { check("\(error)".contains("DocMDP"), "a certified (DocMDP P 1) PDF is refused (\(error))") }
    let cert3 = scratch.appending(path: "cert3.pdf")
    try Data(String(decoding: certData, as: UTF8.self).replacingOccurrences(of: "/P 1 /V", with: "/P 3 /V").utf8).write(to: cert3)
    check((try? PdfComments.add(cert3, page: 1, point: CGPoint(x: 10, y: 10), author: "x", text: "y")) != nil, "…while DocMDP P 3 (annotations allowed) takes a comment")

    // MARK: a damaged cross-reference
    let broken = scratch.appending(path: "broken.pdf")
    var brokenText = String(decoding: orig, as: UTF8.self)
    if let r = brokenText.range(of: "startxref\n", options: .backwards) {
        let tail = brokenText[r.upperBound...]
        let num = tail.prefix { $0.isNumber }
        brokenText.replaceSubrange(r.upperBound..<tail.index(tail.startIndex, offsetBy: num.count), with: "7")
    }
    try Data(brokenText.utf8).write(to: broken)
    do { _ = try PdfComments.add(broken, page: 1, point: CGPoint(x: 10, y: 10), author: "x", text: "y"); check(false, "a file whose xref can't be read is refused") }
    catch { check(!"\(error)".isEmpty, "a file whose xref can't be read is refused, not guessed at (\(error))") }
    check(bytes(broken) == Data(brokenText.utf8), "…and left as it was")
    check((try? PdfComments.threads(URL(fileURLWithPath: "/nonexistent.pdf"))) == nil, "a missing file is an error")

    // MARK: an Acrobat-style thread in an indirect /Annots array
    let thr = scratch.appending(path: "thread.pdf")
    try threadFixture().write(to: thr)
    let thrOrig = bytes(thr)
    let ts = try PdfComments.threads(thr)
    check(ts.count == 1 && ts[0].id == "x1" && ts[0].items.map(\.id) == ["x1", "x1.2", "x1.3"], "an existing thread: the root, the reply and the reply to the reply (attached to the root); the /RT /Group member is not a reply (\(ts.first?.items.map(\.id) ?? []))")
    check(ts[0].resolved && ts[0].items[0].author == "Ann Reviewer" && ts[0].items[0].date == "2026-01-01T11:00:00" && ts[0].items[1].date == "2026-01-02T09:00:00",
          "…its Accepted state reply makes it resolved, and a +01:00 date is read as UTC")
    check(ts[0].items[2].id == "x1.3" && ts[0].items[2].text == "Reply to the reply", "…a reply with no /NM gets a synthesized id")
    _ = try PdfComments.resolve(thr, thread: "x1", resolved: false, author: "Geoff", now: now)
    let thrTail = String(decoding: bytes(thr).dropFirst(thrOrig.count), as: UTF8.self)
    check(bytes(thr).starts(with: thrOrig) && thrTail.contains("7 0 obj") && !thrTail.contains("\n3 0 obj"), "an indirect /Annots array is re-emitted as its own object; the page object is not rewritten")
    check(try PdfComments.threads(thr)[0].resolved == false, "…and Reopen beats the older Accepted")
    let w4 = try PdfComments.add(thr, page: 1, quads: [CGRect(x: 72, y: 695, width: 100, height: 20)], author: "claude", text: "second", now: now)
    let thrCount = try PdfComments.threads(thr).count
    check(w4.id == "c1" && thrCount == 2 && annotCount(thr) >= 2, "a comment added beside an existing thread: c1 (x1 is not a c-id), both read, PDFKit opens it")
    try threadFixture(perms: " /Perms << /DocMDP 6 0 R >>").write(to: scratch.appending(path: "t2.pdf"))   // object 6 is an annotation here: not a signature, so no refusal
    check((try? PdfComments.threads(scratch.appending(path: "t2.pdf"))) != nil, "a /Perms entry that isn't a signature doesn't stop reading")

    // MARK: xref stream + object stream
    let xs = scratch.appending(path: "xrefstream.pdf")
    try xrefStreamPDF().write(to: xs)
    let xsOrig = bytes(xs)
    let xpc = try PdfComments.pageCount(xs)
    check(PDFDocument(url: xs)?.pageCount == 1 && xpc == 1, "the xref-stream fixture opens in PDFKit and Duo finds its page through the object stream")
    check(try PdfComments.threads(xs).isEmpty, "it has no threads")
    let x1 = try PdfComments.add(xs, page: 1, quads: [CGRect(x: 72, y: 695, width: 200, height: 20)], author: "Geoff Q", text: "On the compressed page.", now: now, backups: backups)
    let xd1 = bytes(xs)
    let xTail = String(decoding: xd1.dropFirst(xsOrig.count), as: UTF8.self)
    check(x1.id == "c1" && xd1.starts(with: xsOrig), "add to the xref-stream file: c1, and the original is a prefix")
    check(xTail.contains("/Type /XRef") && xTail.contains("/W [1 4 2]") && !xTail.contains("\ntrailer") && !xTail.contains("\nxref\n"), "…and the update is an xref stream, not a classic table")
    check(xTail.contains("/Prev \(String(decoding: xsOrig.suffix(40), as: UTF8.self).components(separatedBy: "startxref\n")[1].components(separatedBy: "\n")[0])"), "…with /Prev at the old startxref")
    check(annotCount(xs) == 1 && CGPDFDocument(xs as CFURL)?.numberOfPages == 1, "PDFKit and CGPDFDocument open it; one annotation")
    _ = try PdfComments.reply(xs, to: "c1", author: "claude", text: "ok", now: later)
    _ = try PdfComments.resolve(xs, thread: "c1", resolved: true, author: "claude", now: later.addingTimeInterval(1))
    let xt = try PdfComments.threads(xs)
    check(xt.count == 1 && xt[0].items.count == 2 && xt[0].resolved && bytes(xs).starts(with: xd1), "a second and third xref-stream update chain, and read back")
    _ = try PdfComments.delete(xs, thread: "c1")
    check(try PdfComments.threads(xs).isEmpty && annotCount(xs) == 0 && bytes(xs).starts(with: xsOrig), "delete works on it too")

    // MARK: --at (the app's placement)
    let place1 = try AppModel.pdfPlace(classic, at: "turquoise walrus")
    check(place1.page == 1 && (place1.quads?.count ?? 0) >= 1, "--at finds a text that appears once and highlights its lines")
    do { _ = try AppModel.pdfPlace(classic, at: "the quick brown fox"); check(false, "--at a text that appears many times is refused") }
    catch { check("\(error)".contains("14 times"), "--at a text that appears many times is refused, saying how many (\(error))") }
    do { _ = try AppModel.pdfPlace(classic, at: "no such words anywhere"); check(false, "--at a text that isn't there is refused") }
    catch { check("\(error)".contains("doesn't appear"), "--at a text that isn't there is refused") }
    let place2 = try AppModel.pdfPlace(classic, at: "page 3")
    check(place2.page == 3 && place2.quads == nil && place2.point != nil && abs(place2.point!.x - 572) < 0.5 && abs(place2.point!.y - 752) < 0.5, "--at \"page N\" is a note at the top right of the page's crop box")
    let place3 = try AppModel.pdfPlace(classic, at: "page 2 Line 7 of the long page")
    check(place3.page == 2 && place3.quads?.isEmpty == false, "--at \"page N <text>\" matches on that page only")
    check((try? AppModel.pdfPlace(classic, at: "page 1 Line 7 of the long page")) == nil, "…and fails when the text is on another page")

    // MARK: doc read
    let fresh = scratch.appending(path: "fresh.pdf")
    cgFixture(fresh)
    let rr = try PdfRead.read(fresh)
    check(rr.pages == 4 && (1...4).allSatisfy { rr.text.contains("--- page \($0) ---\n") }, "doc read puts a `--- page N ---` line before each page")
    check(rr.text.contains("Alpha beta gamma delta epsilon") && rr.text.contains("turquoise walrus"), "…then the page's text")
    check(rr.look == [PdfRead.Look(page: 3, reason: "no text layer"), PdfRead.Look(page: 4, reason: "mostly a figure")], "the pages to look at: the image page has no text layer, the chart is a figure; text pages are not listed (\(rr.look))")
    check(rr.text.contains("- page 3: no text layer") && rr.text.contains("- page 4: mostly a figure") && !rr.text.contains("- page 1:") && !rr.text.contains("- page 2:"), "…listed with the reason")
    check(rr.text.hasSuffix("Render one with `duo2 pdf render fresh.pdf <page>` and read the PNG.\n"), "…and the closing line names the render verb")
    let png = try PdfRead.render(fresh, page: 4, width: 600)
    let rep = NSBitmapImageRep(data: png)
    check(png.starts(with: [0x89, 0x50, 0x4E, 0x47]) && rep?.pixelsWide == 600 && rep?.pixelsHigh == 776, "pdf render makes a 600 px wide PNG of a page")
    check((try? PdfRead.render(fresh, page: 5)) == nil, "…and refuses a page that isn't there")
    check(DuoAction.all.contains { $0.id == .pdfRender } && ActionID.pdfRender.action.args.contains("<page>"), "pdf render is an action in the registry")
    try pdfHighlightChecks(scratch: scratch)
    try pdfViewerChecks(scratch: scratch)
}
