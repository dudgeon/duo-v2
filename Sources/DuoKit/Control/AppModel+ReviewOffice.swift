import DuoControl
import DuoSearch
import Foundation

// `duo2 comment …` on a Word or PowerPoint file (DL-331): the comment, its replies and its resolved state are written
// into the file's comment parts (`OfficeComments`), and @claude routing (`comment send`, `comment status`) reads the threads
// back as `Review.Thread`s, so the same turn, delivery and reply tracking as a Markdown comment apply. No viewer controls yet:
// the composer is a surface to design (Q-490).
extension AppModel {
    static func isOffice(_ url: URL) -> Bool { OfficeComments.kind(url) != nil }

    /// Where the originals are kept before Duo writes a comment into a file.
    static var officeBackups: URL { SupportFolder.duo.appendingPathComponent("Office backups", isDirectory: true) }

    /// A file's threads as the review model sees them: authors in signature form (`Dana Writer` is `dana-writer`, Claude is
    /// `claude`), the day of each date, a closed thread's closing line left out (resolved is closed).
    public static func officeReviewThreads(_ url: URL) throws -> [Review.Thread] {
        try OfficeComments.threads(url).map { t in
            var comments = t.items.map {
                Review.Comment(author: Review.signatureName($0.author), date: $0.date.count >= 10 ? String($0.date.prefix(10)) : nil, id: $0.id, text: $0.text)
            }
            if t.resolved { comments.append(.closingMark) }
            return Review.Thread(id: t.id, anchor: t.anchor, comments: comments)
        }
    }

    /// The turn for an Office thread: where it is, the quoted thread, and how to answer with `--file`.
    func officeTurn(url: URL, thread id: String) -> String? {
        guard let office = (try? OfficeComments.threads(url))?.first(where: { $0.id == id }),
              let t = (try? Self.officeReviewThreads(url))?.first(where: { $0.id == id }) else { return nil }
        return Self.officeTurnText(name: displayPath(url), place: office.place, thread: t)
    }

    /// `line 0` becomes where the thread is (a Word or PowerPoint file has no lines), and the reply line names the file.
    public static func officeTurnText(name: String, place: String, thread t: Review.Thread) -> String {
        var out = Review.turn(path: name, line: 0, thread: t)
        out = out.replacingOccurrences(of: "\(name), line 0 (thread", with: "\(name), \(place) (thread")
        out = out.replacingOccurrences(of: "Reply in the thread: duo2 comment reply \(t.id) \"<text>\"   (add --suggest to propose an edit).",
                                       with: "Reply in the thread: duo2 comment reply \(t.id) \"<text>\" --file \"\(name)\".")
        return out
    }

    func officeReviewVerb(_ id: ActionID, _ inv: Invocation, author: String, url: URL, args: [String], _ done: @escaping @MainActor (Reply) -> Void) {
        let name = displayPath(url)
        do {
            switch id {
            case .commentList:
                let all = try OfficeComments.threads(url)
                let review = try Self.officeReviewThreads(url)
                let list = all.filter { inv.has("closed") ? $0.resolved : !$0.resolved }.filter { t in
                    !inv.has("unsent") || (t.items.contains { $0.text.range(of: "@claude", options: .caseInsensitive) != nil } && !t.items.contains { Review.signatureName($0.author) == "claude" })
                }
                let lines = list.flatMap { t -> [String] in
                    let head = t.items[0]
                    var out = ["#\(t.id) [\(t.resolved ? "closed" : "open")] @\(Review.signatureName(head.author)), \(head.date.prefix(10)) on \(t.place)"
                               + (t.anchor.map { " “\(Review.abbreviate($0))”" } ?? "") + ": " + head.text + (t.legacy ? "  (legacy PowerPoint comment: read only)" : "")]
                    for r in t.items.dropFirst() { out.append("  ↳ #\(r.id) @\(Review.signatureName(r.author)), \(r.date.prefix(10)): \(r.text)") }
                    return out
                }
                done(.ok(list.isEmpty ? "\(name) has no \(inv.has("closed") ? "closed " : "")comment threads." : "\(name)\n" + lines.joined(separator: "\n"),
                         list.map { t -> [String: Any] in
                             ["id": t.id, "closed": t.resolved, "anchor": t.anchor as Any, "place": t.legacy ? t.place + " (legacy)" : t.place,
                              "namesClaude": review.first { $0.id == t.id }?.comments.contains { $0.mentionsClaude } ?? false,
                              "comments": t.items.map { ["id": $0.id, "author": $0.author, "date": $0.date, "text": $0.text] }]
                         }))
            case .commentAdd:
                guard let at = inv.flags["at"], !at.isEmpty, !args.isEmpty else { return done(.fail("usage: \(id.action.usage)")) }
                let w = try OfficeComments.add(url, at: at, author: author, text: args.joined(separator: " "), backups: Self.officeBackups)
                done(.ok(w.summary, ["file": name, "id": w.id]))
            case .commentReply:
                guard let tid = args.first, args.count > 1 else { return done(.fail("usage: \(id.action.usage)")) }
                if inv.has("suggest") { return done(.fail("--suggest proposes an edit in a Markdown document; a Word or PowerPoint file has no suggestions Duo writes")) }
                let w = try OfficeComments.reply(url, to: tid, author: author, text: args.dropFirst().joined(separator: " "), backups: Self.officeBackups)
                done(.ok(w.summary, ["file": name, "id": w.id]))
            case .commentClose, .commentReopen:
                guard let tid = args.first else { return done(.fail("usage: \(id.action.usage)")) }
                let w = try OfficeComments.resolve(url, thread: tid, resolved: id == .commentClose, backups: Self.officeBackups)
                done(.ok(w.summary, ["file": name, "id": w.id]))
            case .commentDelete:
                done(.fail("deleting a comment from a Word or PowerPoint file isn't built; close it with `duo2 comment close`"))
            case .commentStatus:
                guard let raw = args.first?.trimmingCharacters(in: CharacterSet(charactersIn: "#")), let t = try Self.officeReviewThreads(url).first(where: { $0.id == raw }) else {
                    return done(.fail(args.first.map { "no thread #\($0) in \(name)" } ?? "usage: \(id.action.usage)"))
                }
                let people = Array(Set(t.comments.compactMap(\.author))).sorted().map { "@\($0)" }.joined(separator: ", ")
                let names = t.comments.contains { $0.mentionsClaude }, replied = t.comments.contains { $0.author == "claude" }
                let d = reviewDeliveries[Self.reviewKey(url, t.id)]
                let delivery = d.map { "\($0.state.rawValue.replacingOccurrences(of: "-", with: " ")) (\($0.sessionName), \(Self.clock($0.at)))\($0.why.map { ": " + $0 } ?? "")" } ?? (names ? "not sent" : "n/a")
                done(.ok("#\(t.id): \(t.closed ? "closed" : "open"), \(t.comments.filter { !$0.closing }.count) comments by \(people); delivery: \(delivery); "
                         + (names ? (replied ? "names @claude, Claude has replied" : "names @claude, no reply from Claude yet") : "doesn't name @claude"),
                         ["id": t.id, "closed": t.closed, "repliedByClaude": replied, "delivery": d?.state.rawValue ?? "not sent"]))
            case .commentSend:
                let threads = try Self.officeReviewThreads(url)
                let ids: [String]
                if inv.has("all") {
                    ids = threads.filter { t in !t.closed && t.comments.contains(where: \.mentionsClaude) && !t.comments.contains { $0.author == "claude" }
                        && self.reviewDeliveries[Self.reviewKey(url, t.id)] == nil }.map(\.id)
                    guard !ids.isEmpty else { return done(.ok("Nothing to send: every @claude comment in \(name) went, or has an answer.")) }
                } else if let one = args.first { ids = [one.trimmingCharacters(in: CharacterSet(charactersIn: "#"))] }
                else { return done(.fail("usage: \(id.action.usage)")) }
                var chosen: Fixture.Session?
                if let to = inv.flags["to"] {
                    guard let s = findSession(to, in: nil) else { return done(.fail("no session '\(to)' (see `duo2 sessions`)")) }
                    chosen = s
                }
                if inv.has("new") { return done(.fail("--new isn't built yet: start a session with `duo2 session new`, then send with --to it (Q-284)")) }
                var lines: [String] = []
                var left = ids.count
                for tid in ids {
                    sendReviewComment(url, thread: tid, to: chosen) { r in
                        lines.append("#\(tid): \(r.text)"); left -= 1
                        if left == 0 { done(.ok(lines.joined(separator: "\n"), ["file": name, "threads": ids])) }
                    }
                }
            default: done(.fail("\(url.lastPathComponent) is a Word or PowerPoint file: that verb works on a Markdown document"))
            }
        } catch {
            done(.fail("\(error)"))
        }
    }
}
