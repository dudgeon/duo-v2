import AppKit
import DuoControl
import DuoDeck
import DuoKit
import Foundation

// Duo Decks P3 track A: the deck preview provider (render gating, anchor map, problems, comments,
// shape to slot) and the deck verbs' parity. Pure parts run on the sample deck and the northwind pack;
// the viewer's web view isn't needed.
@MainActor func deckP3aChecks() throws {
    print("Duo Decks P3a: the deck preview provider")
    let study = repoRoot().appending(path: "docs/design/duo-decks-study/samples")
    let deck = study.appending(path: "decks/field-trial-review.md")
    let packs = [study.appending(path: "templates/decks")]
    let text = try String(contentsOf: deck, encoding: .utf8)

    // canPreview and the registration's test
    check(DeckPreview.canPreview(file: "decks/a.md", frontmatter: ["type": "deck"]) && !DeckPreview.canPreview(file: "a.md", frontmatter: [:])
          && !DeckPreview.canPreview(file: "a.html", frontmatter: ["type": "deck"]) && !DeckPreview.canPreview(file: "a.md", frontmatter: ["type": "note"]),
          "canPreview: a .md with type: deck, nothing else")
    check(DeckPreviewRegistration.test("decks/a.md", ["type": "deck"]) && !DeckPreviewRegistration.test("a.md", ["type": "note"]) && !DeckPreviewRegistration.test("a.pptx", ["type": "deck"]),
          "the registered test follows the frontmatter")
    check(DeckPreviewRegistration.frontmatter(of: text)["type"] == "deck" && DeckPreviewBuild.isDeck(text: text) && !DeckPreviewBuild.isDeck(text: "# hello\n"), "frontmatter is read from the first lines")
    let before = PreviewProviders.extra.count
    DeckPreviewRegistration.install(); DeckPreviewRegistration.install()
    check(PreviewProviders.extra.count == before + 1 || PreviewProviders.extra.count == before, "installing twice registers once")
    check(PreviewProviders.kind(forFile: "decks/x.md", frontmatter: ["type": "deck"]) == .deck && PreviewProviders.kind(forFile: "x.md", frontmatter: ["type": "note"]) == .markdown,
          "split view's lookup finds the deck kind before Markdown")

    // a clean render: bytes, no errors, the same bytes as the file export
    let r = DeckPreviewBuild.build(text: text, file: deck, packDirs: packs)
    check(r.bytes != nil && r.problems.filter { $0.severity == .error }.isEmpty && r.slideCount == 9, "the sample renders: bytes, 9 slides, no errors (\(r.problems.map(\.message)))")
    check(r.bytes == (try Deck.export(deck: deck, packDirs: packs)), "the in-memory export is the file export's bytes")

    // anchor map
    func range(_ a: String) -> ClosedRange<Int>? { r.anchors.first { $0.anchor == a }.map { $0.firstLine...$0.lastLine } }
    check(r.anchors.filter { !$0.anchor.contains("/") }.map(\.anchor) == (1...9).map { "slide \($0)" }, "an anchor per slide")
    check(range("slide 1")?.lowerBound == 8 && range("slide 3/value")?.lowerBound == 31, "slide 1 starts at line 8 and slide 3's value at 31 (\(String(describing: range("slide 3/value"))))")
    let s3 = range("slide 3")!, v3 = range("slide 3/value")!
    check(s3.contains(v3.lowerBound) && s3.contains(v3.upperBound), "a slot's lines sit inside its slide's")
    let policy = PreviewPolicy()
    policy.bufferChanged { _ in }
    policy.cancel()
    _ = policy.accept(.anchorMap(rev: policy.rev, r.anchors))
    check(policy.narrowest(containing: v3.lowerBound)?.anchor == "slide 3/value", "split view's policy picks the slot over the slide for a caret line")

    // problems with severities
    let broken = text.replacingOccurrences(of: "- What breaks first in wet weather?\n", with: "- What breaks first in wet weather?\n- One\n- Two\n- Three\n- Four\n- Five\n- Six\n- Seven\n")
    let rb = DeckPreviewBuild.build(text: broken, file: deck, packDirs: packs)
    check(rb.bytes == nil && rb.problems.contains { $0.severity == .error } && rb.slideCount == 9 && !rb.anchors.isEmpty,
          "a deck with errors has no bytes but keeps its map, and the errors are errors (\(rb.problems.map(\.message)))")
    let empty = text.replacingOccurrences(of: "## value\n86%", with: "## value\n")
    let re = DeckPreviewBuild.build(text: empty, file: deck, packDirs: packs)
    check(re.problems.contains { $0.severity == .notice && $0.message.contains("is empty") } && re.problems.filter { $0.severity == .error }.isEmpty && re.bytes != nil,
          "an empty slot is a notice, and the deck still draws (\(re.problems.map { "\($0.severity.rawValue): \($0.message)" }))")
    let nopack = DeckPreviewBuild.build(text: text.replacingOccurrences(of: "template: northwind", with: "template: nowhere"), file: deck, packDirs: packs)
    check(nopack.bytes == nil && nopack.problems.first?.severity == .error && nopack.problems.first?.line == 2, "a missing pack is one error at the frontmatter")

    // comments: the thread id on the slot (or slide) it falls in
    let c1 = try Review.addComment(to: text, at: "86%", author: "sam", date: "2026-11-01", body: "Is this the final figure?")
    let rc = DeckPreviewBuild.build(text: c1.text, file: deck, packDirs: packs)
    check(rc.comments == [CommentAnchor(anchor: "slide 3/value", thread: c1.id)], "a comment on the value is anchored on slide 3/value (\(rc.comments))")
    // (the bytes differ in the source hash alone: the text is not the same text)
    let cTmp = FileManager.default.temporaryDirectory.appending(path: "duo-p3a-c-\(getpid()).pptx")
    defer { try? FileManager.default.removeItem(at: cTmp) }
    try rc.bytes!.write(to: cTmp)
    let cGot = try Deck.inspect(cTmp)
    let cText = cGot.slides.flatMap(\.shapes).map(\.text).joined()
    check(rc.shapes == r.shapes && !cText.contains("{") && !cText.contains("final figure"), "comments never reach the export")
    check(rc.anchors.map(\.anchor) == r.anchors.map(\.anchor), "comments don't change the anchors")

    // shape id -> slot, through the template, against the exported pptx
    let tmp = FileManager.default.temporaryDirectory.appending(path: "duo-p3a-\(getpid()).pptx")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try r.bytes!.write(to: tmp)
    let got = try Deck.inspect(tmp)
    let pack = try Deck.loadPack("northwind", in: packs)
    let parsed = Deck.parse(text)
    var mapped = 0, wrong = 0
    for (n, s) in parsed.slides.enumerated() {
        guard let t = pack.template(s.template) else { continue }
        let ids = (r.shapes[n + 1] ?? [:]).keys.sorted()
        for (i, id) in ids.enumerated() where i < got.slides[n].shapes.count {
            mapped += 1
            let idx = got.slides[n].shapes[i].idx
            if t.slots.first(where: { $0.idx == idx })?.name != r.shapes[n + 1]?[id] { wrong += 1 }
        }
    }
    check(mapped >= 15 && wrong == 0, "every drawn slot shape maps to its placeholder's slot through the template (\(mapped) shapes, \(wrong) wrong)")
    check(r.anchor(slide: 3, shapeID: r.shapes[3]!.first { $0.value == "value" }!.key) == "slide 3/value" && r.anchor(slide: 3, shapeID: 999) == "slide 3",
          "a picked shape names slide N/slot, or the slide when it is no slot's")
    check(DeckPreviewBuild.parse(anchor: "slide 3/value")! == (3, "value") && DeckPreviewBuild.parse(anchor: "slide 12")! == (12, nil) && DeckPreviewBuild.parse(anchor: "h:2") == nil, "anchors parse back")

    // the provider: bound to a file, with no app (the web view alone), gate and events
    _ = NSApplication.shared
    let p = DeckPreview(resources: repoRoot().appending(path: "Vendor/pptx-renderer"))
    var events: [PreviewEvent] = []
    p.emit = { events.append($0) }
    p.bind(path: "decks/field-trial-review.md", file: deck, model: nil)
    check(p.view === p.viewer.webView && p.kind == .deck, "without an app the provider's view is the slides alone")
    func pump(_ until: () -> Bool) { let end = Date().addingTimeInterval(20); while !until(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } }
    p.render(text: text, rev: 5)
    p.render(text: broken, rev: 3)   // older than the newest: dropped at the gate
    pump { p.renders >= 1 }
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    check(p.renders == 1 && p.renderedRev == 5, "a render older than the newest is dropped (rendered rev \(p.renderedRev), \(p.renders) renders)")
    let maps = events.compactMap { e -> Int? in if case .anchorMap(let rev, _) = e { return rev } else { return nil } }
    let probs = events.compactMap { e -> Int? in if case .problems(let rev, _) = e { return rev } else { return nil } }
    let coms = events.compactMap { e -> Int? in if case .comments(let rev, _) = e { return rev } else { return nil } }
    check(maps == [5] && probs == [5] && coms == [5], "the map, problems and comments are emitted once, with the revision they answer")
    check(p.lines(of: "slide 3/value") == v3 && p.anchor(forLine: v3.lowerBound) == "slide 3/value", "the provider answers lines of an anchor and the anchor of a line")
    check(p.viewer.shownBytes == r.bytes, "the viewer was handed the bytes, not a file (\(p.viewer.shownBytes?.count ?? 0))")
    p.render(text: broken, rev: 6)
    pump { p.renders >= 2 }
    check(p.renders == 2 && p.viewer.shownBytes == r.bytes && p.rendering.problems.contains { $0.severity == .error },
          "a deck with errors keeps the last good drawing and reports the errors")

    // parity: the three verbs exist, are app verbs, and Parity sees them
    for v in ["deck", "deck go", "deck pick"] {
        let hit = DuoAction.resolve(v.split(separator: " ").map(String.init))
        check(hit?.0.verb == v && hit?.0.local == false && hit?.0.family == .deck, "duo2 \(v) is an app verb in the deck family")
    }
    check(DuoAction.resolve(["deck", "check", "x.md"])?.0.verb == "deck check" && DuoAction.resolve(["slide", "go", "2"])?.0.verb == "slide go", "the local deck verbs and slide go still resolve")
}
