import DuoControl
import DuoSearch
import Foundation
import PDFKit

// `duo2 comment …` on a PDF (DL-335): the comment, its replies and its resolved state are appended to the file as standard
// annotations in one incremental update (`PdfComments`), and @claude routing (`comment send`, `comment status`) reads the threads back
// as `Review.Thread`s, so the same turn, delivery and reply tracking as a Markdown or Office comment apply. The viewer's controls
// are a surface to design (Q-494); a viewer that has the file open listens for `.duoPdfChanged` and reloads.
extension Notification.Name {
    /// Posted after Duo changed a PDF on disk: `userInfo["path"]` is its path. A viewer showing that file reloads (slice 3).
    public static let duoPdfChanged = Notification.Name("DuoPdfChanged")
}

extension AppModel {
    static func isPdf(_ url: URL) -> Bool { PdfComments.isPdf(url) }

    /// Where the originals are kept before Duo appends a comment to a PDF.
    static var pdfBackups: URL { SupportFolder.duo.appendingPathComponent("PDF backups", isDirectory: true) }

    /// The file's threads with each highlight's anchor filled in: the page's text under the quads, as PDFKit reads it.
    public static func pdfThreads(_ url: URL) throws -> [PdfComments.Thread] {
        var threads = try PdfComments.threads(url)
        guard threads.contains(where: { ["Highlight", "Underline", "StrikeOut", "Squiggly"].contains($0.kind) }), let doc = PDFDocument(url: url) else { return threads }
        var pageRows: [Int: [PdfTextRows.Row]] = [:]
        for i in threads.indices where ["Highlight", "Underline", "StrikeOut", "Squiggly"].contains(threads[i].kind) {
            guard let page = doc.page(at: threads[i].page - 1) else { continue }
            let rows = pageRows[threads[i].page] ?? { let r = page.pageRef.map(PdfTextRows.rows) ?? []; pageRows[threads[i].page] = r; return r }()
            let parts = threads[i].rects.compactMap { r -> String? in
                // The page's own text rows first (PDFKit's rectangle selection misses on files whose layout it gets wrong), then PDFKit,
                // a hair inside the box so a neighbouring line's glyphs don't bleed in.
                if let t = rowText(rows, in: r) { return t }
                return page.selection(for: r.insetBy(dx: min(1, r.width / 4), dy: min(1.5, r.height / 4)))?.string }
                .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.filter { !$0.isEmpty }
            if !parts.isEmpty { threads[i].anchor = parts.joined(separator: " ") }
        }
        return threads
    }

    /// The characters of the page's text rows whose middle falls inside `r`, one string per row, nil when none do or any is not plain ASCII.
    static func rowText(_ rows: [PdfTextRows.Row], in r: CGRect) -> String? {
        var parts: [String] = []
        for row in rows where row.baseline > r.minY && row.baseline < r.maxY {
            var x = row.x0, s = ""
            for (c, a) in zip(row.text, row.advance) {
                if x + a / 2 >= r.minX, x + a / 2 <= r.maxX { s.append(c) }
                x += a
            }
            if s.contains(where: { !$0.isASCII }) { return nil }
            if !s.isEmpty { parts.append(s.trimmingCharacters(in: .whitespaces)) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// A PDF's threads as the review model sees them (as `officeReviewThreads`).
    public static func pdfReviewThreads(_ url: URL) throws -> [Review.Thread] {
        try pdfThreads(url).map { t in
            var comments = t.items.map {
                Review.Comment(author: Review.signatureName($0.author), date: $0.date.count >= 10 ? String($0.date.prefix(10)) : nil, id: $0.id, text: $0.text)
            }
            if t.resolved { comments.append(.closingMark) }
            return Review.Thread(id: t.id, anchor: t.anchor, comments: comments)
        }
    }

    /// The turn for a PDF thread: where it is (`page 3`), the quoted thread, and how to answer with `--file`.
    func pdfTurn(url: URL, thread id: String) -> String? {
        guard let pdf = (try? Self.pdfThreads(url))?.first(where: { $0.id == id }),
              let t = (try? Self.pdfReviewThreads(url))?.first(where: { $0.id == id }) else { return nil }
        return Self.pdfTurnText(name: displayPath(url), place: pdf.place, thread: t)
    }

    public static func pdfTurnText(name: String, place: String, thread t: Review.Thread) -> String {
        officeTurnText(name: name, place: place, thread: t)
    }

    /// Tell a viewer that has the file open to read it again.
    @MainActor static func pdfChanged(_ url: URL) {
        NotificationCenter.default.post(name: .duoPdfChanged, object: nil, userInfo: ["path": url.path])
    }

    // MARK: --at

    /// Where `comment add --at` points on a PDF: the quads of a text found once, or a spot on a page.
    public struct PdfPlace { public var page: Int; public var quads: [CGRect]?; public var point: CGPoint? }

    public static func pdfPlace(_ url: URL, at: String) throws -> PdfPlace {
        guard let doc = PDFDocument(url: url) else { throw PdfComments.Failure("can't open \(url.lastPathComponent) as a PDF") }
        var text = at.trimmingCharacters(in: .whitespaces), onPage: Int?
        if let m = text.range(of: #"^page\s+(\d+)\b\s*"#, options: [.regularExpression, .caseInsensitive]) {
            let head = String(text[m])
            onPage = Int(head.filter(\.isNumber))
            text = String(text[m.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard let p = onPage, p >= 1, p <= doc.pageCount else { throw PdfComments.Failure("\(url.lastPathComponent) has \(doc.pageCount) pages: there is no page \(onPage ?? 0)") }
            if text.isEmpty {
                let box = doc.page(at: p - 1)!.bounds(for: .cropBox)
                return PdfPlace(page: p, quads: nil, point: CGPoint(x: box.maxX - 40, y: box.maxY - 40))
            }
        }
        guard !text.isEmpty else { throw PdfComments.Failure("--at needs a text that appears once, or `page N`") }
        var found = doc.findString(text, withOptions: [])
        if let p = onPage { found = found.filter { $0.pages.contains { doc.index(for: $0) == p - 1 } } }
        guard found.count == 1 else {
            throw PdfComments.Failure(found.isEmpty ? "“\(text)” doesn't appear in \(url.lastPathComponent)\(onPage.map { " on page \($0)" } ?? "")"
                                                    : "“\(text)” appears \(found.count) times in \(url.lastPathComponent)\(onPage.map { " on page \($0)" } ?? ""): say which with `page N <text>` or a longer text")
        }
        var page: PDFPage?, quads: [CGRect] = []
        for line in found[0].selectionsByLine() {
            guard let p = line.pages.first else { continue }
            if let page, page !== p { throw PdfComments.Failure("“\(text)” runs across two pages: pick a shorter text") }
            page = p
            let b = line.bounds(for: p)
            if b.width > 0, b.height > 0 { quads.append(b) }
        }
        guard let page, !quads.isEmpty else { throw PdfComments.Failure("couldn't place “\(text)” on a page") }
        quads = pdfCorrected(quads, page: page, text: text)
        return PdfPlace(page: doc.index(for: page) + 1, quads: quads, point: nil)
    }

    // MARK: Where the text really is

    /// PDFKit's selection boxes are right for most files, but a PDF whose text sits in a 1 pt font under a scaled text matrix, one
    /// wrapped line split over two rows (what macOS prints), gets boxes as tall as several rows and an x that sometimes starts left
    /// of the page; its per-character boxes are off as well (F-n). When a box is that wrong, read the rows from the page's content
    /// (`PdfTextRows`: a baseline, a size and each character's advance) and make one box per row for the text. Where the content
    /// can't be read that way, or the text isn't in it exactly once, PDFKit's boxes stay.
    static func pdfCorrected(_ lines: [CGRect], page p: PDFPage, text: String) -> [CGRect] {
        let crop = p.bounds(for: .cropBox).insetBy(dx: -2, dy: -2)
        guard let string = p.string as NSString?, string.length > 0, let ref = p.pageRef else { return lines }
        // Plausible? A line box is about one em high; the ink of the glyphs near the text is about 0.55 to 0.75 em.
        func ws(_ i: Int) -> Bool { string.substring(with: NSRange(location: i, length: 1)).unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) } }
        let centre = string.range(of: text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "").location
        let mid = centre == NSNotFound ? 0 : centre
        let near = max(0, mid - 60)..<min(string.length, mid + 120)
        let heights = near.filter { !ws($0) }.map { p.characterBounds(at: $0).height }.filter { $0 > 0.5 && $0 < 200 }.sorted()
        if heights.count >= 3, lines.allSatisfy({ crop.contains($0) && $0.height <= 2.8 * heights[heights.count / 2] }) { return lines }
        let rows = PdfTextRows.rows(ref)
        let needle = Array(text.filter { !$0.isWhitespace })
        guard !needle.isEmpty, !rows.isEmpty else { return lines }
        var hay: [Character] = [], origin: [(row: Int, col: Int)] = []
        for (ri, r) in rows.enumerated() { for (ci, c) in r.text.enumerated() where !c.isWhitespace { hay.append(c); origin.append((ri, ci)) } }
        var found: [Int] = []
        if hay.count >= needle.count {
            for i in 0...(hay.count - needle.count) where hay[i] == needle[0] && Array(hay[i..<(i + needle.count)]) == needle { found.append(i) }
        }
        guard found.count == 1 else { return lines }
        var cols: [Int: (Int, Int)] = [:]
        for k in found[0]..<(found[0] + needle.count) {
            let o = origin[k]
            cols[o.row] = (min(cols[o.row]?.0 ?? o.col, o.col), max(cols[o.row]?.1 ?? o.col, o.col))
        }
        let out = cols.keys.sorted().map { ri -> CGRect in
            let r = rows[ri], c = cols[ri]!
            let x = r.span(c.0, c.1)
            return CGRect(x: x.0, y: r.baseline - 0.23 * r.size, width: x.1 - x.0, height: r.size)
        }
        return out.isEmpty ? lines : out
    }

    // MARK: Verbs

    func pdfReviewVerb(_ id: ActionID, _ inv: Invocation, author: String, url: URL, args: [String], _ done: @escaping @MainActor (Reply) -> Void) {
        let name = displayPath(url)
        do {
            switch id {
            case .commentList:
                let all = try Self.pdfThreads(url)
                let review = try Self.pdfReviewThreads(url)
                let list = all.filter { inv.has("closed") ? $0.resolved : !$0.resolved }.filter { t in
                    !inv.has("unsent") || (t.items.contains { $0.text.range(of: "@claude", options: .caseInsensitive) != nil } && !t.items.contains { Review.signatureName($0.author) == "claude" })
                }
                let lines = list.flatMap { t -> [String] in
                    let head = t.items[0]
                    var out = ["#\(t.id) [\(t.resolved ? "closed" : "open")] @\(Review.signatureName(head.author)), \(head.date.prefix(10)) on \(t.place)"
                               + (t.anchor.map { " “\(Review.abbreviate($0))”" } ?? "") + ": " + head.text]
                    for r in t.items.dropFirst() { out.append("  ↳ #\(r.id) @\(Review.signatureName(r.author)), \(r.date.prefix(10)): \(r.text)") }
                    return out
                }
                done(.ok(list.isEmpty ? "\(name) has no \(inv.has("closed") ? "closed " : "")comment threads." : "\(name)\n" + lines.joined(separator: "\n"),
                         list.map { t -> [String: Any] in
                             ["id": t.id, "closed": t.resolved, "anchor": t.anchor as Any, "place": t.place, "kind": t.kind,
                              "namesClaude": review.first { $0.id == t.id }?.comments.contains { $0.mentionsClaude } ?? false,
                              "comments": t.items.map { ["id": $0.id, "author": $0.author, "date": $0.date, "text": $0.text] }]
                         }))
            case .commentAdd:
                guard let at = inv.flags["at"], !at.isEmpty, !args.isEmpty else { return done(.fail("usage: \(id.action.usage)")) }
                let place = try Self.pdfPlace(url, at: at)
                let w = try PdfComments.add(url, page: place.page, quads: place.quads, point: place.point, author: author, text: args.joined(separator: " "), backups: Self.pdfBackups)
                Self.pdfChanged(url)
                done(.ok(w.summary, ["file": name, "id": w.id]))
            case .commentReply:
                guard let tid = args.first, args.count > 1 else { return done(.fail("usage: \(id.action.usage)")) }
                if inv.has("suggest") { return done(.fail("--suggest proposes an edit in a Markdown document; a PDF has no suggestions Duo writes")) }
                let w = try PdfComments.reply(url, to: tid, author: author, text: args.dropFirst().joined(separator: " "), backups: Self.pdfBackups)
                Self.pdfChanged(url)
                done(.ok(w.summary, ["file": name, "id": w.id]))
            case .commentClose, .commentReopen:
                guard let tid = args.first else { return done(.fail("usage: \(id.action.usage)")) }
                let w = try PdfComments.resolve(url, thread: tid, resolved: id == .commentClose, author: author, backups: Self.pdfBackups)
                Self.pdfChanged(url)
                done(.ok(w.summary, ["file": name, "id": w.id]))
            case .commentDelete:
                guard let tid = args.first else { return done(.fail("usage: \(id.action.usage)")) }
                let w = try PdfComments.delete(url, thread: tid, backups: Self.pdfBackups)
                Self.pdfChanged(url)
                done(.ok(w.summary, ["file": name, "id": w.id]))
            case .commentStatus:
                guard let raw = args.first?.trimmingCharacters(in: CharacterSet(charactersIn: "#")), let t = try Self.pdfReviewThreads(url).first(where: { $0.id == raw }) else {
                    return done(.fail(args.first.map { "no thread #\($0) in \(name)" } ?? "usage: \(id.action.usage)"))
                }
                let people = Array(Set(t.comments.compactMap(\.author))).sorted().map { "@\($0)" }.joined(separator: ", ")
                let names = t.comments.contains { $0.mentionsClaude }, replied = t.comments.contains { $0.author == "claude" }
                let d = reviewDeliveries[Self.reviewKey(url, t.id)]
                let delivery = d.map { "\($0.state.rawValue.replacingOccurrences(of: "-", with: " ")) (\($0.sessionName), \(Self.clock($0.at)))\($0.why.map { ": " + $0 } ?? "")" } ?? (names ? "not sent" : "n/a")
                done(.ok("#\(t.id): \(t.closed ? "closed" : "open"), \(t.comments.filter { !$0.closing }.count) comments by \(people); delivery: \(delivery); "
                         + (names ? (replied ? "names @claude, Claude has replied" : "names @claude, no reply from Claude yet") : "doesn't name @claude"),
                         ["id": t.id, "closed": t.closed, "repliedByClaude": replied, "delivery": d?.state.rawValue ?? "not sent"]))
            case .commentSend:
                let threads = try Self.pdfReviewThreads(url)
                let ids: [String]
                if inv.has("all") {
                    ids = threads.filter { t in !t.closed && t.comments.contains(where: \.mentionsClaude) && !t.comments.contains { $0.author == "claude" }
                        && self.reviewDeliveries[Self.reviewKey(url, t.id)] == nil }.map(\.id)
                    guard !ids.isEmpty else { return done(.ok("Nothing to send: every @claude comment in \(name) went, or has an answer.")) }
                } else if let one = args.first { ids = [one.trimmingCharacters(in: CharacterSet(charactersIn: "#"))] }
                else { return done(.fail("usage: \(id.action.usage)")) }
                var chosen: Fixture.Session?
                if let to = inv.flags["to"] {
                    guard let s = findSession(to, in: nil) else { return done(.fail("no session '\(to)' (see `duo2 sessions`)")) }
                    chosen = s
                }
                if inv.has("new") { return done(.fail("--new isn't built yet: start a session with `duo2 session new`, then send with --to it (Q-284)")) }
                var lines: [String] = []
                var left = ids.count
                for tid in ids {
                    sendReviewComment(url, thread: tid, to: chosen) { r in
                        lines.append("#\(tid): \(r.text)"); left -= 1
                        if left == 0 { done(.ok(lines.joined(separator: "\n"), ["file": name, "threads": ids])) }
                    }
                }
            default: done(.fail("\(url.lastPathComponent) is a PDF: that verb works on a Markdown document"))
            }
        } catch {
            done(.fail("\(error)"))
        }
    }

    // MARK: pdf render

    func pdfRenderVerb(_ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let arg = inv[0], let n = inv[1].flatMap(Int.init) else { return done(.fail("usage: \(ActionID.pdfRender.action.usage)")) }
        let width = inv.flags["width"].flatMap(Int.init) ?? 1000
        guard (200...3000).contains(width) else { return done(.fail("--width takes 200 to 3000 px")) }
        let url: URL
        switch documentFile(arg, req: req) {
        case .failure(let refusal): return done(.fail(refusal.why))
        case .success(let u): url = u
        }
        guard Self.isPdf(url) else { return done(.fail("\(url.lastPathComponent) isn't a PDF")) }
        do {
            let png = try PdfRead.render(url, page: n, width: width)
            let out: URL
            if let o = inv.flags["out"], !o.isEmpty {
                let e = (o as NSString).expandingTildeInPath
                out = e.hasPrefix("/") ? URL(fileURLWithPath: e) : URL(fileURLWithPath: e, relativeTo: req.cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }).absoluteURL
            } else {
                out = Self.shotFolder(req).appending(path: "\(url.deletingPathExtension().lastPathComponent)-p\(n)-\(width).png")
            }
            try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: out, options: .atomic)
            done(.ok("Saved a picture of \(displayPath(url)), page \(n):\n\(SendFormat.tilde(out.path))", ["files": [out.path], "page": n]))
        } catch {
            done(.fail("\(error)"))
        }
    }
}
