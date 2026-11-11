import Foundation

extension OfficeComments {
    /// Word: `word/comments.xml`, `word/commentsExtended.xml` (done, and which comment a reply answers) and the
    /// `commentRangeStart/End` + `commentReference` anchors in `word/document.xml`.
    enum Word {
        static let wNS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

        struct Raw { var id: String; var author: String; var date: String; var text: String; var paraId: String?; var parentPara: String?; var done: Bool }

        static func raws(_ zip: Pptx.Zip) throws -> [Raw] {
            guard let c = try zip.xml("word/comments.xml") else { return [] }
            var ex: [String: (parent: String?, done: Bool)] = [:]
            if let e = try zip.xml("word/commentsExtended.xml") {
                for n in e.all("commentEx") { if let p = n.attr("w15:paraId") { ex[p] = (n.attr("w15:paraIdParent"), n.attr("w15:done") == "1" || n.attr("w15:done") == "true") } }
            }
            return c.all("comment").compactMap { n in
                guard let id = n.attr("w:id") else { return nil }
                let ps = n.all("p")
                let last = ps.last?.attr("w14:paraId")
                return Raw(id: id, author: n.attr("w:author") ?? "", date: n.attr("w:date") ?? "", text: ps.map { Docx.plain($0, accepted: true) }.joined(separator: "\n"),
                           paraId: last, parentPara: last.flatMap { ex[$0]?.parent }, done: last.flatMap { ex[$0]?.done } ?? false)
            }
        }

        /// The text under each comment's range, from document.xml.
        static func anchors(_ doc: String) -> [String: String] {
            var out: [String: String] = [:]
            var rest = Substring(doc)
            while let s = rest.range(of: "<w:commentRangeStart w:id=\"") {
                let afterID = rest[s.upperBound...]
                guard let q = afterID.firstIndex(of: "\"") else { break }
                let id = String(afterID[..<q])
                if let e = afterID.range(of: "<w:commentRangeEnd w:id=\"\(id)\"") {
                    out[id] = plain(String(afterID[..<e.lowerBound]), tag: "w:t")
                }
                rest = afterID
            }
            return out
        }

        static func read(_ zip: Pptx.Zip) throws -> [Thread] {
            let all = try raws(zip)
            let doc = string(try zip.read("word/document.xml")) ?? ""
            let anchor = anchors(doc)
            var byPara: [String: Raw] = [:]
            for r in all { if let p = r.paraId { byPara[p] = r } }
            func rootOf(_ r: Raw) -> Raw { var cur = r, n = 0; while let p = cur.parentPara, let up = byPara[p], n < 50 { cur = up; n += 1 }; return cur }
            var order: [String] = [], members: [String: [Raw]] = [:]
            for r in all { let root = rootOf(r); if members[root.id] == nil { order.append(root.id) }; members[root.id, default: []].append(r) }
            return order.compactMap { rid -> Thread? in
                guard let ms = members[rid], let root = ms.first(where: { $0.id == rid }) else { return nil }
                let replies = ms.filter { $0.id != rid }
                var items = [Item(id: "c\(rid)", author: root.author, date: root.date, text: root.text)]
                for (i, r) in replies.enumerated() { items.append(Item(id: "c\(rid).\(i + 1)", author: r.author, date: r.date, text: r.text)) }
                let a = anchor[rid].flatMap { $0.isEmpty ? nil : $0 }
                return Thread(id: "c\(rid)", anchor: a, place: place(doc, rid), items: items, resolved: root.done)
            }
        }

        /// `paragraph <paraId>` of the paragraph holding the comment's range start, else `the document`.
        static func place(_ doc: String, _ id: String) -> String {
            guard let r = doc.range(of: "<w:commentRangeStart w:id=\"\(id)\"") else { return "the document" }
            let before = doc[..<r.lowerBound]
            guard let p = before.range(of: "<w:p ", options: .backwards) ?? before.range(of: "<w:p>", options: .backwards) else { return "the document" }
            let tag = doc[p.lowerBound...].prefix(while: { $0 != ">" })
            if let q = tag.range(of: "w14:paraId=\"") {
                let id = tag[q.upperBound...].prefix(while: { $0 != "\"" })
                return "paragraph \(id)"
            }
            return "the document"
        }

        static func wordID(_ thread: String) -> String { String(thread.drop(while: { $0 == "c" || $0 == "#" }).prefix(while: { $0 != "." })) }

        // MARK: Writing

        static func commentXML(id: String, author: String, date: String, text: String, paraId: String) -> String {
            let paras = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var out = "<w:comment w:id=\"\(id)\" w:author=\"\(esc(display(author)))\" w:date=\"\(date)\" w:initials=\"\(esc(initials(display(author))))\">"
            for (i, line) in paras.enumerated() {
                let pid = i == paras.count - 1 ? " w14:paraId=\"\(paraId)\" w14:textId=\"77777777\"" : ""
                out += "<w:p\(pid)><w:pPr><w:pStyle w:val=\"CommentText\"/></w:pPr>"
                if i == 0 { out += "<w:r><w:rPr><w:rStyle w:val=\"CommentReference\"/></w:rPr><w:annotationRef/></w:r>" }
                out += "<w:r><w:t xml:space=\"preserve\">\(esc(line))</w:t></w:r></w:p>"
            }
            return out + "</w:comment>"
        }

        static let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        static let nsAll = "xmlns:w=\"\(wNS)\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\" xmlns:w15=\"http://schemas.microsoft.com/office/word/2012/wordml\" mc:Ignorable=\"w14 w15\""

        /// Makes sure a root element declares a namespace prefix.
        static func declare(_ xml: inout String, root: String, prefix: String, uri: String) {
            guard !xml.contains("xmlns:\(prefix)=") else { return }
            if let r = xml.range(of: "<\(root)") { xml.insert(contentsOf: " xmlns:\(prefix)=\"\(uri)\"", at: r.upperBound) }
        }

        static func uniqueParaId(seed: String, taken: Set<String>) -> String {
            var v = Int(OfficeZip.crc32(Data(seed.utf8)) & 0x7FFF_FFFF)
            if v == 0 { v = 1 }
            while taken.contains(String(format: "%08X", v)) { v = (v + 1) & 0x7FFF_FFFF; if v == 0 { v = 1 } }
            return String(format: "%08X", v)
        }

        struct Parts {
            var comments: String, ext: String, doc: String, rels: String, types: String
            var addedComments = false, addedExt = false
        }

        static func load(_ zip: Pptx.Zip, _ files: [String: Data]) throws -> Parts {
            func part(_ n: String) -> String? { files[n].flatMap { string($0) } ?? string(try? zip.read(n)) }
            guard let doc = part("word/document.xml") else { throw Failure("not a Word document (no word/document.xml)") }
            guard let rels = part("word/_rels/document.xml.rels"), let types = part("[Content_Types].xml") else { throw Failure("the Word document has no relationships or content types") }
            var p = Parts(comments: part("word/comments.xml") ?? "", ext: part("word/commentsExtended.xml") ?? "", doc: doc, rels: rels, types: types)
            if p.comments.isEmpty {
                p.comments = header + "<w:comments \(nsAll)></w:comments>"; p.addedComments = true
            }
            if p.ext.isEmpty {
                p.ext = header + "<w15:commentsEx \(nsAll)></w15:commentsEx>"; p.addedExt = true
            }
            declare(&p.comments, root: "w:comments", prefix: "w14", uri: "http://schemas.microsoft.com/office/word/2010/wordml")
            return p
        }

        static func store(_ p: Parts, _ files: inout [String: Data], _ zip: Pptx.Zip) {
            var p = p
            if p.addedComments {
                addRel(&p.rels, id: freshID("rIdDuoComments", in: p.rels), type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments", target: "comments.xml")
                addOverride(&p.types, part: "/word/comments.xml", type: "application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml")
            }
            if p.addedExt || !p.rels.contains("commentsExtended") {
                addRel(&p.rels, id: freshID("rIdDuoCommentsEx", in: p.rels), type: "http://schemas.microsoft.com/office/2011/relationships/commentsExtended", target: "commentsExtended.xml")
                addOverride(&p.types, part: "/word/commentsExtended.xml", type: "application/vnd.openxmlformats-officedocument.wordprocessingml.commentsExtended+xml")
            }
            // Only a part that changed is written; the rest stay as they were in the file.
            func put(_ name: String, _ text: String) { if string(try? zip.read(name)) != text { files[name] = Data(text.utf8) } }
            put("word/comments.xml", p.comments); put("word/commentsExtended.xml", p.ext); put("word/document.xml", p.doc)
            if p.addedComments || p.addedExt { put("word/_rels/document.xml.rels", p.rels); put("[Content_Types].xml", p.types) }
        }

        static func nextID(_ comments: String) -> String {
            var m = -1
            var rest = Substring(comments)
            while let r = rest.range(of: "<w:comment w:id=\"") {
                let tail = rest[r.upperBound...]
                if let n = Int(tail.prefix(while: { $0 != "\"" })) { m = max(m, n) }
                rest = tail
            }
            return String(m + 1)
        }

        static func takenParaIds(_ p: Parts) -> Set<String> {
            var s = Set<String>()
            for text in [p.comments, p.doc] {
                var rest = Substring(text)
                while let r = rest.range(of: "w14:paraId=\"") { let tail = rest[r.upperBound...]; s.insert(String(tail.prefix(8))); rest = tail }
            }
            return s
        }

        static func reference(_ id: String) -> String { "<w:commentRangeEnd w:id=\"\(id)\"/><w:r><w:rPr><w:rStyle w:val=\"CommentReference\"/></w:rPr><w:commentReference w:id=\"\(id)\"/></w:r>" }

        /// Puts the range around `at` in document.xml: a text that appears once inside a plain run, else its paragraph; a number is a paragraph's position.
        static func anchor(_ doc: inout String, at: String, id: String) throws {
            let start = "<w:commentRangeStart w:id=\"\(id)\"/>"
            // Paragraph by position.
            if let n = Int(at), n > 0 {
                var ranges: [Range<String.Index>] = []
                var from = doc.startIndex
                while let r = doc.range(of: "<w:p>", range: from..<doc.endIndex) ?? doc.range(of: "<w:p ", range: from..<doc.endIndex) {
                    let a = doc.range(of: "<w:p>", range: from..<doc.endIndex), b = doc.range(of: "<w:p ", range: from..<doc.endIndex)
                    let s = [a, b].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound } ?? r
                    ranges.append(s); from = s.upperBound
                }
                guard n <= ranges.count else { throw Failure("the document has \(ranges.count) paragraphs, not \(n)") }
                return try wrapParagraph(&doc, startingAt: ranges[n - 1].lowerBound, id: id)
            }
            let needle = esc(at)
            // A run holding the text, once in the whole document.
            let hits = occurrences(of: needle, inTextOf: doc)
            guard !hits.isEmpty else { throw Failure("“\(at)” isn't in the document's text") }
            guard hits.count == 1 else { throw Failure("“\(at)” appears \(hits.count) times: name a longer piece of text, or a paragraph number") }
            let h = hits[0]
            let textEl = String(doc[h.textRange])
            let inner = String(doc[h.contentRange])
            // The run is `<w:r…>(<w:rPr>…</w:rPr>)?<w:t…>…</w:t></w:r>` with nothing else.
            if let runOpen = doc[..<h.textRange.lowerBound].range(of: "<w:r", options: .backwards),
               let runClose = doc.range(of: "</w:r>", range: h.textRange.upperBound..<doc.endIndex),
               doc[runClose.lowerBound...].hasPrefix("</w:r>"), doc[h.textRange.upperBound..<runClose.lowerBound].isEmpty {
                let head = String(doc[runOpen.lowerBound..<h.textRange.lowerBound])
                let openTag = String(head.prefix(while: { $0 != ">" })) + ">"
                var rPr = String(head.dropFirst(openTag.count))
                if rPr.contains("<w:t") || rPr.contains("<w:br") || rPr.contains("<w:tab") { rPr = "" ; throw Failure("“\(at)” sits in a run with other content; name a paragraph number instead") }
                let r = inner.range(of: needle)!
                let before = String(inner[..<r.lowerBound]), after = String(inner[r.upperBound...])
                func run(_ t: String) -> String { t.isEmpty ? "" : "\(openTag)\(rPr)<w:t xml:space=\"preserve\">\(t)</w:t></w:r>" }
                _ = textEl
                let replacement = run(before) + start + run(needle) + reference(id) + run(after)
                doc.replaceSubrange(runOpen.lowerBound..<runClose.upperBound, with: replacement)
                return
            }
            throw Failure("“\(at)” isn't in a plain run; name a paragraph number instead")
        }

        struct Hit { var textRange: Range<String.Index>; var contentRange: Range<String.Index> }
        /// `<w:t>` elements whose text contains `needle`.
        static func occurrences(of needle: String, inTextOf doc: String) -> [Hit] {
            var out: [Hit] = []
            var from = doc.startIndex
            while let open = doc.range(of: "<w:t", range: from..<doc.endIndex) {
                from = open.upperBound
                // `<w:t>` or `<w:t ...>`, not `<w:tab/>`, `<w:tbl>`, ...
                guard let c = doc[open.upperBound...].first, c == ">" || c == " " else { continue }
                guard let gt = doc[open.upperBound...].firstIndex(of: ">"), doc[doc.index(before: gt)] != "/" else { continue }
                guard let close = doc.range(of: "</w:t>", range: gt..<doc.endIndex) else { break }
                let content = doc.index(after: gt)..<close.lowerBound
                if doc[content].contains(needle) {
                    var n = 0, s = doc[content][...]
                    while let r = s.range(of: needle) { n += 1; s = s[r.upperBound...] }
                    for _ in 0..<n { out.append(Hit(textRange: open.lowerBound..<close.upperBound, contentRange: content)) }
                }
                from = close.upperBound
            }
            return out
        }

        static func wrapParagraph(_ doc: inout String, startingAt p: String.Index, id: String) throws {
            guard let tagEnd = doc[p...].firstIndex(of: ">"), let close = doc.range(of: "</w:p>", range: tagEnd..<doc.endIndex) else { throw Failure("damaged paragraph") }
            // After the paragraph's properties when it has them.
            var insertAt = doc.index(after: tagEnd)
            if doc[insertAt...].hasPrefix("<w:pPr>") || doc[insertAt...].hasPrefix("<w:pPr "), let e = doc.range(of: "</w:pPr>", range: insertAt..<close.lowerBound) { insertAt = e.upperBound }
            let end = reference(id)
            doc.insert(contentsOf: end, at: close.lowerBound)
            doc.insert(contentsOf: "<w:commentRangeStart w:id=\"\(id)\"/>", at: insertAt)
        }

        static func add(_ zip: Pptx.Zip, _ files: inout [String: Data], at: String, author: String, text: String, now: Date) throws -> Written {
            var p = try load(zip, files)
            let id = nextID(p.comments)
            try anchor(&p.doc, at: at, id: id)
            let paraId = uniqueParaId(seed: "\(id)\(author)\(text)\(iso(now))", taken: takenParaIds(p))
            guard insert(&p.comments, commentXML(id: id, author: author, date: iso(now), text: text, paraId: paraId), before: "</w:comments>") else { throw Failure("damaged word/comments.xml") }
            guard insert(&p.ext, "<w15:commentEx w15:paraId=\"\(paraId)\" w15:done=\"0\"/>", before: "</w15:commentsEx>") else { throw Failure("damaged word/commentsExtended.xml") }
            store(p, &files, zip)
            return Written(id: "c\(id)", summary: "Commented in \(display(author))'s name on “\(at)” (thread c\(id)).")
        }

        static func reply(_ zip: Pptx.Zip, _ files: inout [String: Data], to thread: String, author: String, text: String, now: Date) throws -> Written {
            var p = try load(zip, files)
            let all = try raws(zip)
            let rid = wordID(thread)
            guard let root = all.first(where: { $0.id == rid }) else { throw Failure("no thread \(thread) in this document") }
            // The parent's paraId; a comment without one gets it first.
            var parentPara = root.paraId
            if parentPara == nil {
                let np = uniqueParaId(seed: "parent\(rid)", taken: takenParaIds(p))
                guard let c = p.comments.range(of: "<w:comment w:id=\"\(rid)\""), let end = p.comments.range(of: "</w:comment>", range: c.upperBound..<p.comments.endIndex),
                      let lastP = p.comments.range(of: "<w:p", options: .backwards, range: c.upperBound..<end.lowerBound) else { throw Failure("damaged word/comments.xml") }
                p.comments.insert(contentsOf: " w14:paraId=\"\(np)\"", at: p.comments.index(lastP.lowerBound, offsetBy: 4))
                parentPara = np
                p.ext.insert(contentsOf: "<w15:commentEx w15:paraId=\"\(np)\" w15:done=\"0\"/>", at: p.ext.range(of: "</w15:commentsEx>")!.lowerBound)
            }
            let id = nextID(p.comments)
            // The reply's range is the parent's: it starts right after the parent's start and ends after the parent's reference.
            guard insert(&p.doc, "<w:commentRangeStart w:id=\"\(id)\"/>", after: "<w:commentRangeStart w:id=\"\(rid)\"/>") else { throw Failure("thread \(thread) has no anchor in the document") }
            let ref = "<w:commentReference w:id=\"\(rid)\"/></w:r>"
            guard insert(&p.doc, reference(id), after: ref) else { throw Failure("thread \(thread) has no reference in the document") }
            let paraId = uniqueParaId(seed: "\(id)\(author)\(text)\(iso(now))", taken: takenParaIds(p))
            guard insert(&p.comments, commentXML(id: id, author: author, date: iso(now), text: text, paraId: paraId), before: "</w:comments>") else { throw Failure("damaged word/comments.xml") }
            let done = (root.paraId.flatMap { _ in root.done } ?? false) ? "1" : "0"
            guard insert(&p.ext, "<w15:commentEx w15:paraId=\"\(paraId)\" w15:paraIdParent=\"\(parentPara!)\" w15:done=\"\(done)\"/>", before: "</w15:commentsEx>") else { throw Failure("damaged word/commentsExtended.xml") }
            store(p, &files, zip)
            let n = (try? read(zip).first(where: { $0.id == "c\(rid)" })?.items.count) ?? 1
            return Written(id: "c\(rid).\(n)", summary: "Replied in thread c\(rid) as \(display(author)).")
        }

        /// Delete a thread: each comment of it from comments.xml and commentsExtended.xml, and its anchors from document.xml.
        static func delete(_ zip: Pptx.Zip, _ files: inout [String: Data], thread: String) throws -> Written {
            var p = try load(zip, files)
            let all = try raws(zip)
            let rid = wordID(thread)
            guard let root = all.first(where: { $0.id == rid }) else { throw Failure("no thread \(thread) in this document") }
            var ids = [rid], paras = Set<String>()
            if let pid = root.paraId { paras.insert(pid) }
            // Replies: comments whose parent chain reaches the root.
            var byPara: [String: Raw] = [:]
            for r in all { if let pid = r.paraId { byPara[pid] = r } }
            for r in all where r.id != rid {
                var cur = r, n = 0
                while let pp = cur.parentPara, let up = byPara[pp], n < 50 { cur = up; n += 1 }
                if cur.id == rid { ids.append(r.id); if let pid = r.paraId { paras.insert(pid) } }
            }
            for id in ids {
                if let a = p.comments.range(of: "<w:comment w:id=\"\(id)\""), let e = p.comments.range(of: "</w:comment>", range: a.upperBound..<p.comments.endIndex) { p.comments.removeSubrange(a.lowerBound..<e.upperBound) }
                for tag in ["<w:commentRangeStart w:id=\"\(id)\"/>", "<w:commentRangeEnd w:id=\"\(id)\"/>"] { p.doc = p.doc.replacingOccurrences(of: tag, with: "") }
                if let ref = p.doc.range(of: "<w:commentReference w:id=\"\(id)\"/>"),
                   let open = p.doc.range(of: "<w:r>", options: .backwards, range: p.doc.startIndex..<ref.lowerBound) ?? p.doc.range(of: "<w:r ", options: .backwards, range: p.doc.startIndex..<ref.lowerBound),
                   let close = p.doc.range(of: "</w:r>", range: ref.upperBound..<p.doc.endIndex) {
                    p.doc.removeSubrange(open.lowerBound..<close.upperBound)
                }
            }
            for pid in paras {
                if let a = p.ext.range(of: "<w15:commentEx w15:paraId=\"\(pid)\""), let e = p.ext.range(of: "/>", range: a.upperBound..<p.ext.endIndex) { p.ext.removeSubrange(a.lowerBound..<e.upperBound) }
            }
            store(p, &files, zip)
            return Written(id: "c\(rid)", summary: "Deleted thread c\(rid) and its replies.")
        }

        static func resolve(_ zip: Pptx.Zip, _ files: inout [String: Data], thread: String, resolved: Bool) throws -> Written {
            var p = try load(zip, files)
            let all = try raws(zip)
            let rid = wordID(thread)
            guard let root = all.first(where: { $0.id == rid }) else { throw Failure("no thread \(thread) in this document") }
            let members = all.filter { $0.id == rid || $0.parentPara == root.paraId || ($0.parentPara.flatMap { pp in all.first { $0.paraId == pp }?.id } == rid) }
            let value = resolved ? "1" : "0"
            for m in members {
                guard let pid = m.paraId else { continue }
                if let r = p.ext.range(of: "<w15:commentEx w15:paraId=\"\(pid)\"") , let e = p.ext.range(of: "/>", range: r.upperBound..<p.ext.endIndex) {
                    var tag = String(p.ext[r.lowerBound..<e.upperBound])
                    if tag.contains("w15:done=\"") {
                        tag = tag.replacingOccurrences(of: "w15:done=\"[^\"]*\"", with: "w15:done=\"\(value)\"", options: .regularExpression)
                    } else { tag = tag.replacingOccurrences(of: "/>", with: " w15:done=\"\(value)\"/>") }
                    p.ext.replaceSubrange(r.lowerBound..<e.upperBound, with: tag)
                } else {
                    let parent = m.parentPara.map { " w15:paraIdParent=\"\($0)\"" } ?? ""
                    _ = insert(&p.ext, "<w15:commentEx w15:paraId=\"\(pid)\"\(parent) w15:done=\"\(value)\"/>", before: "</w15:commentsEx>")
                }
            }
            if root.paraId == nil { throw Failure("thread \(thread) has no paragraph id to mark; reply to it first") }
            store(p, &files, zip)
            return Written(id: "c\(rid)", summary: "Thread c\(rid) is \(resolved ? "resolved" : "open again").")
        }
    }
}
