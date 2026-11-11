import AppKit
import CoreGraphics
import DuoControl
import DuoKit
import DuoSearch
import Foundation
import PDFKit

// Highlights land on the text they name (the `--at` quads, the drawn highlight, the anchor read back), on a CoreGraphics page and on a
// macOS-printed one (Fixtures/pdf/quartz-mono.pdf: Monaco at font size 1 under a 12x text matrix, a wrapped line split over two rows),
// where PDFKit's own selection boxes are wrong (a box taller than a row, an x that starts left of the page).

private func squash(_ s: String) -> String { s.filter { !$0.isWhitespace } }

/// The page drawn with its annotations at 2x into RGBA, origin bottom-left (so a pixel's page point is x/2, y/2).
private func renderedPage(_ url: URL, page: Int) -> (w: Int, h: Int, px: [UInt8])? {
    guard let pg = PDFDocument(url: url)?.page(at: page) else { return nil }
    let box = pg.bounds(for: .cropBox)
    let w = Int(box.width * 2), h = Int(box.height * 2)
    var px = [UInt8](repeating: 255, count: w * h * 4)
    let ok = px.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: 2, y: 2); ctx.translateBy(x: -box.minX, y: -box.minY)
        pg.draw(with: .cropBox, to: ctx)
        return true
    }
    return ok ? (w, h, px) : nil
}

/// Highlight yellow (1, 0.85, 0 multiplied onto white), page-space points of every such pixel, from a bitmap whose row 0 is the TOP.
private func yellow(_ r: (w: Int, h: Int, px: [UInt8])) -> [CGPoint] {
    var out: [CGPoint] = []
    for y in 0..<r.h { for x in 0..<r.w {
        let i = (y * r.w + x) * 4
        if r.px[i] > 220, r.px[i + 1] > 170, r.px[i + 2] < 110 { out.append(CGPoint(x: Double(x) / 2, y: Double(r.h - 1 - y) / 2)) }
    } }
    return out
}

@MainActor func pdfHighlightChecks(scratch: URL) throws {
    print("highlights land on the text they name (--at quads, the drawn highlight, the anchor)")
    let fm = FileManager.default
    let quartz = repoRoot().appending(path: "Fixtures/pdf/quartz-mono.pdf")
    check(fm.fileExists(atPath: quartz.path), "the macOS-printed fixture is in Fixtures/pdf")

    struct Case { var file: String; var at: String; var page: Int; var rows: [(base: Double, x0: Double, x1: Double)]?; var why: String }
    // Monaco 12 pt: 7.2 pt per character from x = 16.6; a row's baseline is in the content stream (763.284 - 12 per row).
    func cols(_ a: Int, _ b: Int) -> (Double, Double) { (16.6 + 7.2 * Double(a), 16.6 + 7.2 * Double(b)) }
    let cases: [Case] = [
        Case(file: "q", at: "reading notes", page: 1, rows: [(763.284, cols(4, 17).0, cols(4, 17).1)], why: "a word mid-line"),
        Case(file: "q", at: "Section 2: findings and a short paragraph about method.", page: 1, rows: [(439.284, cols(0, 55).0, cols(0, 55).1)], why: "a whole line"),
        Case(file: "q", at: "Line 9: the quick brown fox jumps over the lazy dog, and the turquoise walrus watches.", page: 1,
             rows: [(559.284, cols(0, 80).0, cols(0, 80).1), (547.284, cols(0, 6).0, cols(0, 6).1)], why: "a phrase wrapping two rows"),
        Case(file: "q", at: "Line 8: the quick brown fox", page: 1, rows: [(583.284, cols(0, 27).0, cols(0, 27).1)], why: "the start of a line"),
        Case(file: "c", at: "unique phrase", page: 1, rows: nil, why: "a word mid-line (CoreGraphics)"),
        Case(file: "c", at: "The second line has a unique phrase: turquoise walrus.", page: 1, rows: nil, why: "a whole line (CoreGraphics)"),
        Case(file: "c", at: "Line 7 of the long page", page: 2, rows: nil, why: "a line's start on a later page (CoreGraphics)"),
    ]
    for (n, c) in cases.enumerated() {
        let url = scratch.appending(path: "hl\(n).pdf")
        if c.file == "q" { try? fm.removeItem(at: url); try fm.copyItem(at: quartz, to: url) } else { cgFixture(url) }
        let tag = "\(c.why): “\(c.at.prefix(30))”"
        do {
            let place = try AppModel.pdfPlace(url, at: c.at)
            let w = try PdfComments.add(url, page: place.page, quads: place.quads, point: place.point, author: "geoff", text: "x")
            let th = try AppModel.pdfThreads(url).first { $0.id == w.id }
            check(th != nil && squash(th!.anchor ?? "") == squash(c.at), "\(tag): the anchor reads back as the text (\(th?.anchor ?? "nil"))")
            let quads = th?.rects ?? []
            // The quads against the matched text.
            if let rows = c.rows {
                let ok = quads.count == rows.count && zip(quads.sorted { $0.minY > $1.minY }, rows).allSatisfy { q, r in
                    abs(q.minX - r.x0) < 1.5 && abs(q.maxX - r.x1) < 1.5 && q.minY > r.base - 5 && q.minY < r.base - 1 && q.maxY > r.base + 7 && q.maxY < r.base + 13 }
                check(ok, "\(tag): the quads are one box per row of the text, a line high (\(quads.map { "\(Int($0.minX))..\(Int($0.maxX)) y\(Int($0.minY))..\(Int($0.maxY))" }))")
            } else if let sel = PDFDocument(url: url)?.findString(c.at, withOptions: []).first, let pg = sel.pages.first {
                let lines = sel.selectionsByLine().map { $0.bounds(for: pg) }
                let u = lines.dropFirst().reduce(lines[0]) { $0.union($1) }, qu = quads.dropFirst().reduce(quads[0]) { $0.union($1) }
                check(abs(u.minX - qu.minX) < 0.5 && abs(u.maxX - qu.maxX) < 0.5 && abs(u.minY - qu.minY) < 0.5 && abs(u.maxY - qu.maxY) < 0.5, "\(tag): the quads' union is the selection's bounds within 0.5 pt (\(qu) vs \(u))")
            }
            // The drawn highlight against the matched text: every yellow pixel is on a text row, and most of each row's box is yellow.
            if let r = renderedPage(url, page: place.page - 1), let rows = c.rows {
                let ys = yellow(r)
                func inside(_ p: CGPoint) -> Bool { rows.contains { p.x > $0.x0 - 2 && p.x < $0.x1 + 2 && p.y > $0.base - 5 && p.y < $0.base + 13 } }
                let stray = ys.filter { !inside($0) }.count
                check(!ys.isEmpty && stray <= ys.count / 100, "\(tag): the drawn highlight lies on the text's rows (\(ys.count) yellow points, \(stray) outside)")
                let covered = rows.allSatisfy { row in
                    let box = CGRect(x: row.x0 + 1, y: row.base - 1, width: row.x1 - row.x0 - 2, height: 8)
                    let have = Set(ys.filter { box.contains($0) }.map { "\(Int($0.x * 2)),\(Int($0.y * 2))" }).count
                    return Double(have) > 0.55 * (box.width * 2) * (box.height * 2)
                }
                check(covered, "\(tag): …and it covers the text of every row")
            } else if let r = renderedPage(url, page: place.page - 1) {
                let ys = yellow(r)
                let hull = quads.dropFirst().reduce(quads[0]) { $0.union($1) }.insetBy(dx: -1.5, dy: -1.5)
                check(!ys.isEmpty && ys.allSatisfy { hull.contains($0) }, "\(tag): the drawn highlight lies inside the quads (\(ys.count) yellow points)")
            }
        } catch {
            check(false, "\(tag): add and read back (\(error))")
        }
    }
}
