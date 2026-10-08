import DuoControl
import DuoSearch
import Foundation

// `duo2 doc markup` and `duo2 doc comments` (DL-162): the Word viewer's markup menu, and the
// comments it drew. The Markup menu calls `setMarkup` too, so a click and a verb do the same.
extension AppModel {
    /// The Word document in the right pane, if one is showing.
    var visibleDocx: DocxViewer? {
        guard let path = rightTab, Self.isWordViewable(path) else { return nil }
        return docxViewerIfLoaded
    }

    /// One change to the viewer's markup (the menu's click, or the verb): a mode, the comment
    /// toggles, or a person (`.some(nil)` shows everyone again).
    func setMarkup(mode: String? = nil, comments: Bool? = nil, resolved: Bool? = nil, person: String?? = nil) {
        let v = docxViewer
        var m = v.markup
        if let mode { m.mode = mode }
        if let comments { m.comments = comments }
        if let resolved { m.resolved = resolved }
        if let person { m.person = person }
        v.markup = m
    }

    static func markupWords(_ m: DocxViewer.Markup) -> String {
        let mode = ["all": "All Markup", "simple": "Simple Markup", "none": "No Markup", "original": "Original"][m.mode] ?? m.mode
        return "\(mode), comments \(m.comments ? "shown" : "hidden"), resolved comments \(m.resolved ? "open" : "folded"), \(m.person.map { "only \($0)’s marks" } ?? "everyone’s marks")"
    }

    func docxVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let v = visibleDocx, let url = v.url else { return done(.fail("no Word document is showing (open a .docx with `duo2 doc open`)")) }
        guard v.state == .ready else {
            let why: String
            switch v.state {
            case .loading: why = "the document is still being drawn"
            case .failed(let w): why = "Duo can’t draw \(url.lastPathComponent): \(w)"
            case .ready: why = "ready"
            }
            return done(.fail(why))
        }
        let path = displayPath(url)
        switch id {
        case .docMarkup:
            func onOff(_ flag: String) -> Bool?? {
                guard let value = inv.flags[flag] else { return .none }
                switch value.lowercased() {
                case "on", "yes", "true", "": return .some(true)
                case "off", "no", "false": return .some(false)
                default: return .some(nil)
                }
            }
            var mode: String?
            if let a = inv[0] {
                guard DocxViewer.Markup.modes.contains(a.lowercased()) else { return done(.fail("usage: \(id.action.usage)")) }
                mode = a.lowercased()
            }
            var comments: Bool?, resolved: Bool?
            if let c = onOff("comments") { guard let c else { return done(.fail("--comments takes on or off")) }; comments = c }
            if let r = onOff("show-resolved") { guard let r else { return done(.fail("--show-resolved takes on or off")) }; resolved = r }
            var person: String??
            if let p = inv.flags["person"] {
                if ["everyone", "all", ""].contains(p.lowercased()) { person = .some(nil) }
                else if let hit = v.people.first(where: { $0.name.localizedCaseInsensitiveContains(p) }) { person = .some(hit.name) }
                else { return done(.fail("no one called “\(p)” in \(path): " + v.people.map(\.name).joined(separator: ", "))) }
            }
            if mode != nil || comments != nil || resolved != nil || person != nil { setMarkup(mode: mode, comments: comments, resolved: resolved, person: person) }
            let m = v.markup
            let people = v.people.map { "\($0.name) (\($0.count))" }.joined(separator: ", ")
            done(.ok("\(path): \(Self.markupWords(m)).\n\(v.changeCount) tracked changes, \(v.comments.count) comments." + (people.isEmpty ? "" : " People: \(people)."),
                     ["file": path, "mode": m.mode, "comments": m.comments, "showResolved": m.resolved, "person": m.person as Any,
                      "changes": v.changeCount, "commentCount": v.comments.count,
                      "people": v.people.map { ["name": $0.name, "count": $0.count, "colour": $0.colour] as [String: Any] }] as [String: Any]))
        case .docComments:
            let list = v.comments.filter { !inv.has("resolved") || $0.resolved }
            func day(_ iso: String) -> String { String(iso.prefix(10)) }
            var lines: [String] = []
            for c in list {
                lines.append("\(c.reply ? "  ↳ " : "")\(c.id) [\(c.resolved ? "resolved" : "open")] \(c.author), \(day(c.date)), ¶\(c.paragraph): \(c.text)")
            }
            done(.ok(list.isEmpty ? "\(path) has no \(inv.has("resolved") ? "resolved " : "")comments." : "\(path)\n" + lines.joined(separator: "\n"),
                     list.map { ["id": $0.id, "author": $0.author, "date": $0.date, "text": $0.text, "resolved": $0.resolved, "reply": $0.reply, "paragraph": $0.paragraph] as [String: Any] }))
        default: done(.fail("not a Word verb"))
        }
    }
}
