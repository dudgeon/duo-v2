import DuoControl
import DuoKit
import Foundation

// DL-236, DL-237: the review model (CriticMarkup parse and edits), Suggest Edits in the frontmatter,
// the convention paragraph and the duo2 review verbs' registration.
@MainActor func reviewChecks() throws {
    print("review in Markdown: marks, threads, closing, suggestions (DL-236, DL-237)")
    let doc = """
    ---
    title: One-pager
    ---
    # Offline

    The price is {~~30~>10~~}{>>@sam 2026-10-27 #s1: matches the deck<<} euros. It is {==cheap enough==}{>>@geoff 2026-10-27 #c1: really?<<}{>>@sam 2026-10-27 #c1.1: yes<<}.
    Add {++a line++}{>>@claude 2026-10-28 #s2<<} and {--cut this--}{>>@geoff 2026-10-28 #s3: drop<<}.
    `{++not a mark++}` stays. @claude can you tighten this? {>>@geoff 2026-10-28 #c2: bare<<}

    ```
    {==code==}{>>@x 2026-10-28 #c9: no<<}
    ```
    """
    let p = Review.parse(doc)
    check(p.suggestions.count == 3, "three suggestions are read, none from code (\(p.suggestions.count))")
    check(p.suggestions.first?.kind == .substitution && p.suggestions.first?.old == "30" && p.suggestions.first?.new == "10", "a substitution reads old and new")
    check(p.suggestions.first?.author == "sam" && p.suggestions.first?.date == "2026-10-27" && p.suggestions.first?.id == "s1" && p.suggestions.first?.note == "matches the deck", "its signature note gives author, date, id and note")
    check(p.suggestions[1].kind == .insertion && p.suggestions[1].id == "s2" && p.suggestions[1].note == "", "an insertion with a signature and no note")
    check(p.suggestions[2].kind == .deletion && p.suggestions[2].old == "cut this", "a deletion")
    check(p.threads.count == 2, "two threads (\(p.threads.map(\.id)))")
    let c1 = p.thread("c1")
    check(c1?.anchor == "cheap enough" && c1?.comments.count == 2 && c1?.replies.first?.text == "yes" && c1?.closed == false, "a thread has its anchor, comment and reply")
    check(p.thread("c2")?.anchor == nil, "a comment with no highlight is a thread with no anchor")
    check(Review.nextID("c", in: doc) == "c10" && Review.nextID("s", in: doc) == "s4", "the next ids come after every id in the file, code included")

    // Writing
    let added = try Review.addComment(to: doc, at: "6", author: "Geoff Q", date: "2026-10-28", body: "why")
    check(added.text.contains("{==# Offline==}") || added.text.contains("{==The price"), "comment --at <line> highlights the line's text")
    check(Review.parse(added.text).thread(added.id)?.root?.author == "geoff-q", "the signature name is lower case with dashes")
    let at = try Review.addComment(to: doc, at: "Offline", author: "claude", date: "2026-10-28", body: "title?")
    check(at.text.contains("{==Offline==}{>>@claude 2026-10-28 #c10: title?<<}"), "comment --at <text> highlights it and signs")
    check((try? Review.addComment(to: doc, at: "nowhere", author: "a", date: "d", body: "x")) == nil, "a missing text fails")
    check((try? Review.addComment(to: doc, at: "not a mark", author: "a", date: "d", body: "x")) == nil, "text inside a mark or code is not an anchor")

    let replied = try Review.reply(in: doc, to: "c1", author: "claude", date: "2026-10-28", body: "I think so")
    check(replied.id == "c1.2" && replied.text.contains("{>>@sam 2026-10-27 #c1.1: yes<<}{>>@claude 2026-10-28 #c1.2: I think so<<}"), "a reply goes after the last comment with the next number")
    let sugg = try Review.reply(in: doc, to: "c1", author: "claude", date: "2026-10-28", body: "inexpensive", suggest: true)
    let ps = Review.parse(sugg.text)
    check(sugg.id == "s4" && ps.suggestion("s4")?.old == "cheap enough" && ps.suggestion("s4")?.new == "inexpensive" && ps.suggestion("s4")?.comments.count == 3, "reply --suggest makes a signed substitution and keeps the thread's comments")

    let closed = try Review.close(in: doc, id: "c1", author: "geoff", date: "2026-10-28")
    check(closed.id == "c1.2" && closed.text.contains("{>>@sam 2026-10-27 #c1.1: yes<<}{>>@geoff 2026-10-28 #c1.2 closed<<}"), "closing is a reply, `#c1.2 closed`")
    let pc = Review.parse(closed.text)
    check(pc.thread("c1")?.closed == true && pc.open.map(\.id) == ["c2"] && pc.closed.map(\.id) == ["c1"] && pc.thread("c1")?.comments.count == 3, "a closed thread keeps its comments and counts as closed")
    check(closed.text.contains("{==cheap enough==}"), "closing keeps the highlight")
    check((try? Review.close(in: closed.text, id: "c1", author: "a", date: "d")) == nil, "closing twice fails")
    let rep2 = try Review.reply(in: closed.text, to: "c1", author: "sam", date: "2026-10-29", body: "more")
    check(rep2.id == "c1.3" && !rep2.text.contains("closed<<}") && Review.parse(rep2.text).thread("c1")?.closed == false, "a reply reopens (the closing line goes)")
    check(try Review.reopen(in: closed.text, id: "c1").text == doc, "reopen is exactly the closing line removed")
    let gone = try Review.delete(in: doc, id: "c1")
    check(gone.text.contains("It is cheap enough.") && Review.parse(gone.text).thread("c1") == nil && !gone.text.contains("#c1"), "delete removes markers and every comment, keeps the text")
    check((try? Review.delete(in: doc, id: "c7")) == nil, "an unknown thread fails")

    let acc = try Review.resolve(in: doc, id: "s1", accept: true)
    check(acc.text.contains("The price is 10 euros.") && !acc.text.contains("#s1"), "accept a substitution takes the new text and the comments go")
    let rej = try Review.resolve(in: doc, id: "s1", accept: false)
    check(rej.text.contains("The price is 30 euros."), "reject puts the old text back")
    check(try Review.resolve(in: doc, id: "s3", accept: true).text.contains("and ."), "accept a deletion removes the text")
    check(try Review.resolve(in: doc, id: "s2", accept: false).text.contains("Add  and"), "reject an insertion removes it")
    let all = Review.resolveAll(in: doc, accept: true)
    check(all.count == 3 && Review.parse(all.text).suggestions.isEmpty && Review.parse(all.text).thread("c1") != nil, "accept all leaves the comment threads")
    check(Review.resolveAll(in: doc, accept: true, author: "claude").count == 1, "accept all by one person")

    // What the builders write reads back (the converter uses them)
    let built = "A " + Review.substitution("old", "new") + Review.comment(author: "Sam Smith", date: "2026-10-28", id: "s1", text: "why <<} not") + " b"
    let rb = Review.parse(built)
    check(rb.suggestions.count == 1 && rb.suggestions[0].author == "sam-smith" && rb.suggestions[0].new == "new", "marks the builders write parse back")
    check(rb.suggestions[0].note == "why < <} not", "a note can't hold the closing mark")
    check(Review.parse("plain text with {braces} and {+ nothing +}").isEmpty, "text that only looks like marks is left alone")
    check(Review.parse("{++open never closed").isEmpty, "an unclosed mark is text")

    // Suggest Edits
    check(!Review.suggestEdits(doc), "off when the frontmatter doesn't say")
    let on = Review.settingSuggestEdits(doc, on: true)
    check(Review.suggestEdits(on) && on.hasPrefix("---\ntitle: One-pager\nsuggest-edits: true\n---\n"), "on adds the property to the frontmatter")
    check(Review.settingSuggestEdits(on, on: false) == doc, "off removes it and the document is as it was")
    check(Review.settingSuggestEdits(doc, on: false) == doc, "off on a document that never used it touches nothing")
    check(Review.settingSuggestEdits("# Hi\n", on: true) == "---\nsuggest-edits: true\n---\n\n# Hi\n", "a document with no frontmatter gets one while on")
    let flipped = Review.settingSuggestEdits("---\nsuggest-edits: false\n---\nx", on: true)
    check(flipped.contains("suggest-edits: true") && !flipped.contains("false"), "a false line is switched, not doubled")

    // The editor's grammar (Vendor/codemirror/src/critic.js) reads the same marks and signs typing and Claude's edits (stage 2)
    let script = repoRoot().appending(path: "Vendor/codemirror/test/run.sh")
    if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/node") || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/node") {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = [script.path]
        p.environment = ProcessInfo.processInfo.environment.merging(["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]) { $1 }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try? p.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        check(p.terminationStatus == 0, "the editor module's own checks pass (critic.test.mjs)" + (p.terminationStatus == 0 ? "" : ":\n" + out))
    } else { print("  (node isn't installed: the editor module's own checks are skipped)") }
    let editorJS = (try? String(contentsOf: repoRoot().appending(path: "Vendor/codemirror/src/duo-editor.js"), encoding: .utf8)) ?? ""
    check(editorJS.contains("reviewCore,") && editorJS.contains("reviewDrawing"), "the editor loads the review module: parse always, drawing with the live preview")

    // Marks the converter writes (Q-283): a deletion inside a commented range, a comment over two paragraphs
    let conv = "Some {=={--some old words--}{>>@morgan-editor 2026-09-06 #s2: <<}==}{>>@riley-reviewer 2026-09-06 #c3: why<<} here.\n\n{==First paragraph.==}\n\n{==Second paragraph.==}{>>@riley-reviewer 2026-09-05 #c5: both<<}{>>@dana-writer 2026-09-05 #c5.1: yes<<}\n"
    let pcv = Review.parse(conv)
    check(pcv.suggestions.map(\.id) == ["s2"] && pcv.suggestion("s2")?.kind == .deletion && pcv.suggestion("s2")?.old == "some old words", "a deletion inside a highlight is a suggestion of its own")
    check(pcv.threads.map(\.id) == ["c3", "c5"] && pcv.thread("c3")?.pieces.count == 1 && pcv.thread("c3")?.anchor == "some old words", "the highlight stays the thread's anchor")
    check(pcv.thread("c5")?.pieces.count == 2 && pcv.thread("c5")?.anchor == "First paragraph.\n\nSecond paragraph." && pcv.thread("c5")?.comments.count == 2, "a comment over two paragraphs is one thread, a highlight in each")
    let del = try Review.delete(in: conv, id: "c5")
    check(del.text.contains("First paragraph.\n\nSecond paragraph.\n") && !del.text.contains("{==") || del.text.contains("{--some old words--}"), "Delete takes every highlight's markers and the comments, keeps the text")
    let del3 = try Review.delete(in: conv, id: "c3")
    check(del3.text.contains("{--some old words--}{>>@morgan-editor 2026-09-06 #s2: <<}") && !del3.text.contains("#c3") && !del3.text.contains("{==some"), "deleting a thread keeps the suggestion inside its highlight")
    check(Review.parse(del3.text).suggestion("s2") != nil, "…and it is still a suggestion")
    let accv = try Review.resolve(in: conv, id: "s2", accept: true)
    check(accv.text.contains("Some {==") && Review.parse(accv.text).thread("c3") != nil, "accepting it leaves the thread")

    // @claude comments (DL-236 9A, 10A): where one goes first, and what the turn says
    check(Review.firstGuess(thread: "t", document: "d", lastEditor: "e", onScreen: "s") == "t", "the first guess is the thread's session")
    check(Review.firstGuess(thread: nil, document: "d", lastEditor: "e", onScreen: "s") == "d", "then this document's last choice")
    check(Review.firstGuess(thread: nil, document: nil, lastEditor: "e", onScreen: "s") == "e", "then the one that last edited it through Duo")
    check(Review.firstGuess(thread: nil, document: nil, lastEditor: nil, onScreen: "s") == "s", "then the one on screen")
    check(Review.firstGuess(thread: "", document: nil, lastEditor: nil, onScreen: nil) == nil, "else none: New Session")
    let ct = Review.parse("Launch is {==planned for early November==}{>>@geoff 2026-10-28 #c2: @claude can you tighten this?<<}{>>@sam 2026-10-28 #c2.1: yes please<<}").thread("c2")!
    let turn = Review.turn(path: "docs/offline.md", line: 9, thread: ct)
    check(turn.hasPrefix("@claude comment in docs/offline.md, line 9 (thread c2), from geoff, 2026-10-28\n"), "the turn starts with where, which thread and from whom")
    check(turn.contains("On: “planned for early November”\n> @geoff: @claude can you tighten this?\n> @sam: yes please\n"), "the turn names the anchor and quotes the thread as data")
    check(turn.contains("duo2 comment reply c2 \"<text>\"") && turn.contains("--suggest") && !turn.contains("\u{1b}"), "the turn says how to reply, as plain text")
    check(ct.comments.contains(where: \.mentionsClaude) && !Review.parse("{==a==}{>>@geoff 2026-10-28 #c3: just a note<<}").threads[0].comments.contains(where: \.mentionsClaude), "a comment names @claude or it doesn't")

    // The paragraph and the verbs
    let c = Review.convention
    for must in ["{++added++}", "never accept or reject", "signed @claude", "#id.n", "closed<<}", "never delete someone's comment", "names @claude", "suggest-edits: true", "duo2 comment reply"] {
        check(c.contains(must), "the convention paragraph says “\(must)”")
    }
    check(c.count < 1400, "the paragraph stays short (\(c.count))")
    let verbs: [ActionID] = [.commentAdd, .commentList, .commentReply, .commentSend, .commentClose, .commentDelete, .commentReopen, .commentStatus, .suggestionList, .suggestionAccept, .suggestionReject, .docReview]
    for id in verbs {
        check(DuoAction.all.contains { $0.id == id } && !id.action.summary.isEmpty, "duo2 \(id.rawValue) is registered with help")
    }
    let inv = Invocation(["f.md", "--at", "3", "hello", "world"])
    check(inv[0] == "f.md" && inv.flags["at"] == "3" && inv.positional.dropFirst().joined(separator: " ") == "hello world", "comment add's arguments parse")
    check(Invocation(["--closed"]).has("closed") && Invocation(["c1", "--all"]).has("all"), "--closed and --all are switches")
}
