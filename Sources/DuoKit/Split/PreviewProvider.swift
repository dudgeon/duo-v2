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
    public var line: Int
    public var message: String
    public init(line: Int, message: String) { self.line = line; self.message = message }
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
}

@MainActor
public protocol PreviewProvider: AnyObject {
    var kind: PreviewKind { get }
    /// Whether this provider can preview `file` (its project-relative path or `file:` key) with this frontmatter.
    static func canPreview(file: String, frontmatter: [String: String]) -> Bool
    /// Draws `text`, the editor's buffer at revision `rev` (unsaved edits included). Never writes a file.
    func render(text: String, rev: Int)
    func reveal(anchor: String, reason: RevealReason)
    /// Where the provider's events go: split view's `PreviewPolicy`.
    var emit: ((PreviewEvent) -> Void)? { get set }
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

    public static func kind(forFile file: String, frontmatter: [String: String] = [:]) -> PreviewKind? {
        for e in extra where e.test(file, frontmatter) { return e.kind }
        switch (file as NSString).pathExtension.lowercased() {
        case "md", "markdown": return .markdown
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
        }
        return true
    }

    /// The caret moved to a source line: the anchor to reveal, once; nil if caret-follow is off, the
    /// line is in no anchor, or it is the one already revealed.
    public func anchorToReveal(forLine line: Int) -> String? {
        guard caretFollow, let a = map.first(where: { $0.contains(line: line) })?.anchor, a != revealing, a != current else { return nil }
        revealing = a
        return a
    }

    /// The source lines of `anchor`, for the editor's margin mark.
    public func lines(of anchor: String) -> ClosedRange<Int>? {
        map.first { $0.anchor == anchor }.map { $0.firstLine...max($0.firstLine, $0.lastLine) }
    }
}
