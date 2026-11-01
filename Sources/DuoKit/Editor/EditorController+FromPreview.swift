import AppKit
import Foundation

/// What a preview beside the editor asks of it (`preview-provider`; Duo Decks R4, R11, R12). None of
/// these moves the caret or takes the keyboard: the preview keeps it (DL-284).
extension EditorController {
    /// R12: Add Comment (⌥⌘M) on source lines `lines` (1-based), composed in the review margin. With
    /// `quiet` (the default) the composer's field waits for a click instead of taking the keyboard.
    /// `done(false)`: no document, or the lines are blank (nothing to anchor on).
    public func addComment(lines: ClosedRange<Int>, quiet: Bool = true, done: (@MainActor (Bool) -> Void)? = nil) {
        guard url != nil else { done?(false); return }
        run("return duo.reviewAddCommentAt(a, b, q)", ["a": lines.lowerBound, "b": lines.upperBound, "q": quiet]) { v in
            done?((v as? Bool) == true)
        }
    }

    /// R11: opens a thread in the review margin, by its id or as the first anchored on `line`, and
    /// scrolls it into view. `done` gets the thread's id, or nil when there's none.
    public func openThread(id: String? = nil, line: Int? = nil, done: (@MainActor (String?) -> Void)? = nil) {
        guard url != nil, id != nil || line != nil else { done?(nil); return }
        run("return duo.reviewOpenThread(i, l)", ["i": id ?? NSNull(), "l": line ?? NSNull()]) { v in done?(v as? String) }
    }

    /// The selection's text and 1-based lines (R4: ⌘D from a source, or a slot's lines), nil when nothing is selected.
    public func selection(_ done: @escaping @MainActor ((text: String, lines: ClosedRange<Int>)?) -> Void) {
        run("return duo.selection()") { v in
            guard let d = v as? [String: Any], let t = d["text"] as? String,
                  let a = d["fromLine"] as? Int, let b = d["toLine"] as? Int else { return done(nil) }
            done((t, a...max(a, b)))
        }
    }
}
