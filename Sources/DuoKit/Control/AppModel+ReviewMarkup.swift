import DuoControl
import Foundation

/// How a Markdown document's marks are drawn (the Word viewer's Markup menu, DL-162 W4, for Markdown): kept per document while Duo runs.
public struct MarkdownMarkup: Equatable, Sendable {
    public static let modes = ["all", "simple", "none", "original"]
    public var mode = "all"
    public var showClosed = false
    public init() {}
}

extension AppModel {
    /// A Markdown document is in the editor (not a Word one).
    var showingMarkdownDocument: Bool {
        guard let u = editorIfLoaded?.url else { return false }
        return Self.markdownExtensions.contains(u.pathExtension.lowercased())
    }

    /// `duo2 doc markup` and `duo2 doc comments` on a Markdown document (DL-237): the mode and the closed threads' visibility, and the threads.
    func markdownMarkupVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let url = editorIfLoaded?.url else { return done(.fail("no document is showing")) }
        if id == .docComments { return reviewVerb(.commentList, inv, req, done) }
        let key = url.resolvingSymlinksInPath().standardizedFileURL.path
        var m = markdownMarkup[key] ?? MarkdownMarkup()
        if let a = inv[0] {
            guard MarkdownMarkup.modes.contains(a.lowercased()) else { return done(.fail("usage: \(id.action.usage)")) }
            m.mode = a.lowercased()
        }
        if let v = inv.flags["show-closed"] ?? inv.flags["show-resolved"] {
            switch v.lowercased() {
            case "on", "yes", "true", "": m.showClosed = true
            case "off", "no", "false": m.showClosed = false
            default: return done(.fail("--show-closed takes on or off"))
            }
        }
        markdownMarkup[key] = m
        let shown = m
        reviewText(url) { text in
            let p = Review.parse(text ?? "")
            let words = ["all": "All Markup", "simple": "Simple Markup", "none": "No Markup", "original": "Original"][shown.mode] ?? shown.mode
            let path = self.displayPath(url)
            let message = "\(path): \(words), closed comments \(shown.showClosed ? "shown" : "hidden").\n\(p.suggestions.count) suggestions, \(p.open.count) open comment threads, \(p.closed.count) closed."
            let data: [String: Any] = ["file": path, "mode": shown.mode, "showClosed": shown.showClosed, "suggestions": p.suggestions.count, "threads": p.open.count, "closed": p.closed.count]
            done(.ok(message, data))
        }
    }
}
