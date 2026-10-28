import DuoControl
import Foundation

// `duo2 comment …`, `duo2 suggestion …`, `duo2 doc review` (DL-236, DL-237): the verbs over the
// review model (`Review`, DuoControl/ReviewMarkup.swift). A file open in Duo's editor is changed
// through the buffer, so the user sees it and nothing is lost to their unsaved text; any other file is
// written on disk. The editor's own buttons call the same operations (stages 2 to 4).
extension AppModel {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "txt"]

    /// The file a review verb works on: `--file`, the first positional where the verb takes a path, or the showing document.
    private func reviewFile(_ inv: Invocation, _ req: ControlRequest, path: String?) -> URL? {
        if let s = inv.flags["file"] ?? path {
            if let u = deckFile(s, req: req) { return u }
            let expanded = (s as NSString).expandingTildeInPath
            let u = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : URL(fileURLWithPath: expanded, relativeTo: req.cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }).absoluteURL
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        return editorIfLoaded?.url
    }

    /// Who signs: `--as`, else Claude when a Claude session runs the verb, else the user's Mac account (DL-236 11).
    private func reviewAuthor(_ inv: Invocation, _ req: ControlRequest) -> String {
        if let name = inv.flags["as"], !name.isEmpty { return name }
        return req.session != nil ? "claude" : NSUserName()
    }

    private func isOpenInEditor(_ url: URL) -> EditorController? {
        guard let e = editorIfLoaded, let open = e.url, open.resolvingSymlinksInPath().standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else { return nil }
        return e
    }

    /// The text as the editor has it (unsaved edits included), or the file's.
    func reviewText(_ url: URL, _ done: @escaping @MainActor (String?) -> Void) {
        if let e = isOpenInEditor(url) { e.currentText { done($0) } }
        else if FileKind.isBinary(url) { done(nil) }
        else { done(FileManager.default.contents(atPath: url.path).map { String(decoding: $0, as: UTF8.self) }) }
    }

    /// Write `new` where `old` was: through the editor when the file is open, else to disk.
    func reviewWrite(_ url: URL, old: String, new: String, plain: Bool, _ done: @escaping @MainActor (String?) -> Void) {
        guard new != old else { return done(nil) }
        if let e = isOpenInEditor(url) {
            if let why = e.readOnlyReason { return done("open in Duo but read-only (\(why)); leave it, or ask the user") }
            if e.conflict { return done("open in Duo with a conflict the user hasn't resolved; ask the user before changing it") }
            if plain {
                e.run("return duo.applyPlain(b, t)", ["b": old, "t": new]) { ok in done(ok as? Bool == true ? nil : "the text changed while Duo was writing; try again") }
            } else {
                e.run("return duo.agentEdit(e, c)", ["e": [Any](), "c": new]) { v in
                    let r = (v as? [String: Any])?["result"] as? String
                    done(r == "applied" || r == "unchanged" ? nil : ((v as? [String: Any])?["reason"] as? String ?? "couldn't apply the change"))
                }
            }
        } else {
            do { try Data(new.utf8).write(to: url, options: .atomic); done(nil) } catch { done("couldn't write \(url.lastPathComponent): \(error.localizedDescription)") }
        }
    }

    static func threadLines(_ t: Review.Thread) -> [String] {
        var lines: [String] = []
        let head = t.root
        lines.append("#\(t.id) [\(t.closed ? "closed" : "open")] \(head?.author.map { "@\($0)" } ?? "unsigned")\(head?.date.map { ", \($0)" } ?? "")"
                     + (t.anchor.map { " on “\(Review.abbreviate($0))”" } ?? " (no highlighted text)") + ": " + (head?.text ?? ""))
        for c in t.comments.dropFirst() {
            lines.append("  ↳ #\(c.id ?? "?") \(c.author.map { "@\($0)" } ?? "unsigned")\(c.date.map { ", \($0)" } ?? ""): " + (c.closing ? "closed" : c.text))
        }
        return lines
    }

    static func threadJSON(_ t: Review.Thread) -> [String: Any] {
        ["id": t.id, "closed": t.closed, "anchor": t.anchor as Any, "namesClaude": t.comments.contains { $0.mentionsClaude },
         "comments": t.comments.map { ["id": $0.id as Any, "author": $0.author as Any, "date": $0.date as Any, "text": $0.text, "closing": $0.closing] as [String: Any] }]
    }

    func reviewVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        let takesPath: Set<ActionID> = [.commentAdd, .commentList, .suggestionList]
        let path = takesPath.contains(id) ? inv[0] : nil
        guard let url = reviewFile(inv, req, path: path) else {
            return done(.fail(path == nil && inv.flags["file"] == nil ? "no document is showing: name one with --file <file>" : "no file '\(path ?? inv.flags["file"] ?? "")' here (a path from the project's folder, or absolute)"))
        }
        guard Self.markdownExtensions.contains(url.pathExtension.lowercased()) else { return done(.fail("\(url.lastPathComponent) isn't a Markdown document")) }
        let name = displayPath(url)
        // The id verbs take it first; `comment add` takes its text after the path.
        let args = takesPath.contains(id) ? Array(inv.positional.dropFirst()) : inv.positional
        let author = reviewAuthor(inv, req), today = Review.isoDay()
        reviewText(url) { [self] text in
            guard let text else { return done(.fail("can't read \(name)")) }
            let parsed = Review.parse(text)
            @MainActor func edit(_ make: () throws -> Review.Result, extra: [String: Any] = [:]) {
                do {
                    let r = try make()
                    self.reviewWrite(url, old: text, new: r.text, plain: false) { err in
                        if let err { return done(.fail(err)) }
                        done(.ok(r.summary + (self.isOpenInEditor(url) != nil ? " The user sees it in the editor; it autosaves." : ""), ["file": name, "id": r.id].merging(extra) { $1 }))
                    }
                } catch { done(.fail("\(error)")) }
            }
            switch id {
            case .commentAdd:
                guard let at = inv.flags["at"], !at.isEmpty, !args.isEmpty else { return done(.fail("usage: \(id.action.usage)")) }
                edit { try Review.addComment(to: text, at: at, author: author, date: today, body: args.joined(separator: " ")) }
            case .commentList:
                let list = parsed.threads.filter { inv.has("closed") ? $0.closed : !$0.closed }.filter { t in
                    !inv.has("unsent") || (t.comments.contains { $0.mentionsClaude } && !t.comments.contains { $0.author == "claude" })
                }
                done(.ok(list.isEmpty ? "\(name) has no \(inv.has("closed") ? "closed " : "")comment threads." : "\(name)\n" + list.flatMap(Self.threadLines).joined(separator: "\n"),
                         list.map(Self.threadJSON)))
            case .commentReply:
                guard let tid = args.first, args.count > 1 else { return done(.fail("usage: \(id.action.usage)")) }
                edit { try Review.reply(in: text, to: tid, author: author, date: today, body: args.dropFirst().joined(separator: " "), suggest: inv.has("suggest")) }
            case .commentClose:
                guard let tid = args.first else { return done(.fail("usage: \(id.action.usage)")) }
                edit { try Review.close(in: text, id: tid, author: author, date: today) }
            case .commentReopen:
                guard let tid = args.first else { return done(.fail("usage: \(id.action.usage)")) }
                edit { try Review.reopen(in: text, id: tid) }
            case .commentDelete:
                guard let tid = args.first else { return done(.fail("usage: \(id.action.usage)")) }
                edit { try Review.delete(in: text, id: tid) }
            case .commentStatus:
                guard let tid = args.first?.trimmingCharacters(in: CharacterSet(charactersIn: "#")), let t = parsed.thread(tid) else { return done(.fail(args.first.map { "no thread #\($0) in \(name)" } ?? "usage: \(id.action.usage)")) }
                let people = Array(Set(t.comments.compactMap(\.author))).sorted().map { "@\($0)" }.joined(separator: ", ")
                let names = t.comments.contains { $0.mentionsClaude }, replied = t.comments.contains { $0.author == "claude" }
                done(.ok("#\(t.id): \(t.closed ? "closed" : "open"), \(t.comments.filter { !$0.closing }.count) comments by \(people); "
                         + (names ? (replied ? "names @claude, Claude has replied" : "names @claude, no reply from Claude yet") : "doesn't name @claude")
                         + "; \(t.anchor == nil ? "no highlighted text" : "on “\(Review.abbreviate(t.anchor!))”")",
                         Self.threadJSON(t).merging(["repliedByClaude": replied, "delivery": "not sent"] as [String: Any]) { $1 }))
            case .commentSend:
                done(.fail("sending a comment to a session arrives with @claude routing; until then, reply with `duo2 comment reply` or send the document with `duo2 send file`"))
            case .suggestionList:
                let lines = parsed.suggestions.map { s -> String in
                    let what: String
                    switch s.kind {
                    case .insertion: what = "insert “\(Review.abbreviate(s.new))”"
                    case .deletion: what = "delete “\(Review.abbreviate(s.old))”"
                    case .substitution: what = "“\(Review.abbreviate(s.old))” → “\(Review.abbreviate(s.new))”"
                    }
                    return "#\(s.id ?? "?") \(s.author.map { "@\($0)" } ?? "unsigned")\(s.date.map { ", \($0)" } ?? ""): \(what)" + (s.note.isEmpty ? "" : " (\(s.note))")
                }
                done(.ok(lines.isEmpty ? "\(name) has no suggestions." : "\(name)\n" + lines.joined(separator: "\n"),
                         parsed.suggestions.map { ["id": $0.id as Any, "kind": $0.kind.rawValue, "author": $0.author as Any, "date": $0.date as Any, "old": $0.old, "new": $0.new, "note": $0.note] as [String: Any] }))
            case .suggestionAccept, .suggestionReject:
                let accept = id == .suggestionAccept
                if inv.has("all") {
                    let person = inv.flags["person"].flatMap { $0.isEmpty ? nil : $0 }
                    let r = Review.resolveAll(in: text, accept: accept, author: person)
                    guard r.count > 0 else { return done(.fail("no suggestions to \(accept ? "accept" : "reject")")) }
                    edit({ Review.Result(text: r.text, id: "all", summary: "\(accept ? "Accepted" : "Rejected") \(r.count) suggestion\(r.count == 1 ? "" : "s").") }, extra: ["count": r.count])
                } else {
                    guard let sid = args.first else { return done(.fail("usage: \(id.action.usage)")) }
                    edit { try Review.resolve(in: text, id: sid, accept: accept) }
                }
            default: done(.fail("not a review verb"))
            }
        }
    }

    /// `duo2 doc review [on|off]`: the Suggest Edits switch of the document showing.
    func docReviewVerb(_ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let url = reviewFile(inv, req, path: nil), Self.markdownExtensions.contains(url.pathExtension.lowercased()) else {
            return done(.fail("no Markdown document is showing"))
        }
        reviewText(url) { [self] text in
            guard let text else { return done(.fail("can't read \(url.lastPathComponent)")) }
            let now = Review.suggestEdits(text)
            guard let word = inv[0] else {
                return done(.ok("Suggest Edits is \(now ? "on" : "off") for \(displayPath(url)).", ["file": displayPath(url), "on": now]))
            }
            if word == "next" || word == "previous" {
                guard let e = editorIfLoaded, isOpenInEditor(url) != nil else { return done(.fail("the document isn't showing in the editor")) }
                e.run("return duo.reviewStep(d)", ["d": word == "next" ? 1 : -1]) { v in
                    guard let r = v as? [String: Any], let n = r["index"] as? Int, let t = r["total"] as? Int else { return done(.ok("Nothing to review in \(self.displayPath(url)).")) }
                    done(.ok("Mark \(n) of \(t): \((r["kind"] as? String) ?? "") #\((r["id"] as? String) ?? "?")", r))
                }
                return
            }
            guard ["on", "off"].contains(word) else { return done(.fail("usage: \(ActionID.docReview.action.usage)")) }
            let on = word == "on"
            // A plain change, the user's switch: not highlighted as Claude's.
            reviewWrite(url, old: text, new: Review.settingSuggestEdits(text, on: on), plain: true) { err in
                if let err { return done(.fail(err)) }
                done(.ok("Suggest Edits is \(on ? "on" : "off") for \(self.displayPath(url))" + (on ? ": every change becomes a signed suggestion (`suggest-edits: true` in its frontmatter)." : "."), ["file": self.displayPath(url), "on": on]))
            }
        }
    }
}
