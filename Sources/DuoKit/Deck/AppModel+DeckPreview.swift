import DuoControl
import Foundation

// `duo2 deck`, `deck go`, `deck pick` (Duo Decks P3a): the Markdown deck in split view. Both sides move
// together: the preview scrolls to the slide and the source shows its first line.
extension AppModel {
    /// The split tab showing a deck, and its provider.
    var deckSplit: (tab: SplitTab, preview: DeckPreview)? {
        guard let t = showingSplit, t.kind == .deck, let p = DeckPreviewHub.current, p.path == t.source else { return nil }
        return (t, p)
    }

    func deckPreviewVerb(_ id: ActionID, _ inv: Invocation, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let (tab, p) = deckSplit else {
            return done(.fail("no deck is showing in split view (a Markdown deck, `type: deck`, opened with `duo2 split <file>`); a .pptx file uses `duo2 slide`"))
        }
        let viewer = p.viewer
        guard viewer.state == .ready || viewer.state == .loading else {
            return done(.fail("the deck can't be drawn yet: `duo2 deck check \(tab.source)` says why"))
        }
        func lines(_ a: ClosedRange<Int>) -> String { a.count > 1 ? "lines \(a.lowerBound)–\(a.upperBound)" : "line \(a.lowerBound)" }
        switch id {
        case .deckShowing:
            editor(.main).selection { [weak self] sel in
                guard let self else { return }
                let slot = sel.flatMap { p.anchor(forLine: $0.lines.lowerBound) }
                var text = "\(tab.source): slide \(viewer.slide) of \(viewer.count) in the preview."
                if let slot, let r = p.lines(of: slot) { text += " The caret is in \(slot) (\(lines(r)))." } else { text += " The caret is not in a slide." }
                if p.rendering.problems.contains(where: { $0.severity == .error }) {
                    text += " The deck has problems, so the preview shows the last good drawing: `duo2 deck check \(tab.source)`."
                }
                var json: [String: Any] = ["file": tab.source, "slide": viewer.slide, "count": viewer.count]
                if let slot { json["anchor"] = slot }
                if let slot, let r = p.lines(of: slot) { json["lines"] = [r.lowerBound, r.upperBound] }
                done(.ok(text, json))
            }
        case .deckGo:
            guard viewer.state == .ready else { return done(.fail("the deck is still being drawn")) }
            let arg = inv[0] ?? ""
            let n = arg == "next" ? viewer.slide + 1 : ["previous", "prev"].contains(arg) ? viewer.slide - 1 : Int(arg)
            guard let n else { return done(.fail("usage: \(id.action.usage)")) }
            let to = max(1, min(viewer.count, n))
            p.reveal(anchor: "slide \(to)", reason: .request)
            var text = "Slide \(to) of \(viewer.count)."
            var json: [String: Any] = ["slide": to, "count": viewer.count]
            if let r = p.lines(of: "slide \(to)") {
                editor(.main).run("return window.duo && duo.selectLines ? duo.selectLines(a, a) : false", ["a": r.lowerBound]) { _ in }
                text += " Source \(lines(r))."
                json["lines"] = [r.lowerBound, r.upperBound]
            }
            if to != n { text += " (The deck has \(viewer.count).)" }
            done(.ok(text, json))
        case .deckPick:
            guard viewer.state == .ready else { return done(.fail("the deck is still being drawn")) }
            func report() -> Reply {
                guard let anchor = p.pickedAnchor, let (s, slot) = DeckPreviewBuild.parse(anchor: anchor) else {
                    return .ok("The picker is on: the user clicks a shape; run `duo2 deck pick` again to read it.")
                }
                let r = p.lines(of: anchor) ?? p.lines(of: "slide \(s)")
                var text = "Picked \(viewer.pickedShape?.name ?? "a shape") on slide \(s)"
                var json: [String: Any] = ["slide": s]
                if let slot { text += ", the \(slot) slot"; json["slot"] = slot }
                if let r { text += " (source \(lines(r)) of \(tab.source))"; json["lines"] = [r.lowerBound, r.upperBound] }
                return .ok(text + ".", json)
            }
            if let sel = inv[0] {
                viewer.pick(selector: sel) { ok in
                    done(ok ? report() : .fail("no shape \(sel): use <slide>/<shape id> from `duo2 slide shapes`"))
                }
            } else if viewer.picked != nil {
                done(report())
            } else {
                viewer.startPicking()
                done(report())
            }
        default: done(.fail("not a deck verb"))
        }
    }
}
