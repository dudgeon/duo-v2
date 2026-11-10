import DuoControl
import DuoKit
import DuoSearch
import Foundation

// DL-331: comments written into a Word and a PowerPoint file. A comment, a reply and a resolved state go into the comment parts
// (and the anchors a comment needs); every other part stays byte for byte as it was; the result reads back with Duo's own readers
// (Docx.outline, Pptx.outline, OfficeComments); routing reads the threads as Review threads. Fixtures are the committed ones.
@MainActor func officeCommentChecks() throws {
    print("comments written into Word and PowerPoint files (DL-331)")
    let root = repoRoot()
    let scratch = FileManager.default.temporaryDirectory.appending(path: "duo-office-checks-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let now = ISO8601DateFormatter().date(from: "2026-11-10T09:30:00Z")!

    /// The parts whose bytes differ between two files (by name), and the parts added.
    func changed(_ a: URL, _ b: URL) throws -> (changed: Set<String>, added: Set<String>, removed: Set<String>) {
        let x = try OfficeZip.rawParts(Data(contentsOf: a)), y = try OfficeZip.rawParts(Data(contentsOf: b))
        return (Set(x.keys.filter { y[$0] != nil && y[$0] != x[$0] }), Set(y.keys).subtracting(x.keys), Set(x.keys).subtracting(y.keys))
    }

    // MARK: Word
    let docx = scratch.appending(path: "Review.docx")
    try FileManager.default.copyItem(at: root.appending(path: "docs/design/docx-viewer-handoff/fixture/markup/Word markup.docx"), to: docx)
    let docx0 = scratch.appending(path: "Review.orig.docx")
    try FileManager.default.copyItem(at: docx, to: docx0)
    let before = try OfficeComments.threads(docx)
    check(before.count >= 5 && before.contains { $0.items.count > 1 } && before.contains { $0.resolved }, "reads a Word file's threads with replies and resolved state (\(before.count))")
    let beforeOutline = try Docx.outline(docx)

    let w = try OfficeComments.add(docx, at: "forty", author: "Geoff Q", text: "@claude is this right?\nSecond line.", now: now)
    var t = try OfficeComments.threads(docx)
    check(t.count == before.count + 1, "a comment is added to the Word file")
    let mine = t.first { $0.id == w.id }
    check(mine?.anchor == "forty" && mine?.root.author == "Geoff Q" && mine?.root.text == "@claude is this right?\nSecond line." && mine?.root.date == "2026-11-10T09:30:00Z", "…on the text it names, with its author, date and text")
    let d1 = try changed(docx0, docx)
    check(d1.changed == ["word/comments.xml", "word/commentsExtended.xml", "word/document.xml"] && d1.added.isEmpty && d1.removed.isEmpty,
          "only the comment parts and the anchors changed; every other part is byte for byte as it was (\(d1.changed.sorted()))")
    let afterOutline = try Docx.outline(docx)
    check(afterOutline.map(\.text) == beforeOutline.map(\.text) && afterOutline.count == beforeOutline.count, "the document's text reads the same")
    check(afterOutline.flatMap(\.comments).contains { $0.author == "Geoff Q" && $0.text.hasPrefix("@claude") }, "Duo's own Word reader sees the comment on its paragraph")

    // Review adapter: routing reads it
    let review = try AppModel.officeReviewThreads(docx)
    let rt = review.first { $0.id == w.id }
    check(rt?.root?.author == "geoff-q" && rt?.comments.first?.mentionsClaude == true && rt?.anchor == "forty", "routing sees it as a Review thread that names @claude, signed geoff-q")

    let turn = AppModel.officeTurnText(name: "Review.docx", place: mine?.place ?? "", thread: rt!)
    check(turn.hasPrefix("@claude comment in Review.docx, paragraph ") && turn.contains("(thread \(w.id)), from geoff-q") && turn.contains("On: “forty”")
          && turn.contains("> @geoff-q: @claude is this right?") && turn.contains("duo2 comment reply \(w.id) \"<text>\" --file \"Review.docx\"") && !turn.contains("line 0") && !turn.contains("--suggest"),
          "the turn sent to a session names the file and paragraph, quotes the thread as data and tells Claude to reply with --file")
    let r = try OfficeComments.reply(docx, to: w.id, author: "claude", text: "Yes: forty-two.", now: now)
    t = try OfficeComments.threads(docx)
    let withReply = t.first { $0.id == w.id }
    check(withReply?.items.count == 2 && withReply?.items[1].author == "Claude" && withReply?.items[1].id == r.id && withReply?.items[1].text == "Yes: forty-two.", "a reply goes in the thread, signed Claude")
    let outline2 = try Docx.outline(docx).flatMap(\.comments)
    check(outline2.contains { $0.text == "Yes: forty-two." && $0.parent != nil && $0.thread == outline2.first { $0.text.hasPrefix("@claude") }?.id },
          "Docx.outline reads it as a reply to the comment (commentsExtended)")
    let review2 = try AppModel.officeReviewThreads(docx).first { $0.id == w.id }
    check(review2?.comments.contains { $0.author == "claude" } == true, "routing sees Claude's reply as claude's")

    _ = try OfficeComments.resolve(docx, thread: w.id, resolved: true)
    check(try OfficeComments.threads(docx).first { $0.id == w.id }?.resolved == true, "resolving marks the thread done")
    check(try Docx.outline(docx).flatMap(\.comments).filter { $0.thread == outline2.first { $0.text.hasPrefix("@claude") }?.id }.allSatisfy(\.resolved), "Docx.outline sees the root and its reply resolved")
    _ = try OfficeComments.resolve(docx, thread: w.id, resolved: false)
    check(try OfficeComments.threads(docx).first { $0.id == w.id }?.resolved == false, "…and open again")

    // A reply to a comment a person wrote in Word (it has its own paraId and thread)
    let existing = before.first { !$0.resolved && $0.items.count == 1 }
    if let existing {
        let rr = try OfficeComments.reply(docx, to: existing.id, author: "claude", text: "Looking.", now: now)
        check(try OfficeComments.threads(docx).first { $0.id == existing.id }?.items.last?.id == rr.id, "a reply to a thread a person started in Word lands in that thread")
    } else { check(false, "the fixture has an open one-comment thread") }

    // Refusals
    check((try? OfficeComments.add(docx, at: "nonexistent phrase", author: "x", text: "y")) == nil, "a text that isn't in the document is refused")
    check((try? OfficeComments.add(docx, at: "the", author: "x", text: "y")) == nil, "a text that appears more than once is refused")
    check((try? OfficeComments.reply(docx, to: "c999", author: "x", text: "y")) == nil, "a reply to a thread that isn't there is refused")
    let p1 = try OfficeComments.add(docx, at: "1", author: "claude", text: "On the first paragraph.", now: now)
    check(try OfficeComments.threads(docx).contains { $0.id == p1.id }, "a paragraph number anchors a comment on the whole paragraph")

    // MARK: PowerPoint
    let pptx = scratch.appending(path: "Deck.pptx")
    try FileManager.default.copyItem(at: root.appending(path: "docs/design/duo-decks-study/samples/import/grower-update.pptx"), to: pptx)
    let pptx0 = scratch.appending(path: "Deck.orig.pptx")
    try FileManager.default.copyItem(at: pptx, to: pptx0)
    let pb = try OfficeComments.threads(pptx)
    check(pb.contains { $0.place == "slide 5" && $0.items.count == 2 && $0.root.text.hasPrefix("Is the footnote") } && pb.contains { $0.legacy && $0.place == "slide 3" },
          "reads a PowerPoint file's modern comment with its reply and the legacy one (\(pb.map(\.id)))")
    let slidesBefore = try Pptx.outline(pptx).count

    let pa = try OfficeComments.add(pptx, at: "2", author: "Geoff Q", text: "@claude shorten this slide", now: now)
    let pt = try OfficeComments.threads(pptx)
    check(pa.id == "s2c1" && pt.first { $0.id == "s2c1" }?.root.text == "@claude shorten this slide" && pt.first { $0.id == "s2c1" }?.place == "slide 2", "a comment is added to a slide that had none (new comments part)")
    let pd = try changed(pptx0, pptx)
    check(pd.changed.isSubset(of: ["ppt/slides/_rels/slide2.xml.rels", "[Content_Types].xml", "ppt/authors.xml"]) && pd.changed.contains("ppt/slides/_rels/slide2.xml.rels")
          && pd.added.count == 1 && pd.added.first?.hasPrefix("ppt/comments/modernComment_") == true && pd.removed.isEmpty,
          "only the slide's relationships, the content types, the authors and the new comments part changed (\(pd.changed.sorted()) + \(pd.added.sorted()))")
    check(try Pptx.outline(pptx).count == slidesBefore, "the deck still reads: same slide count")
    let ar = try AppModel.officeReviewThreads(pptx).first { $0.id == "s2c1" }
    check(ar?.root?.author == "geoff-q" && ar?.comments.first?.mentionsClaude == true, "routing sees it as a Review thread that names @claude")

    let pr = try OfficeComments.reply(pptx, to: "s2c1", author: "claude", text: "Cut to three bullets.", now: now)
    let pt2 = try OfficeComments.threads(pptx).first { $0.id == "s2c1" }
    check(pr.id == "s2c1.1" && pt2?.items.count == 2 && pt2?.items[1].author == "Claude", "a reply goes in the slide's thread, signed Claude (authors.xml gets Claude once)")
    let existingReply = try OfficeComments.reply(pptx, to: "s5c1", author: "claude", text: "Yes, only here.", now: now)
    check(try OfficeComments.threads(pptx).first { $0.id == "s5c1" }?.items.count == 3 && existingReply.id == "s5c1.2", "a reply to a thread a person started in PowerPoint lands in that thread, after the reply there")
    let authorsXML = String(decoding: try Pptx.Zip(pptx).read("ppt/authors.xml") ?? Data(), as: UTF8.self)
    check(authorsXML.components(separatedBy: "name=\"Claude\"").count == 2, "Claude is one author in authors.xml however many times it writes")

    _ = try OfficeComments.resolve(pptx, thread: "s5c1", resolved: true)
    check(try OfficeComments.threads(pptx).first { $0.id == "s5c1" }?.resolved == true, "a PowerPoint thread resolves (status=resolved)")
    _ = try OfficeComments.resolve(pptx, thread: "s5c1", resolved: false)
    check(try OfficeComments.threads(pptx).first { $0.id == "s5c1" }?.resolved == false, "…and opens again")
    check((try? OfficeComments.add(pptx, at: "99", author: "x", text: "y")) == nil, "a slide that isn't there is refused")
    check((try? OfficeComments.reply(pptx, to: "s3c1", author: "x", text: "y")) == nil, "a reply to a legacy comment is refused (read only)")
    let pd2 = try changed(pptx0, pptx)
    check(!pd2.changed.contains { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") } && !pd2.changed.contains("ppt/presentation.xml"), "no slide, layout or presentation part was touched")

    // The backup holds the first original
    let backups = scratch.appending(path: "backups")
    _ = try OfficeComments.add(pptx, at: "1", author: "claude", text: "Backup test", now: now, backups: backups)
    let kept = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []
    check(kept.count == 1 && kept[0].hasSuffix("Deck.pptx"), "a backup of the file as it was is kept before the write")
}
