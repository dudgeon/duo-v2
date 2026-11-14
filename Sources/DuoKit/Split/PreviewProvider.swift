import AppKit
import Foundation

/// The interface between split view and whatever previews a file (`preview-provider`, agreed with
/// Duo Decks). The provider owns the anchor map and the rendering; split view owns the policy
/// (caret-follow, the 250 ms render pause, loop suppression), the panes, the fold, persistence and
/// the verbs; the editor owns the caret, the visible lines, DL-77's reconcile and Add Comment.

/// Source lines that belong to one anchor: `slide 3`, `slide 3/value`, a Markdown heading or block,
/// an HTML element id.
public struct AnchorRange: Equatable, Sendable {
    public var anchor: String
    public var firstLine: Int
    public var lastLine: Int
    public init(anchor: String, firstLine: Int, lastLine: Int) { self.anchor = anchor; self.firstLine = firstLine; self.lastLine = lastLine }
    public func contains(line: Int) -> Bool { (firstLine...max(firstLine, lastLine)).contains(line) }
}

public struct SourceProblem: Equatable, Sendable {
    public enum Severity: String, Sendable { case error, notice }
    public var line: Int
    public var message: String
    /// An error, or a notice (a deck's empty slot).
    public var severity: Severity
    public init(line: Int, message: String, severity: Severity = .error) { self.line = line; self.message = message; self.severity = severity }
}

public struct CommentAnchor: Equatable, Sendable {
    public var anchor: String
    public var thread: String
    public init(anchor: String, thread: String) { self.anchor = anchor; self.thread = thread }
}

/// Why split view asks a preview to reveal an anchor.
public enum RevealReason: String, Sendable { case caret, scroll, request }

/// Who caused an event; a `.reveal` never echoes back as a `current` (loop suppression).
public enum PreviewOrigin: String, Sendable { case user, reveal, render }

/// What a provider emits. Every one carries the revision it answers.
public enum PreviewEvent: Equatable, Sendable {
    case anchorMap(rev: Int, [AnchorRange])
    case activate(anchor: String, origin: PreviewOrigin)
    case current(anchor: String, origin: PreviewOrigin)
    case problems(rev: Int, [SourceProblem])
    case comments(rev: Int, [CommentAnchor])
    /// R11: a pin on the preview asks to open its thread in the source's review margin (DL-237's popover when folded).
    case openThread(thread: String)
    /// R12: Add Comment on an anchor's lines, without taking focus from the preview.
    case addComment(anchor: String)
}

@MainActor
public protocol PreviewProvider: AnyObject {
    var kind: PreviewKind { get }
    /// The provider's whole view, with its own bar (a deck's 44 bar, the HTML viewer's picker): split
    /// view hosts it as the preview side and draws no bar of its own.
    var view: NSView { get }
    /// The split it now previews: its tab key and file, before the first `render` (a deck reads its
    /// folder's template and pictures from here). Optional; the default does nothing.
    func bind(path: String, file: URL, model: AppModel)
    /// Whether this provider can preview `file` (its project-relative path or `file:` key) with this frontmatter.
    static func canPreview(file: String, frontmatter: [String: String]) -> Bool
    /// Draws `text`, the editor's buffer at revision `rev` (unsaved edits included). Never writes a file.
    func render(text: String, rev: Int)
    func reveal(anchor: String, reason: RevealReason)
    /// Where the provider's events go: split view's `PreviewPolicy`.
    var emit: ((PreviewEvent) -> Void)? { get set }
}

public extension PreviewProvider {
    func bind(path: String, file: URL, model: AppModel) {}
}

/// A provider drops a render older than its newest.
public struct RevisionGate: Sendable {
    public private(set) var newest = -1
    public init() {}
    /// True if `rev` should be drawn (and records it); false if a newer one was already drawn.
    public mutating func admit(_ rev: Int) -> Bool {
        guard rev >= newest else { return false }
        newest = rev
        return true
    }
}

/// Which kind of preview a file gets. Duo Decks registers its deck test here when its provider ships.
public enum PreviewProviders {
    /// Extra tests (a deck): first match wins, before the built-in ones.
    nonisolated(unsafe) public static var extra: [(kind: PreviewKind, test: @Sendable (_ file: String, _ frontmatter: [String: String]) -> Bool)] = []
    /// How a registered kind's provider is made: once per window, when a split first shows it.
    nonisolated(unsafe) static var makers: [PreviewKind: @MainActor () -> PreviewProvider] = [:]

    /// A provider outside split view (Duo Decks' deck) registers its kind, its test and how to make it,
    /// once at app start. Split view then hosts `view`, pushes `render(text:rev:)` 250 ms after typing pauses
    /// and takes the provider's events through its policy.
    public static func register(_ kind: PreviewKind, test: @escaping @Sendable (_ file: String, _ frontmatter: [String: String]) -> Bool,
                                make: @escaping @MainActor () -> PreviewProvider) {
        extra.removeAll { $0.kind == kind }
        extra.insert((kind, test), at: 0)
        makers[kind] = make
    }

    public static func kind(forFile file: String, frontmatter: [String: String] = [:]) -> PreviewKind? {
        for e in extra where e.test(file, frontmatter) { return e.kind }
        switch (file as NSString).pathExtension.lowercased() {
        // Markdown has no preview: it renders live in the editor (Geoff, 2026-11-01); view/edit source is being explored.
        case "html", "htm": return .html
        default: return nil
        }
    }
}

/// Split view's policy over one provider: caret-follow on, scroll-follow off, render 250 ms after typing
/// pauses, and revisions on everything so a stale map is ignored and a reveal never echoes.
@MainActor
public final class PreviewPolicy {
    public static let renderPause: Duration = .milliseconds(250)
    public var caretFollow = true
    public var scrollFollow = false
    /// Where the preview's comment requests go: split view wires these to the editor's `openThread` and
    /// `addComment` (slice 2's EditorController API), which never take the keyboard.
    public var onRequest: ((PreviewEvent) -> Void)?

    /// The editor's current revision: every buffer change makes a new one.
    public private(set) var rev = 0
    public private(set) var map: [AnchorRange] = []
    public private(set) var problems: [SourceProblem] = []
    public private(set) var comments: [CommentAnchor] = []
    public private(set) var current: String?
    private var revealing: String?
    private var task: Task<Void, Never>?
    public private(set) var renders = 0

    public init() {}

    /// The buffer changed: a new revision, and a render once typing pauses.
    @discardableResult
    public func bufferChanged(render: @escaping @MainActor (Int) -> Void) -> Int {
        rev += 1
        let mine = rev
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.renderPause)
            guard !Task.isCancelled, let self, self.rev == mine else { return }
            self.renders += 1
            render(mine)
        }
        return mine
    }

    public func cancel() { task?.cancel() }

    /// Takes a provider event; false when it is stale or an echo and was ignored.
    @discardableResult
    public func accept(_ e: PreviewEvent) -> Bool {
        switch e {
        case .anchorMap(let r, let m): guard r == rev else { return false }; map = m
        case .problems(let r, let p): guard r == rev else { return false }; problems = p
        case .comments(let r, let c): guard r == rev else { return false }; comments = c
        case .current(let a, let origin):
            if origin == .reveal || a == revealing { revealing = nil; return false }   // our own reveal coming back
            current = a
        case .activate(let a, _): current = a
        case .openThread, .addComment: onRequest?(e)   // R11, R12: the editor's review margin, never taking focus from the preview
        }
        return true
    }

    /// The caret moved to a source line: the anchor to reveal, once; nil if caret-follow is off, the
    /// line is in no anchor, or it is the one already revealed.
    public func anchorToReveal(forLine line: Int) -> String? {
        guard caretFollow, let a = narrowest(containing: line)?.anchor, a != revealing, a != current else { return nil }
        revealing = a
        return a
    }

    /// The source lines of `anchor`, for the editor's margin mark.
    public func lines(of anchor: String) -> ClosedRange<Int>? {
        map.first { $0.anchor == anchor }.map { $0.firstLine...max($0.firstLine, $0.lastLine) }
    }

    /// The narrowest range holding `line`: `slide 3/value` over `slide 3`, whatever the map's order.
    public func narrowest(containing line: Int) -> AnchorRange? {
        map.filter { $0.contains(line: line) }.min { ($0.lastLine - $0.firstLine) < ($1.lastLine - $1.firstLine) }
    }
}
