import DuoControl
import DuoSearch
import Foundation

// `duo2 slide …` (ENH-12, DL-125): the deck on screen and its slide, moving between slides, a
// slide's shapes and notes from the file, and the picker. Shape ids are OOXML `p:cNvPr` ids: the
// viewer stamps the same ones on what it draws.
extension AppModel {
    func slideVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        let deck = visibleDeck
        switch id {
        case .slide:
            guard let d = deck, let url = d.url else { return done(.fail("no deck is showing (open a .pptx with `duo2 doc open`)")) }
            guard d.state == .ready else { return done(.fail(stateWords(d))) }
            let path = displayPath(url)
            var text = "\(path), slide \(d.slide) of \(d.count) on screen."
            if let s = (try? Pptx.outline(url, slide: d.slide))?.first { text += "\n" + Self.outlineText(s) }
            done(.ok(text, ["file": path, "slide": d.slide, "count": d.count]))
        case .slideGo:
            guard let d = deck else { return done(.fail("no deck is showing")) }
            guard d.state == .ready else { return done(.fail(stateWords(d))) }
            let arg = inv[0] ?? ""
            let n = arg == "next" ? d.slide + 1 : ["previous", "prev"].contains(arg) ? d.slide - 1 : Int(arg)
            guard let n else { return done(.fail("usage: \(id.action.usage)")) }
            let to = max(1, min(d.count, n))
            d.go(to)
            done(.ok("Slide \(to) of \(d.count)." + (to != n ? " (The deck has \(d.count).)" : ""), ["slide": to, "count": d.count]))
        case .slideShapes, .slideNotes:
            // [<file>] [<n>]: a file named, else the deck on screen; a slide named, else the one on
            // screen (shapes: every slide when the file was named without one).
            var args = inv.positional
            var file: URL?
            if let first = args.first, Int(first) == nil {
                guard let u = deckFile(first, req: req) else { return done(.fail("no deck '\(first)' here (a path from the project's folder, or absolute)")) }
                file = u; args.removeFirst()
            }
            let named = args.first.flatMap(Int.init)
            if !args.isEmpty && named == nil { return done(.fail("usage: \(id.action.usage)")) }
            guard let url = file ?? deck?.url else { return done(.fail("no deck is showing: name one (`duo2 \(id.rawValue) <file.pptx> [n]`)")) }
            let slide = named ?? (file == nil ? deck?.slide : nil)
            do {
                let slides = try Pptx.outline(url, slide: slide)
                if let slide, slides.isEmpty { return done(.fail("\(displayPath(url)) has no slide \(slide)")) }
                let path = displayPath(url)
                let json = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(slides))) ?? []
                if id == .slideNotes {
                    let text = slides.map { "Slide \($0.number): " + ($0.notes.isEmpty ? "(no notes)" : "\n" + $0.notes) }.joined(separator: "\n\n")
                    done(.ok("\(path)\n\(text)", json))
                } else {
                    done(.ok("\(path)\n" + slides.map(Self.outlineText).joined(separator: "\n\n"), json))
                }
            } catch { done(.fail("\(displayPath(url)): \(error)")) }
        case .slidePick:
            guard let d = deck, d.state == .ready else { return done(.fail(deck.map(stateWords) ?? "no deck is showing")) }
            if let sel = inv[0] {
                d.pick(selector: sel) { ok in
                    done(ok ? .ok("Picked \(sel) (slide/shape id). `duo2 slide element` describes it; the user sees it outlined.") : .fail("no shape \(sel): use <slide>/<shape id> from `duo2 slide shapes`"))
                }
            } else { d.startPicking(); done(.ok("The picker is on: the user clicks a shape.")) }
        case .slideElement:
            guard let d = deck, let url = d.url else { return done(.fail("no deck is showing")) }
            let finish: @MainActor (SendFormat.Shape?, CGRect?) -> Void = { [weak self] s, rect in
                guard let self, let s else { return done(.fail("no shape (pick one, or pass <slide>/<shape id>)")) }
                d.screenshot(rect: rect) { shot in
                    let j = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(s))) as? [String: Any] ?? [:]
                    done(.ok(SendFormat.shape(s, path: self.displayPath(url), screenshot: shot), j.merging(["screenshot": shot ?? NSNull()]) { $1 }))
                }
            }
            if let sel = inv[0] { d.describe(selector: sel) { e, rect in finish(e.flatMap(d.shape), rect) } } else { finish(d.pickedShape, nil) }
        default: done(.fail("not a slide verb"))
        }
    }

    /// The deck in the right pane, if one is showing.
    var visibleDeck: DeckViewer? {
        guard let path = rightTab, Self.isDeck(path) else { return nil }
        return deckViewerIfLoaded
    }

    func stateWords(_ d: DeckViewer) -> String {
        switch d.state {
        case .loading: "the deck is still being drawn"
        case .failed(let why): "Duo can’t draw \(d.url?.lastPathComponent ?? "the deck"): \(why)"
        case .ready: "ready"
        }
    }

    /// A deck named on the command line: from the caller's project, the one showing, or absolute.
    func deckFile(_ s: String, req: ControlRequest) -> URL? {
        let expanded = (s as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return FileManager.default.fileExists(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil }
        for p in [projectFor(cwd: req.cwd)?.name, currentProject?.name].compactMap({ $0 }) {
            if let rel = relativePath(s, project: p, cwd: req.cwd), let folder = liveFolders[p] { return folder.appending(path: rel) }
        }
        return nil
    }

    /// One slide as Claude reads it: each shape's id, name and type, indented by group, its text
    /// and box, then the notes.
    static func outlineText(_ s: Pptx.Slide) -> String {
        var lines = ["Slide \(s.number):"]
        for sh in s.shapes {
            let indent = String(repeating: "  ", count: sh.inGroups.count + 1)
            var line = "\(indent)\(sh.id)  \(sh.name) (\(sh.type))"
            if let b = sh.box { line += " \(b.w)×\(b.h) at (\(b.x), \(b.y))" }
            if let c = sh.chart { line += " \(c) chart" }
            lines.append(line)
            if let t = sh.text, !t.isEmpty {
                lines += t.split(separator: "\n", omittingEmptySubsequences: false).map { "\(indent)    \($0)" }
            }
            for series in sh.series ?? [] {
                lines.append("\(indent)    \(series.name.isEmpty ? "series" : series.name): " + series.values.map { String(format: "%g", $0) }.joined(separator: ", "))
            }
        }
        if !s.notes.isEmpty { lines.append("  notes: " + s.notes.replacingOccurrences(of: "\n", with: "\n         ")) }
        return lines.joined(separator: "\n")
    }
}
