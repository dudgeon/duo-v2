import DuoControl
import Foundation

/// The review bar's actions (DL-237): the buttons and menus call these, as the verbs do, so a click and
/// `duo2 doc review` / `duo2 doc markup` do the same.
extension AppModel {
    /// Suggest Edits on or off for the document showing: the frontmatter line, written as the user's own change.
    public func toggleSuggestEdits() {
        guard showingMarkdownDocument else { return }
        let on = !(editorIfLoaded?.review.suggestEdits ?? false)
        docReviewVerb(Invocation([on ? "on" : "off"]), ControlRequest(token: "", command: "doc review", args: []), { _ in })
    }

    /// A change to the markup mode or Show Closed Comments of the Markdown document showing, kept while Duo runs.
    public func setMarkdownMarkup(mode: String? = nil, showClosed: Bool? = nil) {
        guard let e = editorIfLoaded, let url = e.url else { return }
        let key = url.resolvingSymlinksInPath().standardizedFileURL.path
        var m = markdownMarkup[key] ?? MarkdownMarkup()
        if let mode, MarkdownMarkup.modes.contains(mode) { m.mode = mode }
        if let showClosed { m.showClosed = showClosed }
        markdownMarkup[key] = m
        e.setReviewMarkup(mode: m.mode, showClosed: m.showClosed)
        reviewMenu = nil
    }

    /// The page shows a document: give it the markup Duo kept for it.
    func syncReviewMarkup(_ r: ReviewSummary) {
        guard let e = editorIfLoaded, let url = e.url else { return }
        let m = markdownMarkup[url.resolvingSymlinksInPath().standardizedFileURL.path] ?? MarkdownMarkup()
        if r.mode != m.mode || r.showClosed != m.showClosed { e.setReviewMarkup(mode: m.mode, showClosed: m.showClosed) }
        pushReviewState()
    }
}
