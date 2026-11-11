import Foundation

extension OfficeComments {
    /// PowerPoint: modern comments, `ppt/comments/modernComment_<slide id in hex>_<creation id in hex>.xml` per slide
    /// (a `p188:cmLst`), with their authors in `ppt/authors.xml`. Legacy comments (`commentN.xml`) are read, not written.
    enum Slides {
        static let p188 = "http://schemas.microsoft.com/office/powerpoint/2018/8/main"
        static let relComments = "http://schemas.microsoft.com/office/2018/10/relationships/comments"
        static let relAuthors = "http://schemas.microsoft.com/office/2018/10/relationships/authors"
        static let relLegacy = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments"

        struct SlideRef { var number: Int; var sldId: String; var part: String }

        static func slides(_ zip: Pptx.Zip) throws -> [SlideRef] {
            guard let pres = try zip.xml("ppt/presentation.xml"), let rels = try? Pptx.rels(zip, "ppt/presentation.xml") else { throw Failure("not a PowerPoint file (no ppt/presentation.xml)") }
            var out: [SlideRef] = []
            for n in pres.all("sldId") {
                guard let rid = n.attr("r:id"), let target = rels[rid], let id = n.attr("id") else { continue }
                out.append(SlideRef(number: out.count + 1, sldId: id, part: target))
            }
            return out
        }

        /// A slide's relationships file: `ppt/slides/_rels/slide3.xml.rels`.
        static func relsPart(_ part: String) -> String {
            let dir = (part as NSString).deletingLastPathComponent, name = (part as NSString).lastPathComponent
            return dir + "/_rels/" + name + ".rels"
        }

        static func authors(_ zip: Pptx.Zip) -> [String: String] {
            var out: [String: String] = [:]
            if let a = try? zip.xml("ppt/authors.xml") { for n in a.all("author") { if let id = n.attr("id") { out[id] = n.attr("name") ?? "" } } }
            return out
        }

        static func paras(_ n: Pptx.Node) -> String {
            guard let body = n.first("txBody") else { return "" }
            return body.all("p").map { p in p.all("t").map(\.value).joined() }.joined(separator: "\n")
        }

        static func read(_ zip: Pptx.Zip) throws -> [Thread] {
            let names = authors(zip)
            var out: [Thread] = []
            for s in try slides(zip) {
                let rels = (try? relsFile(zip, s.part)) ?? []
                var k = 0
                for r in rels where r.type == relComments {
                    guard let list = try zip.xml(Pptx.normalize((s.part as NSString).deletingLastPathComponent + "/" + r.target)) else { continue }
                    for cm in list.all("cm") {
                        k += 1
                        let tid = "s\(s.number)c\(k)"
                        var items = [Item(id: tid, author: names[cm.attr("authorId") ?? ""] ?? "someone", date: cm.attr("created") ?? "", text: paras(cm))]
                        for (i, rp) in (cm.first("replyLst")?.all("reply") ?? []).enumerated() {
                            items.append(Item(id: "\(tid).\(i + 1)", author: names[rp.attr("authorId") ?? ""] ?? "someone", date: rp.attr("created") ?? "", text: paras(rp)))
                        }
                        out.append(Thread(id: tid, anchor: nil, place: "slide \(s.number)", items: items, resolved: ["resolved", "closed"].contains(cm.attr("status") ?? "")))
                    }
                }
                // Legacy comments: read only.
                if let leg = rels.first(where: { $0.type == relLegacy }),
                   let list = try zip.xml(Pptx.normalize((s.part as NSString).deletingLastPathComponent + "/" + leg.target)) {
                    let legacyNames: [String: String] = {
                        var m: [String: String] = [:]
                        if let a = try? zip.xml("ppt/commentAuthors.xml") { for n in a.all("cmAuthor") { if let id = n.attr("id") { m[id] = n.attr("name") ?? "" } } }
                        return m
                    }()
                    for cm in list.all("cm") {
                        k += 1
                        let tid = "s\(s.number)c\(k)"
                        out.append(Thread(id: tid, anchor: nil, place: "slide \(s.number)",
                                          items: [Item(id: tid, author: legacyNames[cm.attr("authorId") ?? ""] ?? "someone", date: cm.attr("dt") ?? "", text: cm.first("text")?.value ?? "")],
                                          resolved: false, legacy: true))
                    }
                }
            }
            return out
        }

        struct Rel { var id: String; var type: String; var target: String }
        static func relsFile(_ zip: Pptx.Zip, _ part: String) throws -> [Rel] {
            guard let x = try zip.xml(relsPart(part)) else { return [] }
            return x.all("Relationship").compactMap { n in n.attr("Id").flatMap { id in n.attr("Type").flatMap { t in n.attr("Target").map { Rel(id: id, type: t, target: $0) } } } }
        }

        static func slide(_ zip: Pptx.Zip, number: Int) throws -> SlideRef {
            let all = try slides(zip)
            guard number >= 1, number <= all.count else { throw Failure("the deck has \(all.count) slides, not \(number)") }
            return all[number - 1]
        }

        static func slideNumber(_ at: String) throws -> Int {
            let digits = at.lowercased().replacingOccurrences(of: "slide", with: "").trimmingCharacters(in: .whitespaces)
            guard let n = Int(digits) else { throw Failure("name a slide number to comment on (`--at 3`); comments on one shape aren't written yet") }
            return n
        }

        static func guid() -> String { "{" + UUID().uuidString.uppercased() + "}" }

        static func body(_ text: String) -> String {
            "<p188:txBody><a:bodyPr/><a:lstStyle/>" + text.split(separator: "\n", omittingEmptySubsequences: false).map { "<a:p><a:r><a:rPr lang=\"en-US\"/><a:t>\(esc(String($0)))</a:t></a:r></a:p>" }.joined() + "</p188:txBody>"
        }

        /// The author's id in authors.xml, adding the author (and the part) if need be.
        static func authorID(_ zip: Pptx.Zip, _ files: inout [String: Data], _ edit: inout Edit, name: String) -> String {
            let display = display(name)
            var xml = edit.authors ?? string(try? zip.read("ppt/authors.xml")) ?? ""
            if xml.isEmpty {
                xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<p188:authorLst xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p188=\"\(p188)\"></p188:authorLst>"
                edit.newAuthorsPart = true
            }
            // An existing author of that name.
            var rest = Substring(xml)
            while let r = rest.range(of: "<p188:author ") {
                let tail = rest[r.upperBound...]
                guard let end = tail.firstIndex(of: ">") else { break }
                let tag = String(tail[..<end])
                if let n = attr(tag, "name"), unesc(n).lowercased() == display.lowercased(), let id = attr(tag, "id") { edit.authors = xml; return id }
                rest = tail[end...]
            }
            let id = guid()
            _ = insert(&xml, "<p188:author id=\"\(id)\" name=\"\(esc(display))\" initials=\"\(esc(initials(display)))\" userId=\"\(esc(display))\" providerId=\"None\"/>", before: "</p188:authorLst>")
            edit.authors = xml
            return id
        }

        static func attr(_ tag: String, _ name: String) -> String? {
            guard let r = tag.range(of: " \(name)=\"") ?? (tag.hasPrefix("\(name)=\"") ? tag.range(of: "\(name)=\"") : nil) else { return nil }
            return String(tag[r.upperBound...].prefix(while: { $0 != "\"" }))
        }

        struct Edit { var authors: String?; var newAuthorsPart = false }

        static func commit(_ zip: Pptx.Zip, _ files: inout [String: Data], _ edit: Edit) throws {
            guard let a = edit.authors else { return }
            files["ppt/authors.xml"] = Data(a.utf8)
            if edit.newAuthorsPart {
                var rels = string(try zip.read("ppt/_rels/presentation.xml.rels")) ?? ""
                addRel(&rels, id: freshID("rIdDuoAuthors", in: rels), type: relAuthors, target: "authors.xml")
                var ct = string(try zip.read("[Content_Types].xml")) ?? ""
                addOverride(&ct, part: "/ppt/authors.xml", type: "application/vnd.ms-powerpoint.authors+xml")
                files["ppt/_rels/presentation.xml.rels"] = Data(rels.utf8); files["[Content_Types].xml"] = Data(ct.utf8)
            }
        }

        static func creationID(_ zip: Pptx.Zip, _ part: String) -> String {
            guard let s = string(try? zip.read(part)), let r = s.range(of: "creationId") else { return "0" }
            let tail = s[r.upperBound...]
            guard let v = tail.range(of: "val=\"") else { return "0" }
            return String(tail[v.upperBound...].prefix(while: { $0 != "\"" }))
        }

        /// The slide's modern comments part, if it has one.
        static func commentsPart(_ zip: Pptx.Zip, _ s: SlideRef) throws -> (part: String, rel: Rel)? {
            guard let r = try relsFile(zip, s.part).first(where: { $0.type == relComments }) else { return nil }
            return (Pptx.normalize((s.part as NSString).deletingLastPathComponent + "/" + r.target), r)
        }

        static func add(_ zip: Pptx.Zip, _ files: inout [String: Data], at: String, author: String, text: String, now: Date) throws -> Written {
            let s = try slide(zip, number: try slideNumber(at))
            var edit = Edit()
            let aid = authorID(zip, &files, &edit, name: author)
            let cm = "<p188:cm id=\"\(guid())\" authorId=\"\(aid)\" created=\"\(iso(now, millis: true))\">"
                + "<pc:sldMkLst xmlns:pc=\"http://schemas.microsoft.com/office/powerpoint/2013/main/command\"><pc:docMk/><pc:sldMk cId=\"\(creationID(zip, s.part))\" sldId=\"\(s.sldId)\"/></pc:sldMkLst>"
                + body(text) + "</p188:cm>"
            if let existing = try commentsPart(zip, s) {
                var xml = string(try zip.read(existing.part)) ?? ""
                guard insert(&xml, cm, before: "</p188:cmLst>") else { throw Failure("damaged \(existing.part)") }
                files[existing.part] = Data(xml.utf8)
            } else {
                let cid = UInt32(creationID(zip, s.part)) ?? 0
                let name = "ppt/comments/modernComment_\(String(Int(s.sldId) ?? 0, radix: 16, uppercase: true))_\(String(cid, radix: 16, uppercase: true)).xml"
                files[name] = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<p188:cmLst xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p188=\"\(p188)\">" + cm + "</p188:cmLst>").utf8)
                var rels = string(try zip.read(relsPart(s.part))) ?? "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"></Relationships>"
                addRel(&rels, id: freshID("rIdDuoCm", in: rels), type: relComments, target: "../comments/" + (name as NSString).lastPathComponent)
                files[relsPart(s.part)] = Data(rels.utf8)
                var ct = string(try zip.read("[Content_Types].xml")) ?? ""
                addOverride(&ct, part: "/" + name, type: "application/vnd.ms-powerpoint.comments+xml")
                files["[Content_Types].xml"] = Data(ct.utf8)
            }
            try commit(zip, &files, edit)
            let n = try read(zip).filter { $0.place == "slide \(s.number)" }.count + 1
            return Written(id: "s\(s.number)c\(n)", summary: "Commented in \(display(author))'s name on slide \(s.number) (thread s\(s.number)c\(n)).")
        }

        /// Finds thread `id` (`s3c1`): its slide, comments part and the position of its `<p188:cm`.
        static func locate(_ zip: Pptx.Zip, _ id: String) throws -> (slide: SlideRef, part: String, k: Int, number: Int) {
            let thread = id.trimmingCharacters(in: CharacterSet(charactersIn: "#")).components(separatedBy: ".")[0]
            guard thread.hasPrefix("s"), let c = thread.firstIndex(of: "c"), let sn = Int(thread[thread.index(after: thread.startIndex)..<c]), let k = Int(thread[thread.index(after: c)...]) else {
                throw Failure("no thread \(id): PowerPoint threads are named like s3c1 (slide 3, its first comment)")
            }
            let s = try slide(zip, number: sn)
            guard let cp = try commentsPart(zip, s) else { throw Failure("slide \(sn) has no comments Duo can write (legacy comments are read only)") }
            // The k-th comment of the slide counts modern ones first, as `read` does.
            guard let list = try zip.xml(cp.part), k >= 1, k <= list.all("cm").count else { throw Failure("no thread \(thread) in this deck") }
            return (s, cp.part, k, sn)
        }

        /// The range of the k-th `<p188:cm ...>…</p188:cm>` in a part's text.
        static func cmRange(_ xml: String, _ k: Int) -> Range<String.Index>? {
            var from = xml.startIndex, n = 0
            while let r = xml.range(of: "<p188:cm ", range: from..<xml.endIndex) {
                n += 1
                guard let e = xml.range(of: "</p188:cm>", range: r.upperBound..<xml.endIndex) else { return nil }
                if n == k { return r.lowerBound..<e.upperBound }
                from = e.upperBound
            }
            return nil
        }

        static func reply(_ zip: Pptx.Zip, _ files: inout [String: Data], to thread: String, author: String, text: String, now: Date) throws -> Written {
            let loc = try locate(zip, thread)
            var edit = Edit()
            let aid = authorID(zip, &files, &edit, name: author)
            var xml = string(try zip.read(loc.part)) ?? ""
            guard let range = cmRange(xml, loc.k) else { throw Failure("damaged \(loc.part)") }
            var cm = String(xml[range])
            let reply = "<p188:reply id=\"\(guid())\" authorId=\"\(aid)\" created=\"\(iso(now, millis: true))\">" + body(text) + "</p188:reply>"
            if !insert(&cm, reply, before: "</p188:replyLst>") {
                // Child order matters (MS-PPTX, research-comments §1.2): anchor, pos, replyLst, then txBody. PowerPoint drops replies
                // that come after the comment's own txBody, so a new list goes before it.
                guard insert(&cm, "<p188:replyLst>" + reply + "</p188:replyLst>", before: "<p188:txBody>") else { throw Failure("damaged \(loc.part)") }
            }
            xml.replaceSubrange(range, with: cm)
            files[loc.part] = Data(xml.utf8)
            try commit(zip, &files, edit)
            let n = (try? read(zip).first(where: { $0.id == "s\(loc.number)c\(loc.k)" })?.items.count) ?? 1
            return Written(id: "s\(loc.number)c\(loc.k).\(n)", summary: "Replied in thread s\(loc.number)c\(loc.k) as \(display(author)).")
        }

        static func resolve(_ zip: Pptx.Zip, _ files: inout [String: Data], thread: String, resolved: Bool) throws -> Written {
            let loc = try locate(zip, thread)
            var xml = string(try zip.read(loc.part)) ?? ""
            guard let range = cmRange(xml, loc.k), let gt = xml[range].firstIndex(of: ">") else { throw Failure("damaged \(loc.part)") }
            var tag = String(xml[range.lowerBound..<gt])
            let status = resolved ? "resolved" : "active"
            if tag.contains(" status=\"") { tag = tag.replacingOccurrences(of: " status=\"[^\"]*\"", with: " status=\"\(status)\"", options: .regularExpression) }
            else { tag += " status=\"\(status)\"" }
            xml.replaceSubrange(range.lowerBound..<gt, with: tag)
            files[loc.part] = Data(xml.utf8)
            return Written(id: "s\(loc.number)c\(loc.k)", summary: "Thread s\(loc.number)c\(loc.k) is \(resolved ? "resolved" : "open again").")
        }
    }
}
