import CoreGraphics
import Foundation

/// Comments in PDF files (DL-335; Geoff, 2026-11-10). A comment is an ISO 32000 markup annotation (a Highlight over text, or a
/// Text note on a spot); a reply is a Text annotation with `/IRT` and `/RT /R`; Close is a hidden Text annotation with
/// `/StateModel (Review)` and `/State (Completed)`, Reopen the same with `(None)`. Every change is ONE incremental update
/// appended after the file's own bytes (the original stays an exact prefix, so a signature over it holds), written by Duo's own
/// small writer (`PdfObjects.swift`); PDFKit draws the file and never saves it. Foundation, CoreGraphics (geometry) and
/// Compression only. Encrypted files, files whose cross-reference data can't be read exactly, and files certified against
/// changes are refused.
public enum PdfComments {
    public struct Failure: Error, CustomStringConvertible { public let description: String; public init(_ d: String) { description = d } }

    public struct Item: Equatable, Sendable {
        /// `c4` for a thread's first comment, `c4.2` for its first reply (the annotation's /NM, or `p3.1` when it has none).
        public var id: String
        public var author: String
        /// `yyyy-MM-dd'T'HH:mm:ss`, UTC.
        public var date: String
        public var text: String
    }

    public struct Thread: Equatable, Sendable {
        public var id: String
        /// 1-based.
        public var page: Int
        /// `page 3`.
        public var place: String
        /// The text it is on: nil here, the app fills it from the page (PDFKit).
        public var anchor: String?
        /// The text's rectangles in page space (the /QuadPoints, or the /Rect for a note).
        public var rects: [CGRect]
        public var items: [Item]
        public var resolved: Bool
        /// The root's /Subtype: Text, Highlight, Underline, StrikeOut, Squiggly, FreeText or Ink.
        public var kind: String
        public var root: Item { items[0] }
    }

    public struct Written: Sendable { public var id: String; public var summary: String }

    public static func isPdf(_ url: URL) -> Bool { url.pathExtension.lowercased() == "pdf" }

    static let markup: Set<String> = ["Text", "Highlight", "Underline", "StrikeOut", "Squiggly", "FreeText", "Ink"]
    static let closedStates: Set<String> = ["Completed", "Accepted", "Rejected", "Cancelled"]

    // MARK: Reading

    struct Record {
        var thread: Thread
        var rootObj: Int
        /// Every object of the thread: root, replies, state replies and pop-ups.
        var members: [Int]
        var page: PdfFile.Page
        var itemObjs: [Int]
    }

    struct Scan {
        var file: PdfFile
        var pages: [PdfFile.Page]
        var records: [Record]
        var usedNames: Set<String>
    }

    static func scan(_ data: Data) throws -> Scan {
        let file = try PdfFile(data)
        let pages = try file.pages()
        struct A { var obj: Int; var d: [String: PdfObj]; var page: Int; var order: Int }
        var all: [A] = []
        var used = Set<String>()
        for (pi, p) in pages.enumerated() {
            guard let arr = try file.resolve(p.dict["Annots"])?.array else { continue }
            for e in arr {
                guard let n = e.refNumber, let d = try file.object(n)?.dict else { continue }
                all.append(A(obj: n, d: d, page: pi, order: all.count))
                if let nm = d["NM"]?.text { used.insert(nm) }
            }
        }
        let byObj = Dictionary(all.map { ($0.obj, $0) }, uniquingKeysWith: { a, _ in a })
        func subtype(_ a: A) -> String { a.d["Subtype"]?.nameValue ?? "" }
        let rootObjs = Set(all.filter { markup.contains(subtype($0)) && $0.d["IRT"] == nil }.map(\.obj))
        func rootOf(_ a: A) -> Int? {
            var cur = a, hops = 0
            while let irt = cur.d["IRT"]?.refNumber {
                hops += 1; if hops > 32 { return nil }
                guard let up = byObj[irt] else { return nil }
                cur = up
            }
            return rootObjs.contains(cur.obj) ? cur.obj : nil
        }
        var records: [Record] = []
        var index: [Int: Int] = [:]
        var perPage: [Int: Int] = [:]
        for a in all where rootObjs.contains(a.obj) {
            perPage[a.page, default: 0] += 1
            let id = a.d["NM"]?.text ?? "p\(a.page + 1).\(perPage[a.page]!)"
            index[a.obj] = records.count
            let quads = quadRects(try file.resolve(a.d["QuadPoints"])?.array)
            let rects = quads.isEmpty ? (rectOf(try file.resolve(a.d["Rect"])?.array).map { [$0] } ?? []) : quads
            let item = Item(id: id, author: a.d["T"]?.text ?? "", date: isoDate(a.d), text: a.d["Contents"]?.text ?? "")
            var members = [a.obj]
            if let pop = a.d["Popup"]?.refNumber { members.append(pop) }
            records.append(Record(thread: Thread(id: id, page: a.page + 1, place: "page \(a.page + 1)", anchor: nil, rects: rects, items: [item], resolved: false, kind: subtype(a)),
                                  rootObj: a.obj, members: members, page: pages[a.page], itemObjs: [a.obj]))
        }
        var states: [Int: [(Date?, Int, String)]] = [:]
        for a in all where a.d["IRT"] != nil && subtype(a) != "Popup" {
            if a.d["RT"]?.nameValue == "Group" { continue }
            guard let r = rootOf(a), let ri = index[r] else { continue }
            records[ri].members.append(a.obj)
            if let pop = a.d["Popup"]?.refNumber { records[ri].members.append(pop) }
            if a.d["StateModel"]?.text == "Review", let st = a.d["State"]?.text {
                states[ri, default: []].append((pdfDate(a.d["M"]?.text ?? a.d["CreationDate"]?.text ?? ""), a.order, st))
                continue
            }
            let id = a.d["NM"]?.text ?? "\(records[ri].thread.id).\(records[ri].thread.items.count + 1)"
            records[ri].thread.items.append(Item(id: id, author: a.d["T"]?.text ?? "", date: isoDate(a.d), text: a.d["Contents"]?.text ?? ""))
            records[ri].itemObjs.append(a.obj)
        }
        for (ri, list) in states {
            let latest = list.max { x, y in
                let dx = x.0 ?? .distantPast, dy = y.0 ?? .distantPast
                return dx == dy ? x.1 < y.1 : dx < dy
            }
            records[ri].thread.resolved = latest.map { closedStates.contains($0.2) } ?? false
        }
        return Scan(file: file, pages: pages, records: records, usedNames: used)
    }

    public static func threads(_ url: URL) throws -> [Thread] {
        try wrap(url) { try scan(Data(contentsOf: url)).records.map(\.thread) }
    }

    /// How many pages the document has.
    public static func pageCount(_ url: URL) throws -> Int { try wrap(url) { try PdfFile(Data(contentsOf: url)).pages().count } }

    static func quadRects(_ q: [PdfObj]?) -> [CGRect] {
        guard let n = q?.compactMap(\.number), n.count >= 8 else { return [] }
        return stride(from: 0, through: n.count - 8, by: 8).map { i in
            let xs = [n[i], n[i + 2], n[i + 4], n[i + 6]], ys = [n[i + 1], n[i + 3], n[i + 5], n[i + 7]]
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
    }
    static func rectOf(_ r: [PdfObj]?) -> CGRect? {
        guard let n = r?.compactMap(\.number), n.count == 4 else { return nil }
        return CGRect(x: min(n[0], n[2]), y: min(n[1], n[3]), width: abs(n[2] - n[0]), height: abs(n[3] - n[1]))
    }

    // MARK: Dates

    /// `D:YYYYMMDDHHmmSS` with an optional `Z` or `+HH'mm'`; the parts after the year are optional.
    static func pdfDate(_ s: String) -> Date? {
        var t = Substring(s)
        if t.hasPrefix("D:") { t = t.dropFirst(2) }
        let digits = t.prefix { $0.isASCII && $0.isNumber }
        guard digits.count >= 4 else { return nil }
        func part(_ at: Int, _ n: Int, _ dflt: Int) -> Int {
            let a = Array(digits)
            return a.count >= at + n ? Int(String(a[at..<(at + n)])) ?? dflt : dflt
        }
        var c = DateComponents()
        c.year = part(0, 4, 1970); c.month = part(4, 2, 1); c.day = part(6, 2, 1); c.hour = part(8, 2, 0); c.minute = part(10, 2, 0); c.second = part(12, 2, 0)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard var d = cal.date(from: c) else { return nil }
        let rest = t.dropFirst(digits.count)
        if let sign = rest.first, sign == "+" || sign == "-" {
            let nums = rest.dropFirst().filter { $0.isNumber }
            let h = Int(nums.prefix(2)) ?? 0, m = nums.count >= 4 ? Int(nums.dropFirst(2).prefix(2)) ?? 0 : 0
            d = d.addingTimeInterval(TimeInterval((h * 3600 + m * 60) * (sign == "+" ? -1 : 1)))
        }
        return d
    }
    static func isoDate(_ d: [String: PdfObj]) -> String {
        guard let s = d["M"]?.text ?? d["CreationDate"]?.text, let date = pdfDate(s) else { return "" }
        return iso(date)
    }
    static func iso(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: d)
    }
    static func pdfDateString(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "'D:'yyyyMMddHHmmss'Z'"
        return f.string(from: d)
    }

    // MARK: Writing

    /// A highlight over `quads` (page space) with `text`, or (no quads) a note at `point`. `page` is 1-based.
    public static func add(_ url: URL, page: Int, quads: [CGRect]? = nil, point: CGPoint? = nil, author: String, text: String, now: Date = Date(), backups: URL? = nil) throws -> Written {
        guard (quads?.isEmpty == false) || point != nil else { throw Failure("a comment needs the text it is on, or a spot on the page") }
        return try write(url, backups: backups) { s, up in
            guard page >= 1, page <= s.pages.count else { throw Failure("\(url.lastPathComponent) has \(s.pages.count) pages: there is no page \(page)") }
            let pg = s.pages[page - 1]
            let id = freshID(s)
            let num = up.allocate()
            var pairs: [(String, PdfObj)] = [("Type", .name("Annot"))]
            let rect: CGRect
            if let quads, !quads.isEmpty {
                rect = quads.dropFirst().reduce(quads[0]) { $0.union($1) }
                pairs += [("Subtype", .name("Highlight")), ("QuadPoints", .array(quads.flatMap { q in
                    [q.minX, q.maxY, q.maxX, q.maxY, q.minX, q.minY, q.maxX, q.minY].map { PdfObj.real(fmt($0)) } }))]
                let ap = up.allocate()
                var content = "/GS gs 1 0.85 0 rg\n"
                for q in quads { content += "\(fmt(q.minX)) \(fmt(q.minY)) \(fmt(q.width)) \(fmt(q.height)) re f\n" }
                up.setStream(ap, [("Type", .name("XObject")), ("Subtype", .name("Form")), ("BBox", rectArray(rect)),
                                  ("Resources", PdfObj.dict([("ExtGState", PdfObj.dict([("GS", PdfObj.dict([("Type", .name("ExtGState")), ("BM", .name("Multiply"))]))]))]))],
                             Data(content.utf8))
                pairs.append(("AP", PdfObj.dict([("N", .ref(ap, 0))])))
            } else {
                let p = point!
                rect = CGRect(x: p.x, y: p.y, width: 20, height: 20)
                pairs += [("Subtype", .name("Text")), ("Name", .name("Comment"))]
            }
            pairs += [("P", .ref(pg.number, s.file.gen(pg.number))), ("Rect", rectArray(rect)), ("Contents", PdfObj.text(text)), ("T", PdfObj.text(author)),
                      ("M", .string(Array(pdfDateString(now).utf8))), ("CreationDate", .string(Array(pdfDateString(now).utf8))),
                      ("NM", PdfObj.text(id)), ("F", .int(4)), ("C", .array([.int(1), .real("0.85"), .int(0)]))]
            up.set(num, PdfObj.dict(pairs))
            try up.attach(to: pg, add: [num], remove: [])
            return Written(id: id, summary: "Commented on page \(page) as \(id).")
        }
    }

    public static func reply(_ url: URL, to thread: String, author: String, text: String, now: Date = Date(), backups: URL? = nil) throws -> Written {
        try write(url, backups: backups) { s, up in
            let rec = try find(s, thread, url)
            let num = up.allocate()
            let id = nextReplyID(rec)
            up.set(num, replyDict(s, rec, id: id, author: author, text: text, now: now, hidden: false))
            try up.attach(to: rec.page, add: [num], remove: [])
            return Written(id: id, summary: "Replied in #\(rec.thread.id) as \(id).")
        }
    }

    /// Mark a thread closed (a hidden `/State (Completed)` reply), or open again (`/State (None)`).
    public static func resolve(_ url: URL, thread: String, resolved: Bool, author: String, now: Date = Date(), backups: URL? = nil) throws -> Written {
        try write(url, backups: backups) { s, up in
            let rec = try find(s, thread, url)
            if rec.thread.resolved == resolved { return Written(id: rec.thread.id, summary: "#\(rec.thread.id) is already \(resolved ? "closed" : "open").") }
            let num = up.allocate()
            let id = nextReplyID(rec)
            let state = resolved ? "Completed" : "None"
            let d = replyDict(s, rec, id: id, author: author, text: "\(state) set by \(author)", now: now, hidden: true, state: state)
            up.set(num, d)
            try up.attach(to: rec.page, add: [num], remove: [])
            return Written(id: rec.thread.id, summary: resolved ? "Closed #\(rec.thread.id)." : "Reopened #\(rec.thread.id).")
        }
    }

    /// Drop a thread from its page's /Annots: the root, its replies, state replies and pop-ups.
    public static func delete(_ url: URL, thread: String, backups: URL? = nil) throws -> Written {
        try write(url, backups: backups) { s, up in
            let rec = try find(s, thread, url)
            try up.attach(to: rec.page, add: [], remove: Set(rec.members))
            return Written(id: rec.thread.id, summary: "Deleted #\(rec.thread.id) (\(rec.thread.items.count) comment\(rec.thread.items.count == 1 ? "" : "s")).")
        }
    }

    // MARK: Writing helpers

    static func find(_ s: Scan, _ id: String, _ url: URL) throws -> Record {
        let want = id.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if let r = s.records.first(where: { $0.thread.id == want }) { return r }
        // A reply's id names its thread too.
        if let r = s.records.first(where: { $0.thread.items.contains { $0.id == want } }) { return r }
        throw Failure("no thread #\(want) in \(url.lastPathComponent)")
    }

    static func freshID(_ s: Scan) -> String {
        var n = 1
        while s.usedNames.contains("c\(n)") || s.usedNames.contains(where: { $0.hasPrefix("c\(n).") }) { n += 1 }
        return "c\(n)"
    }

    /// `c1.2` for the first reply, then `c1.3`: one more than the highest number in the thread.
    static func nextReplyID(_ rec: Record) -> String {
        var top = 1
        for it in rec.thread.items + [] {
            if it.id.hasPrefix(rec.thread.id + "."), let k = Int(it.id.dropFirst(rec.thread.id.count + 1)) { top = max(top, k) }
        }
        return "\(rec.thread.id).\(max(top, rec.thread.items.count) + 1)"
    }

    static func replyDict(_ s: Scan, _ rec: Record, id: String, author: String, text: String, now: Date, hidden: Bool, state: String? = nil) -> PdfObj {
        let rootDict = (try? s.file.object(rec.rootObj))?.dict ?? [:]
        var pairs: [(String, PdfObj)] = [("Type", .name("Annot")), ("Subtype", .name("Text")), ("P", .ref(rec.page.number, s.file.gen(rec.page.number))),
                                         ("Rect", rootDict["Rect"] ?? .array([.int(0), .int(0), .int(0), .int(0)])),
                                         ("Contents", PdfObj.text(text)), ("T", PdfObj.text(author)),
                                         ("M", .string(Array(pdfDateString(now).utf8))), ("CreationDate", .string(Array(pdfDateString(now).utf8))),
                                         ("NM", PdfObj.text(id)), ("F", .int(hidden ? 32 : 4)),
                                         ("IRT", .ref(rec.rootObj, s.file.gen(rec.rootObj))), ("RT", .name("R"))]
        if let state { pairs += [("StateModel", .string(Array("Review".utf8))), ("State", .string(Array(state.utf8)))] }
        else { pairs.append(("Name", .name("Comment"))) }
        return PdfObj.dict(pairs)
    }

    static func fmt(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }
    static func rectArray(_ r: CGRect) -> PdfObj { .array([r.minX, r.minY, r.maxX, r.maxY].map { PdfObj.real(fmt($0)) }) }

    static func wrap<T>(_ url: URL, _ body: () throws -> T) throws -> T {
        do { return try body() }
        catch let f as PdfFailure { throw Failure("\(url.lastPathComponent): \(f.description)") }
    }

    static func write(_ url: URL, backups: URL?, _ make: (Scan, PdfUpdate) throws -> Written) throws -> Written {
        guard isPdf(url) else { throw Failure("\(url.lastPathComponent) isn't a PDF file") }
        return try wrap(url) {
            let original = try Data(contentsOf: url)
            let s = try scan(original)
            if let why = try s.file.writeRefusal() { throw Failure("\(url.lastPathComponent) can't take comments: \(why)") }
            let up = PdfUpdate(s.file)
            let w = try make(s, up)
            var out = original
            if let last = original.last, last != 10, last != 13 { out.append(10) }
            out.append(try up.finish(at: out.count))
            // Read back what would be written: the original is its prefix and it still parses.
            guard out.starts(with: original), let again = try? scan(out), again.pages.count == s.pages.count else {
                throw Failure("the changed file didn't read back; nothing was written")
            }
            if let backups {
                // One copy of the file as it was before Duo first wrote to it. Every write only appends, so a later original that
                // starts with a kept copy needs no second one.
                try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
                let have = ((try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []).filter { $0.hasSuffix("-" + url.lastPathComponent) }
                let covered = have.contains { (try? Data(contentsOf: backups.appendingPathComponent($0)))
                    .map { $0.count <= original.count && original.starts(with: $0) } ?? false }
                if !covered {
                    let b = backups.appendingPathComponent(String(format: "%08x-", OfficeZip.crc32(original)) + url.lastPathComponent)
                    try original.write(to: b)
                }
            }
            try out.write(to: url, options: .atomic)
            return w
        }
    }
}

// MARK: The update

/// The objects of one incremental update, and the cross-reference section that follows them.
final class PdfUpdate {
    let file: PdfFile
    private var next: Int
    private var bodies: [Int: (body: [UInt8], stream: Data?)] = [:]

    init(_ f: PdfFile) { file = f; next = f.size }

    func allocate() -> Int { defer { next += 1 }; return next }
    func set(_ n: Int, _ o: PdfObj) { bodies[n] = (o.serialized(), nil) }
    func setStream(_ n: Int, _ pairs: [(String, PdfObj)], _ data: Data) {
        var all = pairs; all.append(("Length", .int(data.count)))
        bodies[n] = (PdfObj.dict(all).serialized(), data)
    }

    /// Adds `add` to a page's /Annots and drops `remove`: in the array object when /Annots points at one, else in the page itself.
    func attach(to page: PdfFile.Page, add: [Int], remove: Set<Int>) throws {
        let pageObj = try file.object(page.number)
        guard case .dict(var d, var order)? = pageObj else { throw PdfFailure("page object \(page.number) isn't a dictionary") }
        func edited(_ a: [PdfObj]) -> [PdfObj] {
            a.filter { !(remove.contains($0.refNumber ?? -1)) } + add.map { PdfObj.ref($0, 0) }
        }
        if case .ref(let n, _)? = d["Annots"], let arr = try file.object(n)?.array {
            set(n, .array(edited(arr)))
            return
        }
        let current = d["Annots"]?.array ?? []
        if d["Annots"] == nil { order.append("Annots") }
        d["Annots"] = .array(edited(current))
        set(page.number, .dict(d, order: order))
    }

    /// The bytes to append after the original (which ends with a newline): the objects, and a cross-reference section of the same
    /// kind as the file's newest (a classic table, or an uncompressed xref stream): never mixed.
    func finish(at base: Int) throws -> Data {
        var out = [UInt8]()
        var offsets: [Int: Int] = [:]
        for n in bodies.keys.sorted() {
            offsets[n] = base + out.count - file.headerOffset
            let b = bodies[n]!
            out += Array("\(n) \(file.gen(n)) obj\n".utf8) + b.body
            if let s = b.stream { out += Array("\nstream\n".utf8) + [UInt8](s) + Array("\nendstream".utf8) }
            out += Array("\nendobj\n".utf8)
        }
        let prev = file.newestStartxref
        let t = file.trailer
        var trailerPairs: [(String, PdfObj)] = []
        let xrefObj = file.newestIsStream ? allocate() : nil
        let size = max(file.size, next)
        trailerPairs.append(("Size", .int(size)))
        for k in ["Root", "Info", "ID"] { if let v = t[k] { trailerPairs.append((k, v)) } }
        trailerPairs.append(("Prev", .int(prev)))
        let at = base + out.count - file.headerOffset
        var all = offsets.map { ($0.key, $0.value, file.gen($0.key)) }
        if let x = xrefObj { all.append((x, at, 0)) }
        all.sort { $0.0 < $1.0 }
        if let x = xrefObj {
            var runs: [(Int, Int)] = []
            for e in all { if let l = runs.last, l.0 + l.1 == e.0 { runs[runs.count - 1].1 += 1 } else { runs.append((e.0, 1)) } }
            var rows = [UInt8]()
            for e in all {
                guard e.1 < 1 << 32 else { throw PdfFailure("the file is too large for a cross-reference stream update") }
                rows += [1, UInt8(e.1 >> 24 & 0xFF), UInt8(e.1 >> 16 & 0xFF), UInt8(e.1 >> 8 & 0xFF), UInt8(e.1 & 0xFF), UInt8(e.2 >> 8 & 0xFF), UInt8(e.2 & 0xFF)]
            }
            var pairs: [(String, PdfObj)] = [("Type", .name("XRef")), ("Size", .int(max(size, x + 1))), ("W", .array([.int(1), .int(4), .int(2)])),
                                             ("Index", .array(runs.flatMap { [PdfObj.int($0.0), PdfObj.int($0.1)] }))]
            pairs += trailerPairs.filter { $0.0 != "Size" }
            pairs.append(("Length", .int(rows.count)))
            out += Array("\(x) 0 obj\n".utf8) + PdfObj.dict(pairs).serialized() + Array("\nstream\n".utf8) + rows + Array("\nendstream\nendobj\n".utf8)
        } else {
            var text = "xref\n"
            var i = 0
            while i < all.count {
                var j = i
                while j + 1 < all.count, all[j + 1].0 == all[j].0 + 1 { j += 1 }
                text += "\(all[i].0) \(j - i + 1)\n"
                for e in all[i...j] { text += String(format: "%010d %05d n \n", e.1, e.2) }
                i = j + 1
            }
            out += Array(text.utf8) + Array("trailer\n".utf8) + PdfObj.dict(trailerPairs).serialized() + [10]
        }
        out += Array("startxref\n\(at)\n%%EOF\n".utf8)
        return Data(out)
    }
}
