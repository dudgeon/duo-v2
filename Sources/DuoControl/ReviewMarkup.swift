import Foundation

// Review in Markdown (DL-236, DL-237): tracked changes and comments as signed CriticMarkup, one
// model for everyone who reads or writes them. It's text in, text out and knows no file format or
// view: the editor draws what `parse` finds, the `duo2 comment` and `duo2 suggestion` verbs call
// the operations, and the Word converter writes the same marks with `Review.sign` and the
// builders. Offsets are UTF-16 (NSRange), what the editor and NSString use.
//
//   {++added++}{>>@sam 2026-10-28 #s1: note<<}        a suggestion: the signature note is the first comment
//   {--cut--}  {~~old~>new~~}
//   {==anchor==}{>>@sam 2026-10-28 #c1: text<<}       a thread: highlight, then its comments in order
//   {>>@claude 2026-10-28 #c1.1: reply<<}             a reply: id is the thread's, then .n
//   {>>@geoff 2026-10-28 #c1.2 closed<<}              a closing line (Q-262): the thread is closed
//
// Frontmatter `suggest-edits: true` is the document's Suggest Edits switch (DL-237).

public enum Review {
    public enum Kind: String, Sendable { case insertion, deletion, substitution }

    /// One `{>>…<<}`: a comment, a reply or a closing line.
    public struct Comment: Equatable, Sendable {
        public var author: String?
        public var date: String?
        public var id: String?
        public var text: String
        /// A closing line: `#c1.2 closed`.
        public var closing: Bool
        public var range: NSRange
        public var signed: Bool { author != nil }
        /// A comment written by `Review.defaultAuthorIsClaude`'s author, or one that names @claude.
        public var mentionsClaude: Bool { text.range(of: "@claude", options: .caseInsensitive) != nil }
    }

    /// A highlight with the comments after it (or comments alone, `anchor` nil).
    public struct Thread: Equatable, Sendable {
        public var id: String
        public var anchor: String?
        public var anchorRange: NSRange?
        public var comments: [Comment]
        /// The whole group, highlight and comments.
        public var range: NSRange
        /// The last line is a closing line.
        public var closed: Bool { comments.last?.closing ?? false }
        public var root: Comment? { comments.first { !$0.closing } }
        public var replies: [Comment] { comments.filter { !$0.closing }.dropFirst().map { $0 } }
        public var closingLine: Comment? { closed ? comments.last : nil }
    }

    /// An insertion, a deletion or a substitution, with the comments after it.
    public struct Suggestion: Equatable, Sendable {
        public var kind: Kind
        public var old: String
        public var new: String
        public var id: String?
        public var author: String?
        public var date: String?
        /// The first comment's text.
        public var note: String
        public var comments: [Comment]
        public var range: NSRange
    }

    public struct Parsed: Equatable, Sendable {
        public var threads: [Thread] = []
        public var suggestions: [Suggestion] = []
        public var isEmpty: Bool { threads.isEmpty && suggestions.isEmpty }
        public var open: [Thread] { threads.filter { !$0.closed } }
        public var closed: [Thread] { threads.filter(\.closed) }
        public func thread(_ id: String) -> Thread? { threads.first { $0.id == id } }
        public func suggestion(_ id: String) -> Suggestion? { suggestions.first { $0.id == id } }
    }

    public struct Failure: Error, CustomStringConvertible, Sendable {
        public var description: String
        public init(_ d: String) { description = d }
    }

    // MARK: Parse

    private struct Token { var open: String; var close: String; var kind: String }
    private static let tokens: [Token] = [
        .init(open: "{++", close: "++}", kind: "ins"), .init(open: "{--", close: "--}", kind: "del"),
        .init(open: "{~~", close: "~~}", kind: "sub"), .init(open: "{==", close: "==}", kind: "hl"),
        .init(open: "{>>", close: "<<}", kind: "cm"),
    ]

    private struct Raw { var kind: String; var range: NSRange; var inner: NSRange }

    /// Ranges where marks aren't read: fenced code blocks and inline code.
    static func codeRanges(_ ns: NSString) -> [NSRange] {
        var out: [NSRange] = []
        var pos = 0, fenceStart: Int?
        while pos < ns.length {
            let line = ns.lineRange(for: NSRange(location: pos, length: 0))
            let s = ns.substring(with: line).trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("```") || s.hasPrefix("~~~") {
                if let f = fenceStart { out.append(NSRange(location: f, length: NSMaxRange(line) - f)); fenceStart = nil } else { fenceStart = line.location }
            } else if fenceStart == nil, s.contains("`") {
                var i = line.location
                let end = NSMaxRange(line)
                while i < end {
                    if ns.character(at: i) == 0x60 {
                        let r = ns.range(of: "`", range: NSRange(location: i + 1, length: end - i - 1))
                        if r.location != NSNotFound { out.append(NSRange(location: i, length: NSMaxRange(r) - i)); i = NSMaxRange(r); continue }
                    }
                    i += 1
                }
            }
            pos = NSMaxRange(line)
        }
        if let f = fenceStart { out.append(NSRange(location: f, length: ns.length - f)) }
        return out
    }

    private static func scan(_ ns: NSString) -> [Raw] {
        let code = codeRanges(ns)
        var out: [Raw] = []
        var i = 0
        outer: while i + 3 <= ns.length {
            if ns.character(at: i) == 0x7B /* { */, !code.contains(where: { NSLocationInRange(i, $0) }) {
                for t in tokens where ns.substring(with: NSRange(location: i, length: 3)) == t.open {
                    let from = i + 3
                    let r = ns.range(of: t.close, range: NSRange(location: from, length: ns.length - from))
                    if r.location != NSNotFound {
                        out.append(Raw(kind: t.kind, range: NSRange(location: i, length: NSMaxRange(r) - i), inner: NSRange(location: from, length: r.location - from)))
                        i = NSMaxRange(r)
                        continue outer
                    }
                }
            }
            i += 1
        }
        return out
    }

    /// The signature at the front of a comment: `@name 2026-10-28 #id` then `: text`, or ` closed`.
    public static func parseComment(_ body: String, range: NSRange = NSRange(location: 0, length: 0)) -> Comment {
        let s = body.trimmingCharacters(in: .whitespaces)
        let sig = try? NSRegularExpression(pattern: #"^@([^\s:]+)(?:\s+(\d{4}-\d{2}-\d{2}))?(?:\s+#([\w.]+))?"#)
        let ns = s as NSString
        guard let m = sig?.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else {
            return Comment(author: nil, date: nil, id: nil, text: s, closing: false, range: range)
        }
        func grp(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        var rest = ns.substring(from: m.range.length).trimmingCharacters(in: .whitespaces)
        var closing = false
        if rest.hasPrefix(":") { rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) } else if rest == "closed" { closing = true; rest = "" }
        return Comment(author: grp(1), date: grp(2), id: grp(3), text: rest, closing: closing, range: range)
    }

    public static func parse(_ text: String) -> Parsed {
        let ns = text as NSString
        let raws = scan(ns)
        var out = Parsed()
        var i = 0
        func comments(after idx: Int, endOfPrev: Int) -> (list: [Comment], next: Int, end: Int) {
            var list: [Comment] = [], j = idx, end = endOfPrev
            while j < raws.count, raws[j].kind == "cm", raws[j].range.location == end {
                list.append(parseComment(ns.substring(with: raws[j].inner), range: raws[j].range))
                end = NSMaxRange(raws[j].range); j += 1
            }
            return (list, j, end)
        }
        var unsignedThreads = 0
        while i < raws.count {
            let r = raws[i]
            switch r.kind {
            case "ins", "del", "sub":
                let inner = ns.substring(with: r.inner)
                var old = "", new = ""
                let kind: Kind
                switch r.kind {
                case "ins": kind = .insertion; new = inner
                case "del": kind = .deletion; old = inner
                default:
                    kind = .substitution
                    if let arrow = inner.range(of: "~>") { old = String(inner[..<arrow.lowerBound]); new = String(inner[arrow.upperBound...]) } else { old = inner }
                }
                let c = comments(after: i + 1, endOfPrev: NSMaxRange(r.range))
                let first = c.list.first { !$0.closing }
                out.suggestions.append(Suggestion(kind: kind, old: old, new: new, id: first?.id, author: first?.author, date: first?.date,
                                                  note: first?.text ?? "", comments: c.list,
                                                  range: NSRange(location: r.range.location, length: c.end - r.range.location)))
                i = c.next
            case "hl":
                let c = comments(after: i + 1, endOfPrev: NSMaxRange(r.range))
                let first = c.list.first { !$0.closing }
                unsignedThreads += first?.id == nil ? 1 : 0
                out.threads.append(Thread(id: first?.id ?? "u\(unsignedThreads)", anchor: ns.substring(with: r.inner), anchorRange: r.inner, comments: c.list,
                                          range: NSRange(location: r.range.location, length: c.end - r.range.location)))
                i = c.next
            case "cm":
                let c = comments(after: i, endOfPrev: r.range.location)
                let first = c.list.first { !$0.closing }
                // A reply that lost its thread's comment: its id's root part names the thread.
                unsignedThreads += first?.id == nil ? 1 : 0
                let id = first?.id.map { String($0.split(separator: ".").first ?? "") } ?? "u\(unsignedThreads)"
                out.threads.append(Thread(id: id, anchor: nil, anchorRange: nil, comments: c.list,
                                          range: NSRange(location: r.range.location, length: c.end - r.range.location)))
                i = c.next
            default: i += 1
            }
        }
        return out
    }

    // MARK: Writing marks

    public static func isoDay(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// An author as the signature spells it: lower case, no spaces (DL-236 2, Q-266).
    public static func signatureName(_ name: String) -> String {
        let s = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "-")
        return s.hasPrefix("@") ? String(s.dropFirst()) : s
    }

    /// `{>>@author date #id: text<<}`. Text can't hold `<<}`.
    public static func comment(author: String, date: String, id: String, text: String) -> String {
        "{>>@\(signatureName(author)) \(date) #\(id): \(text.replacingOccurrences(of: "<<}", with: "< <}").replacingOccurrences(of: "\n", with: " "))<<}"
    }
    public static func closingLine(author: String, date: String, id: String) -> String { "{>>@\(signatureName(author)) \(date) #\(id) closed<<}" }

    public static func insertion(_ text: String) -> String { "{++\(text)++}" }
    public static func deletion(_ text: String) -> String { "{--\(text)--}" }
    public static func substitution(_ old: String, _ new: String) -> String { "{~~\(old)~>\(new)~~}" }
    public static func highlight(_ text: String) -> String { "{==\(text)==}" }

    /// The next free `c<n>` or `s<n>` over every id the document uses.
    public static func nextID(_ prefix: String, in text: String) -> String {
        var top = 0
        let re = try? NSRegularExpression(pattern: "#\(prefix)(\\d+)")
        let ns = text as NSString
        for m in re?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [] {
            top = max(top, Int(ns.substring(with: m.range(at: 1))) ?? 0)
        }
        return "\(prefix)\(top + 1)"
    }

    // MARK: Operations (text in, text out)

    public struct Result: Equatable, Sendable {
        public var text: String
        public var id: String
        public var summary: String
        public init(text: String, id: String, summary: String) { self.text = text; self.id = id; self.summary = summary }
    }

    private static func replacing(_ text: String, _ r: NSRange, _ s: String) -> String { (text as NSString).replacingCharacters(in: r, with: s) }

    /// Where `--at` points: a 1-based line (its trimmed text) or a quoted text (first match outside marks).
    public static func anchorRange(in text: String, at: String) throws -> NSRange {
        let ns = text as NSString
        if let n = Int(at.trimmingCharacters(in: .whitespaces)), n >= 1 {
            var pos = 0, line = 1
            while pos < ns.length, line < n { pos = NSMaxRange(ns.lineRange(for: NSRange(location: pos, length: 0))); line += 1 }
            guard pos < ns.length, line == n else { throw Failure("the document has no line \(n)") }
            var r = ns.lineRange(for: NSRange(location: pos, length: 0))
            while r.length > 0, [0x0A, 0x0D].contains(ns.character(at: NSMaxRange(r) - 1)) { r.length -= 1 }
            let line0 = ns.substring(with: r)
            let lead = line0.count - line0.drop(while: { $0 == " " || $0 == "\t" }).count
            let trimmed = line0.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { throw Failure("line \(n) is empty: name the text with --at \"<text>\"") }
            return NSRange(location: r.location + lead, length: (trimmed as NSString).length)
        }
        let marks = scan(ns).map(\.range) + codeRanges(ns)
        var from = 0, hits: [NSRange] = []
        while from < ns.length {
            let r = ns.range(of: at, range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { break }
            if !marks.contains(where: { NSIntersectionRange($0, r).length > 0 }) { hits.append(r) }
            from = r.location + max(r.length, 1)
        }
        guard let first = hits.first else { throw Failure("“\(at)” isn't in the document (outside marks and code)") }
        guard hits.count == 1 else { throw Failure("“\(at)” appears \(hits.count) times: use a line number, or add words around it") }
        return first
    }

    /// A new thread: the anchor wrapped in a highlight, then the signed comment.
    public static func addComment(to text: String, at: String, author: String, date: String, body: String) throws -> Result {
        let r = try anchorRange(in: text, at: at)
        let id = nextID("c", in: text)
        let anchor = (text as NSString).substring(with: r)
        let new = replacing(text, r, highlight(anchor) + comment(author: author, date: date, id: id, text: body))
        return Result(text: new, id: id, summary: "Commented on “\(abbreviate(anchor))” as #\(id).")
    }

    /// A reply after a thread's (or suggestion's) last comment. With `suggest`, the anchor becomes a
    /// substitution to `body` signed as a new suggestion, and the thread's comments follow it.
    public static func reply(in text: String, to id: String, author: String, date: String, body: String, suggest: Bool = false) throws -> Result {
        let id = id.hasPrefix("#") ? String(id.dropFirst()) : id
        let p = parse(text)
        if suggest {
            guard let t = p.thread(id), let anchor = t.anchor, let ar = t.anchorRange else {
                throw Failure("#\(id) isn't a thread with a highlighted text to suggest a change to")
            }
            let sid = nextID("s", in: text)
            // The highlight becomes a substitution; the signature note is the suggestion's, the thread's comments stay.
            let hlOpen = NSRange(location: t.range.location, length: ar.location - t.range.location)
            let hlClose = NSRange(location: NSMaxRange(ar), length: 3)
            var s = text as NSString
            let sig = comment(author: author, date: date, id: sid, text: "suggested in reply to #\(id)")
            let tail = (s.substring(with: NSRange(location: NSMaxRange(hlClose), length: NSMaxRange(t.range) - NSMaxRange(hlClose))))
            let group = substitution(anchor, body) + sig + tail
            s = s.replacingCharacters(in: NSRange(location: hlOpen.location, length: NSMaxRange(t.range) - hlOpen.location), with: group) as NSString
            return Result(text: s as String, id: sid, summary: "Suggested “\(abbreviate(body))” in place of “\(abbreviate(anchor))” as #\(sid).")
        }
        let comments: [Comment], end: Int, root: String
        if let t = p.thread(id) { comments = t.comments; end = NSMaxRange(t.range); root = id }
        else if let s = p.suggestion(id) { comments = s.comments; end = NSMaxRange(s.range); root = id }
        else { throw Failure("no thread or suggestion #\(id) in the document") }
        // Posting a reply reopens a closed thread: its closing line goes (DL-237).
        var base = text
        var at = end
        if let last = comments.last, last.closing {
            base = replacing(base, last.range, "")
            at = end - last.range.length
        }
        let useID = "\(root).\(nextReplyNumber(comments))"
        let new = replacing(base, NSRange(location: at, length: 0), comment(author: author, date: date, id: useID, text: body))
        return Result(text: new, id: useID, summary: "Replied in #\(root) as #\(useID).")
    }

    /// Close and Keep: a closing line after the thread's last comment; everything stays (Q-262).
    public static func close(in text: String, id: String, author: String, date: String) throws -> Result {
        let id = id.hasPrefix("#") ? String(id.dropFirst()) : id
        guard let t = parse(text).thread(id) else { throw Failure("no thread #\(id) in the document") }
        guard !t.closed else { throw Failure("#\(id) is already closed") }
        let first = t.comments.filter { ($0.id ?? "").contains(".") }.compactMap { Int($0.id!.split(separator: ".").last!) }.max() ?? 0
        let lid = "\(id).\(first + 1)"
        let new = replacing(text, NSRange(location: NSMaxRange(t.range), length: 0), closingLine(author: author, date: date, id: lid))
        return Result(text: new, id: lid, summary: "Closed #\(id); the thread stays in the file.")
    }

    /// Reopen: the closing line goes.
    public static func reopen(in text: String, id: String) throws -> Result {
        let id = id.hasPrefix("#") ? String(id.dropFirst()) : id
        guard let t = parse(text).thread(id) else { throw Failure("no thread #\(id) in the document") }
        guard let line = t.closingLine else { throw Failure("#\(id) isn't closed") }
        return Result(text: replacing(text, line.range, ""), id: id, summary: "Reopened #\(id).")
    }

    /// Delete: the highlight's markers and every comment of the thread go; the text stays.
    public static func delete(in text: String, id: String) throws -> Result {
        let id = id.hasPrefix("#") ? String(id.dropFirst()) : id
        let p = parse(text)
        if let t = p.thread(id) {
            return Result(text: replacing(text, t.range, t.anchor ?? ""), id: id, summary: "Deleted #\(id); the text stays.")
        }
        throw Failure("no thread #\(id) in the document")
    }

    /// Accept or reject a suggestion; its comments go with it.
    public static func resolve(in text: String, id: String, accept: Bool) throws -> Result {
        let id = id.hasPrefix("#") ? String(id.dropFirst()) : id
        guard let s = parse(text).suggestion(id) else { throw Failure("no suggestion #\(id) in the document") }
        let kept = accept ? s.new : s.old
        return Result(text: replacing(text, s.range, kept), id: id, summary: "\(accept ? "Accepted" : "Rejected") #\(id).")
    }

    public static func resolveAll(in text: String, accept: Bool, author: String? = nil) -> (text: String, count: Int) {
        var t = text, n = 0
        while let s = parse(t).suggestions.last(where: { author == nil || $0.author == author.map(signatureName) }) {
            t = replacing(t, s.range, accept ? s.new : s.old); n += 1
            if n > 10_000 { break }
        }
        return (t, n)
    }

    /// The number after the highest `.n` any comment of the thread has.
    static func nextReplyNumber(_ comments: [Comment]) -> Int {
        (comments.compactMap { $0.id }.filter { $0.contains(".") }.compactMap { Int($0.split(separator: ".").last ?? "") }.max() ?? 0) + 1
    }

    public static func abbreviate(_ s: String) -> String { s.count > 40 ? String(s.prefix(37)) + "…" : s }

    // MARK: Suggest Edits (DL-237)

    /// Whether the frontmatter says `suggest-edits: true`.
    public static func suggestEdits(_ text: String) -> Bool {
        guard let fm = frontmatterRange(text) else { return false }
        let body = (text as NSString).substring(with: fm)
        return body.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == "suggest-edits: true" }
    }

    /// The text between the `---` lines, if the document starts with frontmatter.
    static func frontmatterRange(_ text: String) -> NSRange? {
        let ns = text as NSString
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return nil }
        let start = ns.lineRange(for: NSRange(location: 0, length: 0)).length
        var pos = start
        while pos < ns.length {
            let l = ns.lineRange(for: NSRange(location: pos, length: 0))
            if ns.substring(with: l).trimmingCharacters(in: .whitespacesAndNewlines) == "---" { return NSRange(location: start, length: l.location - start) }
            pos = NSMaxRange(l)
        }
        return nil
    }

    /// The switch on or off: the line is written only while on, and removed when off (a document that
    /// never used it is never touched). Frontmatter is made when there is none and the switch goes on.
    public static func settingSuggestEdits(_ text: String, on: Bool) -> String {
        let ns = text as NSString
        if let fm = frontmatterRange(text) {
            var lines = ns.substring(with: fm).components(separatedBy: "\n")
            let isLine: (String) -> Bool = { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("suggest-edits:") }
            if on {
                if let i = lines.firstIndex(where: isLine) { lines[i] = "suggest-edits: true" }
                else {
                    // Before the closing `---`: the last element of a block that ends in "\n" is "".
                    let at = lines.last == "" ? lines.count - 1 : lines.count
                    lines.insert("suggest-edits: true", at: at)
                }
            } else { lines.removeAll(where: isLine) }
            return ns.replacingCharacters(in: fm, with: lines.joined(separator: "\n"))
        }
        return on ? "---\nsuggest-edits: true\n---\n" + (text.isEmpty || text.hasPrefix("\n") ? "" : "\n") + text : text
    }

    // MARK: The paragraph every Duo session gets (DL-236 7, DL-237)

    /// What Duo's context hook tells each session about review marks. Its own section: other
    /// additions to the primer don't touch it. Research §3.3's tested paragraph (B1), plus the closing
    /// line (Q-262), the `suggest-edits` frontmatter (DL-237) and the verbs.
    public static let convention = """
    Duo reviews: review marks in Markdown use CriticMarkup with a signature: {++added++}, {--deleted--}, {~~old~>new~~}, {==highlight==}, each followed by {>>@author date #id: note<<}. Marks are suggestions awaiting a person's decision: never accept or reject one, and never close a thread, unless asked in so many words; "deal with the review" means answering what is addressed to you, not resolving it. To propose an edit, write it as a mark signed @claude instead of changing text. Reply to a comment by adding {>>@claude date #id.n: reply<<} right after it (`duo2 comment reply <id> <text>` does it in Duo's editor if the file is open); don't delete or rewrite anyone's comment. To close a thread, add {>>@claude date #id.n closed<<} after its last comment; never delete someone's comment. A comment that names @claude is addressed to you. If the file's frontmatter has `suggest-edits: true`, write every change as a signed mark.
    """
}
