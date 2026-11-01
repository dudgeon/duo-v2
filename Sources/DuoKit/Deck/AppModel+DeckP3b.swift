import DuoControl
import DuoDeck
import Foundation

// `duo2 deck problems | comments | comment | export again | export show` and `deck template pick | picked`
// (Duo Decks P3b). They work on the deck showing in split view, or on `--deck <file>`.
extension AppModel {
    /// The deck a P3b verb works on: `--deck`, else the one in split view.
    func deckTarget(_ inv: Invocation, _ req: ControlRequest) -> (url: URL, preview: DeckPreview?)? {
        if let s = inv.flags["deck"] {
            guard let u = deckFile(s, req: req) else { return nil }
            let p = deckSplit?.preview
            return (u, p?.file?.standardizedFileURL == u.standardizedFileURL ? p : nil)
        }
        if let (_, p) = deckSplit, let f = p.file { return (f, p) }
        return nil
    }

    func deckP3bVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let (url, preview) = deckTarget(inv, req) else {
            return done(.fail(inv.flags["deck"].map { "no deck '\($0)' here (a path from the project's folder, or absolute)" }
                              ?? "no deck is showing in split view: open one with `duo2 split <deck>`, or name it with --deck <file>"))
        }
        let name = displayPath(url)
        switch id {
        case .deckProblems:
            reviewText(url) { [self] text in
                guard let text else { return done(.fail("can't read \(name)")) }
                let r = preview?.rendering.problems != nil && preview?.lastText == text ? preview!.rendering : DeckPreviewBuild.build(text: text, file: url)
                let errors = r.problems.filter { $0.severity == .error }, notices = r.problems.filter { $0.severity == .notice }
                var lines = ["\(name): \(errors.count) problem\(errors.count == 1 ? "" : "s"), \(notices.count) notice\(notices.count == 1 ? "" : "s")"]
                for p in errors + notices { lines.append("\(name):\(p.line): \(p.severity == .error ? "error" : "notice"): \(p.message)") }
                let json: [[String: Any]] = (errors + notices).map { ["line": $0.line, "severity": $0.severity.rawValue, "message": $0.message] }
                done(.ok(lines.joined(separator: "\n"), json))
            }
        case .deckComments:
            reviewText(url) { text in
                guard let text else { return done(.fail("can't read \(name)")) }
                let l = DeckCards.commentLines(text: text)
                done(.ok(l.isEmpty ? "\(name) has no comment threads." : "\(name)\n" + l.joined(separator: "\n")))
            }
        case .deckComment:
            guard inv.positional.count >= 2 else { return done(.fail("usage: \(id.action.usage)")) }
            let anchor = inv.positional[0].hasPrefix("slide ") ? inv.positional[0] : "slide \(inv.positional[0])"
            let body = inv.positional.dropFirst().joined(separator: " ")
            let author = reviewAuthor(inv, req), today = Review.isoDay()
            reviewText(url) { [self] text in
                guard let text else { return done(.fail("can't read \(name)")) }
                do {
                    let r = try DeckCards.addComment(source: text, anchor: anchor, author: author, date: today, body: body)
                    reviewWrite(url, old: text, new: r.text, plain: false, thread: true) { err in
                        if let err { return done(.fail(err)) }
                        done(.ok("Commented on \(anchor) as #\(r.id) (line \(r.line) of \(name)).", ["file": name, "id": r.id, "line": r.line]))
                    }
                } catch { done(.fail("\(error)")) }
            }
        case .deckExportAgain:
            let slides = Deck.parse((try? String(contentsOf: url, encoding: .utf8)) ?? "").slides.count
            if let preview { preview.exportDeck { n in done(n.file != nil ? .ok(n.text) : .fail(n.text + (n.sub.map { "\n\($0)" } ?? ""))) } }
            else {
                Task.detached {
                    let n = DeckPreview.exportNote(file: url, slides: slides)
                    await MainActor.run { done(n.file != nil ? .ok(n.text) : .fail(n.text + (n.sub.map { "\n\($0)" } ?? ""))) }
                }
            }
        case .deckExportShow:
            let dir = url.deletingLastPathComponent()
            let base = url.deletingPathExtension().lastPathComponent
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { Deck.isExport($0, of: base) }.sorted()
            guard let newest = files.last else { return done(.fail("\(name) has not been exported: `duo2 deck export \(name)`")) }
            FileActions.reveal(dir.appending(path: newest))
            done(.ok("Showing \(displayPath(dir.appending(path: newest))) in Finder."))
        default: done(.fail("not a deck verb"))
        }
    }

    /// `duo2 deck template pick [<slides>]` and `picked`: the slide tick boxes of the plain .pptx showing.
    func deckTemplateVerb(_ id: ActionID, _ inv: Invocation, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let v = deckViewerIfLoaded, let file = v.url, file.pathExtension.lowercased() == "pptx", v.webView.window != nil || v.state == .ready else {
            return done(.fail("no PowerPoint file is showing in the viewer: open a .pptx (a Markdown deck makes its own templates with `duo2 deck template build`)"))
        }
        switch id {
        case .deckTemplatePick:
            guard v.state == .ready else { return done(.fail("the deck is still being drawn")) }
            v.setSlidePicking(true)
            if let list = inv[0] {
                let n = list.split(separator: ",").compactMap { Int($0) }
                v.setPickedSlides(n)
            }
            done(.ok("The slide picker is on for \(file.lastPathComponent): the user ticks slides; run `duo2 deck template picked` to read them."))
        default:
            let picked = v.pickedSlides
            let path = displayPath(file)
            let line = "duo2 deck template inventory \"\(path)\" --slides \(picked.map(String.init).joined(separator: ","))"
            done(.ok(picked.isEmpty ? "\(file.lastPathComponent): \(v.slidePicking ? "no slides ticked yet" : "the slide picker is off")."
                     : "\(file.lastPathComponent): slides \(picked.map(String.init).joined(separator: ", ")) picked.\n\(line)",
                     ["file": path, "slides": picked]))
        }
    }
}
