import AppKit
import DuoControl
import DuoDeck
import Foundation
import SwiftUI

/// What one render of a deck's text gives (Duo Decks P3, `preview-provider`): the pptx bytes (nil
/// while the deck has errors), the anchor map, the checker's problems and the comments' anchors.
/// Pure and `Sendable`, so it is made off the main thread and DuoChecks can run it.
public struct DeckRendering: Sendable {
    public var bytes: Data?
    public var anchors: [AnchorRange] = []
    public var problems: [SourceProblem] = []
    public var comments: [CommentAnchor] = []
    /// Slide number (from 1), then a drawn shape's OOXML id, to the slot it is.
    public var shapes: [Int: [Int: String]] = [:]
    public var slideCount = 0

    /// The anchor of a picked shape: `slide 3/value`, or `slide 3` when the shape is no slot's.
    public func anchor(slide: Int, shapeID: Int) -> String {
        shapes[slide]?[shapeID].map { "slide \(slide)/\($0)" } ?? "slide \(slide)"
    }
}

public enum DeckPreviewBuild {
    /// Parses, checks and exports `text` (the editor's buffer; `file` says where the deck lives, for its
    /// pictures and template packs). Never writes anything. A deck with errors has no bytes: the viewer
    /// keeps showing the last good drawing while the source shows the problems.
    public static func build(text: String, file: URL, packDirs: [URL]? = nil) -> DeckRendering {
        var out = DeckRendering()
        let dirs = packDirs ?? Deck.packDirs(near: file.deletingLastPathComponent())
        let checked: Deck.Checked
        let slides: [Deck.Slide]
        do {
            checked = try Deck.check(source: text, deck: file, packDirs: dirs)
            slides = checked.slides
            out.problems = checked.problems.map { SourceProblem(line: $0.line, message: $0.message, severity: .error) }
                + checked.notices.map { SourceProblem(line: $0.line, message: $0.message, severity: .notice) }
        } catch {
            // No such pack, or it can't be read: the deck can't be drawn, and the first lines say why.
            let parsed = Deck.parse(text)
            slides = parsed.slides
            out.problems = [SourceProblem(line: 2, message: "\(error)", severity: .error)]
            out.anchors = anchors(slides)
            out.comments = comments(text, anchors: out.anchors)
            out.slideCount = slides.count
            return out
        }
        out.anchors = anchors(slides)
        out.slideCount = slides.count
        out.comments = comments(text, anchors: out.anchors)
        if checked.problems.isEmpty, let drawn = try? Deck.export(checked: checked, source: text, deck: file) {
            out.bytes = drawn.data
            out.shapes = drawn.shapes
        }
        return out
    }

    /// `slide N` for each slide's lines, `slide N/slot` for each slot's.
    public static func anchors(_ slides: [Deck.Slide]) -> [AnchorRange] {
        var out: [AnchorRange] = []
        for (n, s) in slides.enumerated() {
            out.append(AnchorRange(anchor: "slide \(n + 1)", firstLine: s.line, lastLine: max(s.line, s.lastLine)))
            for slot in s.slots where slot.name != "_default" && slot.name != "_image" {
                out.append(AnchorRange(anchor: "slide \(n + 1)/\(slot.name)", firstLine: slot.line, lastLine: max(slot.line, slot.lastLine)))
            }
        }
        return out
    }

    /// Each comment thread's id, on the narrowest slot or slide its lines fall in.
    public static func comments(_ text: String, anchors: [AnchorRange]) -> [CommentAnchor] {
        let parsed = Review.parse(text)
        if parsed.threads.isEmpty { return [] }
        let ns = text as NSString
        var out: [CommentAnchor] = []
        for t in parsed.threads {
            var line = 1
            var i = 0
            let end = min(t.range.location, ns.length)
            while i < end { if ns.character(at: i) == 10 { line += 1 }; i += 1 }
            let hit = anchors.filter { $0.contains(line: line) }.min { ($0.lastLine - $0.firstLine) < ($1.lastLine - $1.firstLine) }
            if let hit { out.append(CommentAnchor(anchor: hit.anchor, thread: t.id)) }
        }
        return out
    }

    /// `slide 3/value` → (3, "value"); `slide 3` → (3, nil).
    public static func parse(anchor: String) -> (slide: Int, slot: String?)? {
        guard anchor.hasPrefix("slide ") else { return nil }
        let rest = anchor.dropFirst(6)
        let parts = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let n = parts.first.flatMap({ Int($0) }) else { return nil }
        return (n, parts.count > 1 ? String(parts[1]) : nil)
    }

    /// Frontmatter `type: deck` in the first lines of `text`, without parsing the whole deck.
    public static func isDeck(text: String) -> Bool {
        guard text.hasPrefix("---") else { return false }
        for l in text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().prefix(40) {
            if l.hasPrefix("---") { return false }
            if l.replacingOccurrences(of: " ", with: "") == "type:deck" { return true }
        }
        return false
    }
}

/// The Duo Decks preview provider (`kind` `.deck`): today's DeckViewer, fed with the pptx the editor's
/// buffer exports to, in memory. It hosts the viewer's own 44 bar (no new controls), keeps the slide
/// and scroll across redraws, and answers split view with the deck's anchor map, problems and comments.
@MainActor
public final class DeckPreview: NSObject, PreviewProvider {
    public let kind = PreviewKind.deck
    public let viewer: DeckViewer
    public var emit: ((PreviewEvent) -> Void)?

    /// The deck being previewed, project-relative (the tab's key) and on disk. Set by whoever binds the
    /// provider to a split tab (`bind`); a render with no file has nowhere to find packs and does nothing.
    public private(set) var path: String?
    public private(set) var file: URL?
    /// The last rendering, and the revision it answered.
    public private(set) var rendering = DeckRendering()
    public private(set) var renderedRev = -1
    public private(set) var renders = 0
    private var gate = RevisionGate()
    private weak var model: AppModel?
    private var hosting: NSView?
    private var revealing: Int?

    public init(resources: URL? = nil) {
        viewer = DeckViewer(resources: resources)
        super.init()
        viewer.onSlideChange = { [weak self] n in self?.pageMovedTo(n) }
        viewer.onPicked = { [weak self] e in self?.picked(e) }
    }

    public nonisolated static func canPreview(file: String, frontmatter: [String: String]) -> Bool {
        ["md", "markdown"].contains((file as NSString).pathExtension.lowercased()) && frontmatter["type"] == "deck"
    }

    /// Ties the provider to the tab it previews and to the app (the bar's picker and Open With need the model).
    public func bind(path: String, file: URL, model: AppModel?) {
        self.path = path
        self.file = file
        if let model, self.model !== model {
            self.model = model
            viewer.onChange = { [weak model] in model?.pickerRevision += 1 }
            hosting = NSHostingView(rootView: DeckPreviewBody(viewer: viewer, path: path, file: file).environment(model))
        }
    }

    /// The provider's whole view: the viewer's 44 bar over the slides and the picker bar. Without an app
    /// (checks) it is the slides alone.
    public var view: NSView { hosting ?? viewer.webView }

    public func render(text: String, rev: Int) {
        guard gate.admit(rev), let file else { return }
        let name = file.lastPathComponent
        Task.detached(priority: .userInitiated) { [weak self] in
            let r = DeckPreviewBuild.build(text: text, file: file)
            await MainActor.run {
                guard let self, self.gate.newest == rev else { return }   // a newer render won meanwhile
                self.finish(r, rev: rev, name: name)
            }
        }
    }

    /// Takes a finished rendering (also how checks feed the provider without a web view round trip).
    func finish(_ r: DeckRendering, rev: Int, name: String) {
        rendering = r
        renderedRev = rev
        renders += 1
        if let bytes = r.bytes, bytes != viewer.shownBytes { viewer.show(bytes: bytes, name: name) }
        emit?(.anchorMap(rev: rev, r.anchors))
        emit?(.problems(rev: rev, r.problems))
        emit?(.comments(rev: rev, r.comments))
    }

    public func reveal(anchor: String, reason: RevealReason) {
        guard let (n, _) = DeckPreviewBuild.parse(anchor: anchor), viewer.state == .ready else { return }
        if viewer.slide == n { return }   // already there: no scroll
        revealing = n
        viewer.go(n)
    }

    /// The page's slide changed: the user's scroll or ‹ ›, or our own reveal arriving (never echoed as the user's).
    private func pageMovedTo(_ n: Int) {
        let origin: PreviewOrigin = revealing == n ? .reveal : .user
        if revealing == n { revealing = nil }
        emit?(.current(anchor: "slide \(n)", origin: origin))
    }

    /// A shape was picked: its slide and slot (the shape's placeholder, through the template), as an activation.
    private func picked(_ e: SendFormat.Element?) {
        guard let e, let s = Int(e.attributes["slide"] ?? ""), let id = Int(e.attributes["id"] ?? "") else { return }
        emit?(.activate(anchor: rendering.anchor(slide: s, shapeID: id), origin: .user))
    }

    /// The anchor the picked shape stands for, if one is picked.
    public var pickedAnchor: String? {
        guard let e = viewer.picked, let s = Int(e.attributes["slide"] ?? ""), let id = Int(e.attributes["id"] ?? "") else { return nil }
        return rendering.anchor(slide: s, shapeID: id)
    }

    /// The source lines of an anchor in the last rendering.
    public func lines(of anchor: String) -> ClosedRange<Int>? {
        rendering.anchors.first { $0.anchor == anchor }.map { $0.firstLine...max($0.firstLine, $0.lastLine) }
    }

    /// The narrowest anchor holding source line `line`.
    public func anchor(forLine line: Int) -> String? {
        rendering.anchors.filter { $0.contains(line: line) }.min { ($0.lastLine - $0.firstLine) < ($1.lastLine - $1.firstLine) }?.anchor
    }
}

/// The deck preview's body: the viewer's own bar, the slides, the picker bar (DL-125's A, B, C), as in the right pane.
struct DeckPreviewBody: View {
    @Environment(AppModel.self) private var model
    let viewer: DeckViewer
    let path: String
    let file: URL

    var body: some View {
        let _ = model.pickerRevision
        VStack(spacing: 0) {
            DeckBar(viewer: viewer, path: path, file: file)
            DeckWebHost(viewer: viewer)
            DeckPickerBar(viewer: viewer)
        }
    }
}
